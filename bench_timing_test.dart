import 'package:flutter_test/flutter_test.dart';
import 'package:reservily/core/constants.dart';
import 'package:reservily/services/chat_crypto.dart';

void main() {
  test('timing: pbkdf2 unwrap + ecdh', () async {
    final identity = ChatCrypto.generateIdentity();

    final salt = ChatCrypto.randomBytes(16);
    final kek = ChatCrypto.deriveKek('hunter2', ChatCrypto.bytesToB64(salt));
    final wrapped =
        ChatCrypto.wrapIdentity(identity, ChatCrypto.bytesToB64(salt), kek);
    final t0 = DateTime.now();
    await ChatCrypto.unwrapIdentityInIsolate({
      'salt': wrapped['salt'],
      'iv': wrapped['iv'],
      'wrapped': wrapped['wrapped'],
      'password': 'hunter2',
    });
    final t1 = DateTime.now();
    print('PBKDF2-150k unwrap: ${t1.difference(t0).inMilliseconds} ms');

    final other = ChatCrypto.generateIdentity();
    final t2 = DateTime.now();
    await ChatCrypto.deriveConversationKeyInIsolate({
      'priv': identity['priv'],
      'pub': other['pub'],
      'salts': ChatCrypto.candidateSalts('alice', 'bob'),
    });
    final t3 = DateTime.now();
    print('ECDH derive: ${t3.difference(t2).inMilliseconds} ms');

    final t4 = DateTime.now();
    await ChatCrypto.deriveConversationKeysInIsolate({
      'candidates': [identity['priv']],
      'pubs': [other['pub']],
      'salts': ChatCrypto.candidateSalts('alice', 'bob'),
    });
    final t5 = DateTime.now();
    print('Full derivation: ${t5.difference(t4).inMilliseconds} ms');
  });
}
