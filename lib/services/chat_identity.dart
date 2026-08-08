import 'dart:convert';

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

  Map<String, dynamic>? _identity;
  String? _username;
  String? _sessionPassword;
  Set<int> _hidden = {};

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
    _username = username;
    await _loadHidden();

    final key = _identityKey(username);
    final stored = await _readIdentity(key);
    final vault = await _fetchVault();
    Map<String, dynamic>? identity;

    if (vault != null) {
      // The server vault is the SINGLE canonical cross-platform identity. It is
      // the only source of truth: never fall back to a divergent local key.
      identity = await _unlockVault(vault, passwordPrompt);
    } else {
      // No backup exists yet: use the local identity if present, otherwise a
      // migrated legacy key, otherwise generate a fresh one.
      identity = stored ?? await _recoverOrGenerate(null, passwordPrompt);
      if (identity != null) {
        // ALWAYS create the backup so both platforms (web & app) can discover
        // the identity. Prompts for the account password when unavailable.
        await _ensureVaultBackup(identity, passwordPrompt);
      }
    }
    if (identity == null) throw Exception('No encryption key');

    _identity = identity;
    await _storage.write(key: key, value: jsonEncode(identity));

    if (_sessionPassword != null) {
      await _syncVault(identity);
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
    if (vault == null) return ChatCrypto.generateIdentity();
    // Fast path: a password captured earlier in this session.
    if (_sessionPassword != null) {
      try {
        return _unwrap(vault, _sessionPassword!);
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
        final identity = _unwrap(vault, password);
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

  Map<String, dynamic> _unwrap(VaultData vault, String password) {
    final kek = ChatCrypto.deriveKek(password, vault.salt);
    return ChatCrypto.unwrapIdentity(
        vault.salt, vault.iv, vault.wrappedKey, kek);
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
        return _unwrap(vault, password);
      } catch (_) {
        _sessionPassword = null;
        password = null;
      }
    }
    if (passwordPrompt == null) {
      // No password and no way to ask: cannot unlock safely.
      _sessionPassword = null;
      return null;
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
  /// once created so a password always derives the same KEK.
  Future<void> _syncVault(Map<String, dynamic> identity) async {
    final password = _sessionPassword;
    if (password == null) return;
    final existing = await _fetchVault();
    final salt = existing?.salt ??
        ChatCrypto.bytesToB64(ChatCrypto.randomBytes(AppConfig.kekSaltBytes));
    final kek = ChatCrypto.deriveKek(password, salt);
    final wrapped = ChatCrypto.wrapIdentity(identity, salt, kek);
    await api.request(
      '/api/chat/vault/',
      method: 'POST',
      body: {
        'salt': wrapped['salt'],
        'iv': wrapped['iv'],
        'wrapped_key': wrapped['wrapped'],
      },
    );
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
    final identity = _unwrap(vault, password);
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
