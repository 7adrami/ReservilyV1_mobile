import 'package:reservily/core/constants.dart';
import 'package:reservily/services/chat_crypto.dart';

Future<void> main() async {
  final identity = ChatCrypto.generateIdentity();

  // 1) PBKDF2(150k) + AES-GCM unwrap cost
  final wrapped = ChatCrypto.wrapIdentity(identity, 'hunter2');
  final t0 = DateTime.now();
  final unwrapped = await ChatCrypto.unwrapIdentityInIsolate({
    'salt': wrapped['salt'],
    'iv': wrapped['iv'],
    'wrapped': wrapped['wrapped'],
    'password': 'hunter2',
  });
  final t1 = DateTime.now();
  print('PBKDF2-150k unwrap: ${t1.difference(t0).inMilliseconds} ms');

  // 2) one ECDH conversation-key derivation
  final other = ChatCrypto.generateIdentity();
  final t2 = DateTime.now();
  final key = await ChatCrypto.deriveConversationKeyInIsolate({
    'priv': identity['priv'],
    'pub': other['pub'],
    'salts': ChatCrypto.candidateSalts('alice', 'bob'),
  });
  final t3 = DateTime.now();
  print('ECDH derive: ${t3.difference(t2).inMilliseconds} ms, key=$key');

  // 3) full candidate x pub x salt derivation
  final t4 = DateTime.now();
  final full = await ChatCrypto.deriveConversationKeysInIsolate({
    'candidates': [identity['priv']],
    'pubs': [other['pub']],
    'salts': ChatCrypto.candidateSalts('alice', 'bob'),
  });
  final t5 = DateTime.now();
  print('Full derivation: ${t5.difference(t4).inMilliseconds} ms');
}
