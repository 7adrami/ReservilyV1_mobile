import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../core/constants.dart';

/// Pure-Dart port of the web app's end-to-end chat crypto (static/js/chat.js).
///
/// Must produce byte-identical results so a Flutter client and the web app can
/// talk to each other:
///  - identity: ECDH P-256; private key kept as a JWK map, public key as base64
///    SPKI DER.
///  - conversation key: ECDH shared secret -> HKDF-SHA256 (salt = sorted
///    usernames joined with ':', info = "reservily-chat-v1").
///  - messages & reactions: AES-256-GCM with a random 12-byte nonce.
///  - media: AES-256-GCM under a random per-file key carried inside the
///    encrypted message payload.
///  - vault: PBKDF2-SHA256 (150000 iters) -> AES-256-GCM wraps the identity.
class ChatCrypto {
  ChatCrypto._();

  static final Random _random = Random.secure();
  static final ECDomainParameters _p256 = ECDomainParameters('secp256r1');

  /// NIST P-256 field size in bytes (private scalar and coordinates).
  static const int _coordBytes = 32;

  // --------------------------------------------------------------- helpers

  static Uint8List randomBytes(int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  static String bytesToB64(List<int> bytes) => base64Encode(bytes);

  static Uint8List b64ToBytes(String b64) => base64Decode(b64);

  static String _b64url(List<int> bytes) => base64Url.encode(bytes);

  static Uint8List _b64urlDecode(String s) => base64Url.decode(
      s.padRight(s.length + ((4 - s.length % 4) % 4), '='));

  static List<int> _utf8(String s) => utf8.encode(s);

  /// [myUsername] and [otherUsername] sorted (same as JS [a,b].sort().join(':')).
  static String conversationSalt(String a, String b) {
    final list = [a, b]..sort();
    return list.join(':');
  }

  static List<String> candidateSalts(String myUsername, String otherUsername) {
    // Mirror chat.js: keep the legacy "…:undefined" fallbacks so messages
    // produced by the old asymmetric-salt bug still decrypt.
    return [
      conversationSalt(myUsername, otherUsername),
      '$myUsername:undefined',
      '$otherUsername:undefined',
    ];
  }

  // ------------------------------------------------------------ AES-GCM

  static Uint8List _aesGcm({
    required List<int> key,
    required List<int> nonce,
    required List<int> data,
    required bool encrypt,
  }) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      encrypt,
      AEADParameters<KeyParameter>(KeyParameter(Uint8List.fromList(key)), 128,
          Uint8List.fromList(nonce), Uint8List(0)),
    );
    return cipher.process(Uint8List.fromList(data));
  }

  static Uint8List aesGcmEncrypt(
          List<int> key, List<int> nonce, List<int> plaintext) =>
      _aesGcm(key: key, nonce: nonce, data: plaintext, encrypt: true);

  /// [ciphertext] must include the 16-byte auth tag (as produced by WebCrypto).
  static Uint8List aesGcmDecrypt(
          List<int> key, List<int> nonce, List<int> ciphertext) =>
      _aesGcm(key: key, nonce: nonce, data: ciphertext, encrypt: false);

  // --------------------------------------------------------------- HKDF

  static Uint8List hkdfSha256({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
    int length = 32,
  }) {
    final derivator = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(
        Uint8List.fromList(ikm),
        length,
        Uint8List.fromList(salt),
        Uint8List.fromList(info),
      ));
    final out = Uint8List(length);
    derivator.deriveKey(null, 0, out, 0);
    return out;
  }

  // -------------------------------------------------------------- PBKDF2

  static Uint8List pbkdf2Sha256({
    required String password,
    required List<int> salt,
    int iterations = AppConfig.kekIterations,
    int length = 32,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, length));
    return derivator.process(Uint8List.fromList(_utf8(password)));
  }

  // --------------------------------------------------------- identity keys

  /// Generates an ECDH P-256 keypair as the JS WebCrypto export would:
  /// `priv` = JWK map, `pub` = base64 SPKI.
  static Map<String, dynamic> generateIdentity() {
    final random = _seededRandom();
    final generator = ECKeyGenerator()
      ..init(ParametersWithRandom(
        ECKeyGeneratorParameters(_p256),
        random,
      ));
    final pair = generator.generateKeyPair();
    final priv = pair.privateKey;
    final pub = pair.publicKey;
    return {
      'priv': _toJwk(priv),
      'pub': bytesToB64(_spkiEncode(pub.Q!)),
    };
  }

  static FortunaRandom _seededRandom() {
    final rng = FortunaRandom();
    final seed = Uint8List.fromList(randomBytes(32));
    rng.seed(KeyParameter(seed));
    return rng;
  }

  /// Big-endian fixed-width encoding (pads to [width] bytes).
  static Uint8List _fixed(BigInt value, int width) {
    final bytes = Uint8List(width);
    final raw = value.toUnsigned(width * 8).toRadixString(16).padLeft(width * 2, '0');
    final rawBytes = _hexDecode(raw);
    bytes.setRange(width - rawBytes.length, width, rawBytes);
    return bytes;
  }

  static Uint8List _hexDecode(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// Builds the JWK map WebCrypto can import (P-256, base64url, unpadded).
  static Map<String, dynamic> _toJwk(ECPrivateKey priv) {
    final q = (_p256.G * priv.d!)!;
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': _b64url(_fixed(q.x!.toBigInteger()!, _coordBytes)),
      'y': _b64url(_fixed(q.y!.toBigInteger()!, _coordBytes)),
      'd': _b64url(_fixed(priv.d!, _coordBytes)),
    };
  }

  /// Imports a stored JWK private key (as produced by _toJwk or WebCrypto).
  static ECPrivateKey _importJwk(Map<String, dynamic> jwk) {
    final d = BigInt.parse(_b64urlDecode(jwk['d'] as String).fold(
        '', (acc, b) => acc + b.toRadixString(16).padLeft(2, '0')), radix: 16);
    return ECPrivateKey(d, _p256);
  }

  /// Parses a base64 SPKI DER public key and returns the P-256 point.
  static ECPoint _spkiDecode(String spkiB64) {
    final der = base64Decode(spkiB64);
    final reader = _DerReader(der);
    final outerTag = reader.readByte();
    if (outerTag != 0x30) throw ArgumentError('Invalid SPKI');
    reader.readLength();
    final algTag = reader.readByte(); // SEQUENCE (algorithm)
    if (algTag != 0x30) throw ArgumentError('Invalid SPKI');
    reader.readLength();
    // Skip the two OIDs inside the algorithm identifier.
    for (var i = 0; i < 2; i++) {
      if (reader.readByte() != 0x06) throw ArgumentError('Invalid SPKI');
      reader.readLength();
      reader.skip(reader.lastLength);
    }
    final bitTag = reader.readByte(); // BIT STRING
    if (bitTag != 0x03) throw ArgumentError('Invalid SPKI');
    reader.readLength();
    reader.skip(1); // unused-bits octet
    final point = der.sublist(reader.pos, reader.pos + reader.lastLength - 1);
    return _p256.curve.decodePoint(point)!;
  }

  /// Encodes a public point as SPKI DER (matching WebCrypto exportKey).
  static Uint8List _spkiEncode(ECPoint q) {
    final x = _fixed(q.x!.toBigInteger()!, _coordBytes);
    final y = _fixed(q.y!.toBigInteger()!, _coordBytes);
    final point = Uint8List(1 + x.length + y.length);
    point[0] = 4;
    point.setRange(1, 1 + x.length, x);
    point.setRange(1 + x.length, point.length, y);

    const oidEcPublicKey = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01];
    const oidP256 = [0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07];

    final algId = _derSeq([
      ..._derTlv(0x06, oidEcPublicKey),
      ..._derTlv(0x06, oidP256),
    ]);
    final bitString = _derTlv(0x03, [0x00, ...point]);
    return Uint8List.fromList(_derSeq([...algId, ...bitString]));
  }

  static List<int> _derTlv(int tag, List<int> content) => [
        tag,
        ..._derLength(content.length),
        ...content,
      ];

  static List<int> _derSeq(List<int> content) => _derTlv(0x30, content);

  static List<int> _derLength(int len) {
    if (len < 0x80) return [len];
    final hex = len.toRadixString(16).padLeft(2, '0');
    final bytes = _hexDecode(hex.length.isEven ? hex : '0$hex');
    return [0x80 | bytes.length, ...bytes];
  }

  // ------------------------------------------------------------- vault

  static Uint8List deriveKek(String password, String saltB64) {
    return pbkdf2Sha256(password: password, salt: b64ToBytes(saltB64));
  }

  /// Wraps the identity (JSON like the web app stores) with the password KEK.
  static Map<String, String> wrapIdentity(
      Map<String, dynamic> identity, String saltB64, List<int> kek) {
    final iv = randomBytes(AppConfig.aesIvBytes);
    final data = _utf8(jsonEncode(identity));
    final ct = aesGcmEncrypt(kek, iv, data);
    return {
      'salt': saltB64,
      'iv': bytesToB64(iv),
      'wrapped': bytesToB64(ct),
    };
  }

  static Map<String, dynamic> unwrapIdentity(
      String saltB64, String ivB64, String wrappedB64, List<int> kek) {
    final plain = aesGcmDecrypt(
      kek,
      b64ToBytes(ivB64),
      b64ToBytes(wrappedB64),
    );
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  // ------------------------------------------------------- conversation key

  /// ECDH + HKDF conversation key, matching WebCrypto's deriveBits/deriveKey.
  static Uint8List deriveConversationKey(
      Map<String, dynamic> myJwk, String otherPubB64, String salt) {
    final myPriv = _importJwk(myJwk);
    final otherPoint = _spkiDecode(otherPubB64);
    final agreement = ECDHBasicAgreement()..init(myPriv);
    final secret = agreement.calculateAgreement(ECPublicKey(otherPoint, _p256));
    final bits = _fixed(secret, _coordBytes);
    return hkdfSha256(
      ikm: bits,
      salt: _utf8(salt),
      info: _utf8(AppConfig.saltInfo),
    );
  }

  // ------------------------------------------------------------- payloads

  static (String ciphertext, String nonce) encryptPayload(
      List<int> key, Map<String, dynamic> payload) {
    final iv = randomBytes(AppConfig.aesIvBytes);
    final ct = aesGcmEncrypt(key, iv, _utf8(jsonEncode(payload)));
    return (bytesToB64(ct), bytesToB64(iv));
  }

  static Map<String, dynamic> decryptPayload(
      List<int> key, String ciphertext, String nonce) {
    final plain = aesGcmDecrypt(key, b64ToBytes(nonce), b64ToBytes(ciphertext));
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  // ------------------------------------------- background-isolate helpers
  //
  // These are pure (no platform channels) so they can run inside `compute()`
  // and keep the expensive PBKDF2/ECDH/AES work off the UI thread.

  /// Derives the account KEK and unwraps the vault identity in an isolate.
  static Map<String, dynamic> unwrapIdentityInIsolate(
      Map<String, dynamic> args) {
    final salt = args['salt'] as String;
    final iv = args['iv'] as String;
    final wrapped = args['wrapped'] as String;
    final password = args['password'] as String;
    final kek = pbkdf2Sha256(password: password, salt: b64ToBytes(salt));
    return unwrapIdentity(salt, iv, wrapped, kek);
  }

  /// Derives the account KEK and wraps the identity for backup in an isolate.
  static Map<String, String> wrapIdentityInIsolate(Map<String, dynamic> args) {
    final salt = args['salt'] as String;
    final password = args['password'] as String;
    final kek = pbkdf2Sha256(password: password, salt: b64ToBytes(salt));
    return wrapIdentity(args['identity'] as Map<String, dynamic>, salt, kek);
  }

  /// Derives every conversation-key candidate (priv x pub x salt) in an
  /// isolate and returns base64 keys plus the index of the active key.
  static Map<String, dynamic> deriveConversationKeysInIsolate(
      Map<String, dynamic> args) {
    final candidates =
        (args['candidates'] as List).cast<Map<String, dynamic>>();
    final pubs = (args['pubs'] as List).cast<String>();
    final salts = (args['salts'] as List).cast<String>();
    final flat = <String>[];
    for (final priv in candidates) {
      for (final pub in pubs) {
        for (final salt in salts) {
          flat.add(bytesToB64(deriveConversationKey(priv, pub, salt)));
        }
      }
    }
    final activeLatestIdx = (pubs.length - 1) * salts.length;
    return {'keys': flat, 'activeIndex': activeLatestIdx};
  }

  /// Decrypts many message payloads in an isolate, trying every key per item.
  /// A null entry means the message could not be decrypted with any key.
  static List<Map<String, dynamic>?> decryptPayloadsInIsolate(
      Map<String, dynamic> args) {
    final keysB64 = (args['keys'] as List).cast<String>();
    final items = (args['items'] as List).cast<Map<String, dynamic>>();
    final keys = keysB64.map(b64ToBytes).toList();
    return items.map((item) {
      final ct = item['ciphertext'] as String;
      final nonce = item['nonce'] as String;
      for (final key in keys) {
        try {
          return decryptPayload(key, ct, nonce);
        } catch (_) {}
      }
      return null;
    }).toList();
  }

  // --------------------------------------------------------------- media

  /// Encrypts raw file bytes with a fresh random key; returns key/iv as base64
  /// plus the ciphertext (which the server stores as the file).
  static ({String key, String iv, Uint8List ciphertext}) encryptFileBytes(
      List<int> bytes) {
    final key = randomBytes(32);
    final iv = randomBytes(AppConfig.aesIvBytes);
    final ct = aesGcmEncrypt(key, iv, bytes);
    return (key: bytesToB64(key), iv: bytesToB64(iv), ciphertext: ct);
  }

  static Uint8List decryptFileBytes(
      String keyB64, String ivB64, List<int> ciphertext) {
    return aesGcmDecrypt(b64ToBytes(keyB64), b64ToBytes(ivB64), ciphertext);
  }
}

/// Minimal DER reader used to parse SPKI public keys.
class _DerReader {
  _DerReader(this.data);

  final Uint8List data;
  int pos = 0;
  int lastLength = 0;

  int readByte() => data[pos++];

  int readLength() {
    final b = readByte();
    if (b < 0x80) {
      lastLength = b;
      return b;
    }
    var len = 0;
    final count = b & 0x7f;
    for (var i = 0; i < count; i++) {
      len = (len << 8) | readByte();
    }
    lastLength = len;
    return len;
  }

  void skip(int n) => pos += n;
}
