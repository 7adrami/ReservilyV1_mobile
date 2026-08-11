import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/api_client.dart';
import '../core/constants.dart';
import '../models/chat.dart';
import 'chat_crypto.dart';

/// Result of asking the user for their account password to restore a key backup.
enum VaultPromptResult { unlocked, reset, cancelled }

class VaultPrompt {
  const VaultPrompt({required this.result, this.password});
  final VaultPromptResult result;
  final String? password;
}

typedef VaultPasswordPrompt = Future<VaultPrompt> Function(
    {required String message});

/// Manages the per-account ECDH identity, its password-wrapped server backup
/// and the "delete for me" hidden-message set. Mirrors static/js/chat.js.
class ChatIdentity {
  ChatIdentity({required this.api, FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final ApiClient api;
  final FlutterSecureStorage _storage;

  static const _identityPrefix = 'reservily_chat_identity_v1:';
  static const _hiddenKey = 'reservily_chat_hidden_v1';
  static const _convoKeysKey = 'reservily_convo_keys_v1';

  Map<String, dynamic>? _identity;
  String? _username;
  String? _sessionPassword;
  Set<int> _hidden = {};
  Map<String, dynamic> _convoKeys = const {};
  bool _convoLoaded = false;

  /// Public key we last wrapped into the server backup this session, so repeat
  /// chat opens skip the expensive PBKDF2 re-wrap.
  String? _lastSyncedPub;
  /// True once the best-effort backup refresh was scheduled this session.
  bool _syncScheduled = false;

  Map<String, dynamic>? get identity => _identity;
  String? get publicKey => _identity?['pub'] as String?;
  bool get hasIdentity => _identity != null;

  String _identityKey(String username) => '$_identityPrefix$username';

  /// Loads (or generates + restores) the identity for [username], keeps the
  /// server key list current and refreshes the password backup when possible.
  ///
  /// [passwordPrompt] is used only when a backup exists on the server but no
  /// key is stored on this device.
  Future<Map<String, dynamic>> ensureIdentity({
    required String username,
    VaultPasswordPrompt? passwordPrompt,
  }) async {
    // Fast path: this session already resolved the identity for this account.
    // The vault fetch + PBKDF2 unwrap + key re-upload only need to happen once.
    if (_identity != null && _username == username) {
      return _identity!;
    }
    _username = username;
    await _loadHidden();
    final t0 = DateTime.now();

    final key = _identityKey(username);
    final stored = await _readIdentity(key);
    // Fetch the vault in the background: the fast path below does not need it,
    // and the unlock path awaits it (already resolved by then on slow links).
    final vaultFuture = _fetchVault();
    Map<String, dynamic>? identity;

    if (stored != null && !await _serverKeyDiffersFrom(stored['pub'] as String?)) {
      // Fast path: the key stored on THIS device is already the server's
      // canonical key -- skip the vault fetch, PBKDF2 unwrap and password
      // prompt entirely (mirrors the web app, which never asks when it has a
      // matching local identity). The vault is only consulted when the local
      // key is stale (identity rotated on another device) or absent.
      identity = stored;
      debugPrint('[identity] fast path (local key matches server) '
          'in ${DateTime.now().difference(t0).inMilliseconds}ms');
    } else {
      final vault = await vaultFuture;
      if (vault != null) {
        identity = await _unlockVault(vault, passwordPrompt);
        debugPrint('[identity] vault unlock '
            'in ${DateTime.now().difference(t0).inMilliseconds}ms');
      } else {
        // No backup exists yet: use the local identity if present, otherwise
        // a migrated legacy key, otherwise generate a fresh one.
        identity = stored ?? await _recoverOrGenerate(null, passwordPrompt);
        if (identity != null) {
          // Create the backup so both platforms (web & app) can discover the
          // identity. Prompts for the account password when unavailable.
          await _ensureVaultBackup(identity, passwordPrompt);
        }
        debugPrint('[identity] no-vault local/generate path '
            'in ${DateTime.now().difference(t0).inMilliseconds}ms');
      }
    }
    if (identity == null) throw Exception('No encryption key');

    _identity = identity;
    await _storage.write(key: key, value: jsonEncode(identity));

    // Refresh the password backup, but NEVER gate chat on it: the PBKDF2
    // re-wrap takes ~9s in pure Dart and a stale backup is harmless. Runs in
    // the background once per session.
    final resolved = identity;
    if (_sessionPassword != null && !_syncScheduled) {
      _syncScheduled = true;
      unawaited(() async {
        try {
          await _syncVault(resolved);
        } on Exception {
          _syncScheduled = false; // retried on next launch
        }
      }());
    }

    // Re-upload the public key on every load so the server never keeps a stale
    // key after the identity was rotated on another device.
    try {
      await api.request(
        '/api/chat/keys/',
        method: 'POST',
        body: {'public_key': identity['pub']},
      );
    } on Exception {
      // Key upload happens again on next load.
    }
    return identity;
  }

  Future<Map<String, dynamic>?> _recoverOrGenerate(
    VaultData? vault,
    VaultPasswordPrompt? passwordPrompt,
  ) async {
    if (vault == null) {
      // Adopt the server-provisioned identity (created for keyless/new
      // accounts so they are chat-ready immediately) before generating a
      // fresh one. Claiming keeps pre-first-open messages decryptable and
      // drops the server's temporary private copy on the next key upload.
      final claimed = await _claimProvisionedIdentity();
      if (claimed != null) return claimed;
      return ChatCrypto.generateIdentity();
    }
    // Fast path: a password captured earlier in this session.
    if (_sessionPassword != null) {
      try {
        return await _unwrap(vault, _sessionPassword!);
      } catch (_) {
        _sessionPassword = null;
      }
    }
    if (passwordPrompt == null) {
      // No UI available (background restore): start fresh and drop the backup.
      try {
        await api.request('/api/chat/vault/', method: 'DELETE');
      } on Exception {
        // Best-effort; a stale backup is harmless if it cannot be removed.
      }
      return ChatCrypto.generateIdentity();
    }
    final answer = await passwordPrompt(
      message:
          'Enter the password for @${_username ?? 'you'} to restore your '
          'encrypted chat keys.',
    );
    switch (answer.result) {
      case VaultPromptResult.unlocked:
        final password = answer.password!;
        final identity = await _unwrap(vault, password);
        _sessionPassword = password;
        return identity;
      case VaultPromptResult.reset:
        try {
          await api.request('/api/chat/vault/', method: 'DELETE');
        } on Exception {
          // Best-effort; see above.
        }
        return ChatCrypto.generateIdentity();
      case VaultPromptResult.cancelled:
        return null;
    }
  }

  /// Fetches the server-provisioned identity for this account
  /// ({public_key, private_jwk}) or null when there is none to claim.
  /// The client becomes the sole holder of the private key once it uploads
  /// the matching public key (see ensureIdentity's re-upload).
  Future<Map<String, dynamic>?> _claimProvisionedIdentity() async {
    try {
      final data = await api.request('/api/chat/keys/self/');
      if (data is Map<String, dynamic>) {
        final pub = data['public_key'] as String?;
        final priv = data['private_jwk'];
        if (pub != null && priv is Map<String, dynamic>) {
          return {'pub': pub, 'priv': priv};
        }
      }
    } on Exception {
      // No provisioned key (or a network hiccup); fall through to fresh.
    }
    return null;
  }

  /// PBKDF2 (150k iterations) + AES-GCM unwrap runs in a background isolate
  /// so it never blocks the UI.
  Future<Map<String, dynamic>> _unwrap(VaultData vault, String password) {
    return compute(ChatCrypto.unwrapIdentityInIsolate, {
      'salt': vault.salt,
      'iv': vault.iv,
      'wrapped': vault.wrappedKey,
      'password': password,
    });
  }

  /// Unlocks the vault identity. This is the ONLY path when a backup exists:
  /// it resolves the identity from the vault using the session's password, or
  /// falls back to a password prompt. It never returns a divergent key.
  Future<Map<String, dynamic>?> _unlockVault(
    VaultData vault,
    VaultPasswordPrompt? passwordPrompt,
  ) async {
    var password = _sessionPassword;
    if (password != null) {
      try {
        return await _unwrap(vault, password);
      } catch (_) {
        _sessionPassword = null;
        password = null;
      }
    }
    if (passwordPrompt == null) {
      // No password and no UI to ask: fall back to claiming provisioned identity
      // or generating a fresh identity so chat can continue.
      _sessionPassword = null;
      final claimed = await _claimProvisionedIdentity();
      if (claimed != null) return claimed;
      return ChatCrypto.generateIdentity();
    }
    final answer = await passwordPrompt(
      message:
          'Enter the password for @${_username ?? 'you'} to unlock your '
          'encrypted chat keys.',
    );
    switch (answer.result) {
      case VaultPromptResult.unlocked:
        final p = answer.password!;
        final identity = _unwrap(vault, p);
        _sessionPassword = p;
        return identity;
      case VaultPromptResult.reset:
        // Explicit user choice to drop the backup and start over. This ALWAYS
        // generates a new identity and immediately backs it up.
        try {
          await api.request('/api/chat/vault/', method: 'DELETE');
        } on Exception {
          // Best-effort; a stale backup is harmless if it cannot be removed.
        }
        final fresh = await _recoverOrGenerate(null, null);
        if (fresh == null) return null;
        await _ensureVaultBackup(fresh, passwordPrompt);
        return fresh;
      case VaultPromptResult.cancelled:
        _sessionPassword = null;
        return null;
    }
  }

  Future<VaultData?> _fetchVault() async {
    try {
      final data = await api.request('/api/chat/vault/');
      return VaultData.fromJson(data as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  /// True when the account's canonical public key changed away from [localPub]
  /// (identity rotated on another device). On a network failure we TRUST the
  /// local key: chat stays instant (the vault would prompt for a password the
  /// user likely cannot provide right now), and the recovery-key derivation
  /// still decrypts history if the identity truly rotated.
  Future<bool> _serverKeyDiffersFrom(String? localPub) async {
    if (localPub == null) return true;
    try {
      final data = await api.request('/api/chat/keys/self/');
      if (data is Map<String, dynamic>) {
        final serverPub = data['public_key'] as String?;
        return serverPub == null || serverPub != localPub;
      }
    } on Exception {
      // Network hiccup: use the stored identity; re-checked on next launch.
    }
    return false;
  }

  /// Creates the password-wrapped backup for an account that has none yet.
  /// Uses the session password when available; otherwise asks the user for
  /// their account password (or skips when no prompt is wired up).
  Future<void> _ensureVaultBackup(
    Map<String, dynamic> identity,
    VaultPasswordPrompt? passwordPrompt,
  ) async {
    var password = _sessionPassword;
    if (password == null) {
      if (passwordPrompt == null) return; // cannot ask; retried on next launch
      final answer = await passwordPrompt(
        message: 'Enter your Reservily password to back up your encrypted '
            'chat keys so you can use Chat on any device.',
      );
      if (answer.result != VaultPromptResult.unlocked) return;
      password = answer.password!;
    }
    _sessionPassword = password;
    await _syncVault(identity);
  }

  /// Creates or refreshes the password-wrapped backup. The salt stays stable
  /// once created so a password always derives the same KEK. Re-wrapping
  /// (PBKDF2, 150k iterations) runs in a background isolate and is skipped
  /// when the identity was already backed up this session.
  Future<void> _syncVault(Map<String, dynamic> identity) async {
    final password = _sessionPassword;
    if (password == null) return;
    if (_lastSyncedPub == identity['pub']) return;
    final existing = await _fetchVault();
    final salt = existing?.salt ??
        ChatCrypto.bytesToB64(ChatCrypto.randomBytes(AppConfig.kekSaltBytes));
    final wrapped = await compute(ChatCrypto.wrapIdentityInIsolate, {
      'salt': salt,
      'password': password,
      'identity': identity,
    });
    await api.request(
      '/api/chat/vault/',
      method: 'POST',
      body: {
        'salt': wrapped['salt'],
        'iv': wrapped['iv'],
        'wrapped_key': wrapped['wrapped'],
      },
    );
    _lastSyncedPub = identity['pub'];
  }

  /// Stores the account password for this session (mirrors sessionStorage).
  void setSessionPassword(String? password) {
    _sessionPassword = password;
  }

  String? get sessionPassword => _sessionPassword;

  /// Restores the private key from a backup using the given password.
  Future<void> restoreFromVault({
    required VaultData vault,
    required String password,
  }) async {
    final identity = await _unwrap(vault, password);
    _identity = identity;
    _sessionPassword = password;
    final key = _identityKey(_username ?? 'default');
    await _storage.write(key: key, value: jsonEncode(identity));
    try {
      await api.request(
        '/api/chat/keys/',
        method: 'POST',
        body: {'public_key': identity['pub']},
      );
    } on Exception {
      // Key upload happens again on next load.
    }
  }

  /// Every identity private key stored on this device, including identities
  /// saved under other usernames (e.g. the old wrong-username bug). Used as a
  /// recovery net so historical messages stay decryptable.
  Future<List<Map<String, dynamic>>> allStoredIdentities() async {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    Map<String, String> all;
    try {
      all = await _storage.readAll();
    } catch (_) {
      return result;
    }
    all.forEach((key, value) {
      if (!key.startsWith(_identityPrefix)) return;
      try {
        final obj = jsonDecode(value) as Map<String, dynamic>;
        if (!obj.containsKey('priv') || !obj.containsKey('pub')) return;
        final pub = obj['pub'] as String;
        if (seen.contains(pub)) return;
        seen.add(pub);
        result.add(obj);
      } catch (_) {
        // Ignore corrupt entries.
      }
    });
    // The active identity first so the primary key wins tie-breaks.
    result.sort((a, b) {
      if (a['pub'] == _identity?['pub']) return -1;
      if (b['pub'] == _identity?['pub']) return 1;
      return 0;
    });
    return result;
  }

  // ------------------------------------------------------------- hidden

  Future<void> _loadHidden() async {
    try {
      final raw = await _storage.read(key: _hiddenKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List<dynamic>? ?? const []);
      _hidden = list.map((e) => int.tryParse('$e')).whereType<int>().toSet();
    } catch (_) {
      _hidden = {};
    }
  }

  Future<void> _saveHidden() async {
    await _storage.write(
        key: _hiddenKey, value: jsonEncode(_hidden.toList()));
  }

  bool isHidden(int messageId) => _hidden.contains(messageId);

  Future<void> hideForMe(int messageId) async {
    _hidden.add(messageId);
    await _saveHidden();
  }

  // ------------------------------------------------------- conversation keys

  /// Derived conversation keys survive app restarts: keyed by conversation id
  /// and bound to BOTH public keys, so a key rotation on either side safely
  /// misses the cache and triggers a fresh (fast-path) derivation. This is
  /// what makes reopening a chat after the first time effectively instant.
  Future<Map<String, dynamic>> _convoKeyMap() async {
    if (_convoLoaded) return _convoKeys;
    _convoLoaded = true;
    try {
      final raw = await _storage.read(key: _convoKeysKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) _convoKeys = decoded;
      }
    } catch (_) {
      // Corrupt cache: treated as empty; re-derived on next open.
    }
    return _convoKeys;
  }

  /// The persisted conversation key when the cached entry still matches the
  /// current identities of both sides, else null.
  Future<String?> cachedConvoKey({
    required int conversationId,
    required String myPub,
    required String otherPub,
  }) async {
    final all = await _convoKeyMap();
    final entry = all['$conversationId'];
    if (entry is! Map<String, dynamic>) return null;
    if (entry['my'] != myPub || entry['pub'] != otherPub) return null;
    final key = entry['key'];
    return key is String ? key : null;
  }

  Future<void> saveConvoKey({
    required int conversationId,
    required String myPub,
    required String otherPub,
    required String keyB64,
  }) async {
    await _convoKeyMap();
    final next = Map<String, dynamic>.from(_convoKeys);
    next['$conversationId'] = {'my': myPub, 'pub': otherPub, 'key': keyB64};
    _convoKeys = next;
    try {
      await _storage.write(key: _convoKeysKey, value: jsonEncode(next));
    } catch (_) {
      // In-memory cache still serves this session.
    }
  }

  // ------------------------------------------------------------- storage

  Future<Map<String, dynamic>?> _readIdentity(String key) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) return null;
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      if (obj.containsKey('priv') && obj.containsKey('pub')) return obj;
    } catch (_) {
      // Corrupt local data: treated as absent.
    }
    return null;
  }
}
