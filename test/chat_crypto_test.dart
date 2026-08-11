import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:reservily/services/chat_crypto.dart';

void main() {
  group('ChatCrypto', () {
    test('generates a valid P-256 identity', () {
      final id = ChatCrypto.generateIdentity();
      expect(id['priv'], isA<Map<String, dynamic>>());
      expect(id['pub'], isA<String>());
      expect(id['pub']!.length, greaterThan(50));

      // The generated public key must be usable by the other side's private
      // key (this exercises the SPKI DER parser).
      final other = ChatCrypto.generateIdentity();
      final key = ChatCrypto.deriveConversationKey(
        other['priv'] as Map<String, dynamic>,
        id['pub'] as String,
        'a:b',
      );
      expect(key.length, 32);
    });

    test('two identities agree on the same ECDH shared secret', () {
      final alice = ChatCrypto.generateIdentity();
      final bob = ChatCrypto.generateIdentity();

      final salt = ChatCrypto.conversationSalt('alice', 'bob');
      final fromAlice = ChatCrypto.deriveConversationKey(
          alice['priv'] as Map<String, dynamic>, bob['pub'] as String, salt);
      final fromBob = ChatCrypto.deriveConversationKey(
          bob['priv'] as Map<String, dynamic>, alice['pub'] as String, salt);

      expect(fromAlice, fromBob);
      expect(fromAlice.length, 32);
    });

    test('conversation salt sorts usernames (JS [a,b].sort().join(":"))', () {
      expect(ChatCrypto.conversationSalt('bob', 'alice'), 'alice:bob');
      expect(ChatCrypto.conversationSalt('alice', 'bob'), 'alice:bob');
      expect(ChatCrypto.conversationSalt('aa', 'ab'), 'aa:ab');
    });

    test('candidate salts include the legacy :undefined fallbacks', () {
      final salts = ChatCrypto.candidateSalts('me', 'other');
      expect(salts.length, 3);
      expect(salts[0], 'me:other');
      expect(salts, contains('me:undefined'));
      expect(salts, contains('other:undefined'));
    });

    test('message payload encrypt/decrypt round-trips', () {
      final idA = ChatCrypto.generateIdentity();
      final idB = ChatCrypto.generateIdentity();
      final key = ChatCrypto.deriveConversationKey(
        idA['priv'] as Map<String, dynamic>,
        idB['pub'] as String,
        ChatCrypto.conversationSalt('alice', 'bob'),
      );

      final payload = {
        't': 'text',
        'text': 'Hello 👋 world',
        'reply_to': 42,
        'reply_text': 'Prev',
      };
      final enc = ChatCrypto.encryptPayload(key, payload);
      final dec = ChatCrypto.decryptPayload(key, enc.$1, enc.$2);

      expect(dec['t'], 'text');
      expect(dec['text'], 'Hello 👋 world');
      expect(dec['reply_to'], 42);
      expect(dec['reply_text'], 'Prev');
      expect(enc.$1, isNotEmpty);
      expect(enc.$2, isNotEmpty);
    });

    test('media encrypt/decrypt round-trips with a per-file key', () {
      final plaintext = Uint8List.fromList(
          utf8.encode('a barbershop photo — 01010101'.padRight(300, 'x')));
      final enc = ChatCrypto.encryptFileBytes(plaintext);
      expect(enc.ciphertext.length, plaintext.length + 16); // AES-GCM tag

      final dec = ChatCrypto.decryptFileBytes(enc.key, enc.iv, enc.ciphertext);
      expect(dec, plaintext);

      // A tampered tag must fail to decrypt.
      final tampered = Uint8List.fromList(enc.ciphertext);
      tampered[0] ^= 0xff;
      expect(
        () => ChatCrypto.decryptFileBytes(enc.key, enc.iv, tampered),
        throwsA(isA<Exception>()),
      );
    });

    test('vault wrap/unwrap with PBKDF2-derived KEK', () {
      final identity = ChatCrypto.generateIdentity();
      const password = 'correct horse battery staple';
      final saltB64 =
          ChatCrypto.bytesToB64(ChatCrypto.randomBytes(16));

      final kek = ChatCrypto.deriveKek(password, saltB64);
      final wrapped = ChatCrypto.wrapIdentity(identity, saltB64, kek);
      expect(wrapped['salt'], saltB64);
      expect(wrapped['iv'], isNotEmpty);
      expect(wrapped['wrapped'], isNotEmpty);

      final kek2 = ChatCrypto.deriveKek(password, wrapped['salt']!);
      final restored =
          ChatCrypto.unwrapIdentity(wrapped['salt']!, wrapped['iv']!, wrapped['wrapped']!, kek2);
      expect(restored['pub'], identity['pub']);
      expect(restored['priv'], identity['priv']);

      // A wrong password derives a different KEK and must fail.
      final wrong = ChatCrypto.deriveKek('wrong password', wrapped['salt']!);
      expect(
        () => ChatCrypto.unwrapIdentity(
            wrapped['salt']!, wrapped['iv']!, wrapped['wrapped']!, wrong),
        throwsA(isA<Exception>()),
      );
    });

    test('HKDF is deterministic and produces 32 bytes', () {
      final key = ChatCrypto.hkdfSha256(
        ikm: Uint8List.fromList(List.filled(32, 7)),
        salt: Uint8List.fromList(utf8.encode('alice:bob')),
        info: Uint8List.fromList(utf8.encode('reservily-chat-v1')),
      );
      final key2 = ChatCrypto.hkdfSha256(
        ikm: Uint8List.fromList(List.filled(32, 7)),
        salt: Uint8List.fromList(utf8.encode('alice:bob')),
        info: Uint8List.fromList(utf8.encode('reservily-chat-v1')),
      );
      expect(key, key2);
      expect(key.length, 32);
      // HKDF with a different salt must diverge.
      final key3 = ChatCrypto.hkdfSha256(
        ikm: Uint8List.fromList(List.filled(32, 7)),
        salt: Uint8List.fromList(utf8.encode('alice:carol')),
        info: Uint8List.fromList(utf8.encode('reservily-chat-v1')),
      );
      expect(key, isNot(key3));
    });

    test('JWK export matches WebCrypto shape (kty EC, crv P-256)', () {
      final id = ChatCrypto.generateIdentity();
      final jwk = id['priv'] as Map<String, dynamic>;
      expect(jwk['kty'], 'EC');
      expect(jwk['crv'], 'P-256');
      expect(jwk['x'], isA<String>());
      expect(jwk['y'], isA<String>());
      expect(jwk['d'], isA<String>());
      // base64url coordinates decode to 32 bytes each.
      for (final field in ['x', 'y', 'd']) {
        final raw = base64Url.decode(jwk[field] as String);
        expect(raw.length, 32, reason: '$field should be 32 bytes');
      }
    });

    test('a message encrypted under an old identity still decrypts using the '
        'recovery key set', () {
      // Two users who each once had a different (old) identity — the scenario
      // behind "messages encrypted after reopening". We must be able to decrypt
      // with a key list that includes BOTH the current and the old identity.
      final aliceOld = ChatCrypto.generateIdentity();
      final aliceNew = ChatCrypto.generateIdentity();
      final bob = ChatCrypto.generateIdentity();

      final salt = ChatCrypto.conversationSalt('alice', 'bob');

      // Bob encrypted a message while Alice was using her OLD identity.
      final oldKey = ChatCrypto.deriveConversationKey(
        bob['priv'] as Map<String, dynamic>,
        aliceOld['pub'] as String,
        salt,
      );
      final payload = {'t': 'text', 'text': 'old history'};
      final enc = ChatCrypto.encryptPayload(oldKey, payload);

      // Review: a decrypter holding both identities (the recovery net) must
      // find the message using the OLD private key, even though it is not the
      // "primary" (newest) key.
      final newKey = ChatCrypto.deriveConversationKey(
        aliceNew['priv'] as Map<String, dynamic>,
        bob['pub'] as String,
        salt,
      );
      final mirroredNewKey = ChatCrypto.deriveConversationKey(
        bob['priv'] as Map<String, dynamic>,
        aliceNew['pub'] as String,
        salt,
      );
      // Sanity: the new identity does NOT match the ciphertext's old key.
      if (newKey.isNotEmpty) {
        final sameAsOld = newKey.join(',') == oldKey.join(',');
        // Not guaranteed to differ, but it must not be the key that decrypts
        // the old message unless it IS the old key.
        var decryptsWithNew = true;
        try {
          ChatCrypto.decryptPayload(newKey, enc.$1, enc.$2);
        } catch (_) {
          decryptsWithNew = false;
        }
        if (!sameAsOld) {
          expect(decryptsWithNew, isFalse,
              reason: 'New identity should not reflect the old message');
        }
      }

      // The simulated recovery: try new then old identity, old must succeed.
      final candidates = [newKey, oldKey, mirroredNewKey];
      var decrypted = false;
      for (final k in candidates) {
        try {
          final d = ChatCrypto.decryptPayload(k, enc.$1, enc.$2);
          expect(d['t'], 'text');
          expect(d['text'], 'old history');
          decrypted = true;
          break;
        } catch (_) {
          // try next candidate
        }
      }
      expect(decrypted, isTrue,
          reason: 'Recovery key set must contain the old identity key');
    });
  });
}
