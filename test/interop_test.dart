import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reservily/services/chat_crypto.dart';

/// Cross-language interop: proves the Dart port produces ciphertexts a
/// standards-compliant implementation (Python `cryptography`, same primitives
/// as WebCrypto) can decode, and that Dart can decode theirs.
void main() {
  test('Dart <-> Python crypto interop', () async {
    final tempDir = await Directory.systemTemp.createTemp('reservily_interop');
    addTearDown(() => tempDir.delete(recursive: true));

    final dartFixture = <String, dynamic>{};
    final alice = ChatCrypto.generateIdentity();
    final bob = ChatCrypto.generateIdentity();
    const salt = 'alice:bob';

    final key = ChatCrypto.deriveConversationKey(
      alice['priv'] as Map<String, dynamic>,
      bob['pub'] as String,
      salt,
    );

    const text = 'Hello from Dart 👋 — interop check 123';
    final (ct, nonce) =
        ChatCrypto.encryptPayload(key, {'t': 'text', 'text': text});

    final mediaPlain =
        utf8.encode('barbershop-photo-2026-42'.padRight(400, 'x'));
    final media = ChatCrypto.encryptFileBytes(mediaPlain);

    const password = 'correct horse battery staple';
    final vaultSaltB64 =
        ChatCrypto.bytesToB64(ChatCrypto.randomBytes(16));
    final vaultKek = ChatCrypto.deriveKek(password, vaultSaltB64);
    final vault = ChatCrypto.wrapIdentity(alice, vaultSaltB64, vaultKek);

    dartFixture
      ..['salt'] = salt
      ..['alice_pub_spki'] = alice['pub']
      ..['alice_priv_jwk'] = alice['priv']
      ..['bob_priv_jwk'] = bob['priv']
      ..['bob_pub_spki'] = bob['pub']
      ..['text'] = text
      ..['dart_payload_ct'] = ct
      ..['dart_payload_nonce'] = nonce
      ..['media_key'] = media.key
      ..['media_iv'] = media.iv
      ..['media_ct'] = ChatCrypto.bytesToB64(media.ciphertext)
      ..['media_plain'] = base64Encode(mediaPlain)
      ..['vault_salt'] = vault['salt']
      ..['vault_iv'] = vault['iv']
      ..['vault_ct'] = vault['wrapped']
      ..['vault_password'] = password;

    final dartFile = File('${tempDir.path}/dart_fixture.json');
    final pythonFile = File('${tempDir.path}/python_fixture.json');
    dartFile.writeAsStringSync(jsonEncode(dartFixture));

    final result = await Process.run(
      'py',
      [
        'tool/interop/verify_python.py',
        dartFile.path,
        pythonFile.path,
      ],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect('${result.stdout}', contains('PYTHON INTEROP PASS'));

    // Decrypt the Python-produced fixtures.
    final py =
        jsonDecode(pythonFile.readAsStringSync()) as Map<String, dynamic>;
    // Dart pairs Python's private key with our own public key — the same
    // pairing Python used to derive its encryption key.
    final pyKey = ChatCrypto.deriveConversationKey(
      py['py_priv_jwk'] as Map<String, dynamic>,
      dartFixture['alice_pub_spki'] as String,
      salt,
    );
    expect(base64Encode(pyKey), py['py_key_b64']);
    final pyPayload = ChatCrypto.decryptPayload(
      pyKey,
      py['py_payload_ct'] as String,
      py['py_payload_nonce'] as String,
    );
    expect(pyPayload['text'], 'Hello from Python');

    final pyMedia = ChatCrypto.decryptFileBytes(
      py['py_media_key'] as String,
      py['py_media_iv'] as String,
      ChatCrypto.b64ToBytes(py['py_media_ct'] as String),
    );
    expect(utf8.decode(pyMedia), 'python-media-bytes-2026');

    final pyKek = ChatCrypto.deriveKek(
      py['py_vault_password'] as String,
      py['py_vault_salt'] as String,
    );
    final pyIdentity = ChatCrypto.unwrapIdentity(
      py['py_vault_salt'] as String,
      py['py_vault_iv'] as String,
      py['py_vault_ct'] as String,
      pyKek,
    );
    expect(pyIdentity['crv'], 'P-256');
    expect(pyIdentity['x'], py['py_priv_jwk']['x']);
  });
}
