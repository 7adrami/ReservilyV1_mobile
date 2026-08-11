import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat.dart';
import 'chat_crypto.dart';
import 'chat_identity.dart';
import 'chat_service.dart';

/// Room lock states mirroring the web app's status line.
enum RoomStatus {
  waiting, // still trying to fetch the other user's key
  unlocked, // end-to-end encrypted
  noKey, // other user has no key yet
}

/// Replicates the room logic of static/js/chat.js: key derivation over every
/// public key the other user ever uploaded, legacy fallback salts, message
/// polling (after=lastId + deleted_ids), reaction reconciliation, and sending.
class ChatRoomController extends ChangeNotifier {
  ChatRoomController({
    required this.chatService,
    required this.identity,
    required this.myUsername,
    required this.myUserId,
    required this.myName,
  });

  final ChatService chatService;
  final ChatIdentity identity;
  final String myUsername;
  final int myUserId;
  final String myName;

  int? _conversationId;
  ChatUserInfo? _other;
  Uint8List? _key;
  final List<Uint8List> _legacyKeys = [];
  int _pubCount = 0;
  List<Map<String, dynamic>> _identityBackups = [];
  bool _deriving = false;

  final List<ChatMessage> messages = [];
  final Map<int, ({Uint8List bytes, String mime, String name})> _mediaCache = {};

  RoomStatus status = RoomStatus.waiting;
  int lastId = 0;
  int firstId = 0;
  bool loading = false;
  String? error;
  ChatMessage? replyTo;

  Timer? _pollTimer;
  Timer? _keyTimer;
  bool _polling = false;
  bool _fetchingInitial = false;

  static final Map<String, Uint8List> _keyCache = {};
  static final Map<String, Map<String, dynamic>> _legacyCache = {};
  static const int _keyCacheMax = 300;

  static String _keyCacheKey(String myPub, String otherPub, List<String> salts) =>
      '${myPub.compareTo(otherPub) < 0 ? '$myPub|$otherPub' : '$otherPub|$myPub'}|'
      '${salts.join(',')}';

  static void _cacheKeyPut(
      String myPub, String otherPub, List<String> salts, Uint8List key) {
    if (_keyCache.length >= _keyCacheMax) _keyCache.clear();
    _keyCache[_keyCacheKey(myPub, otherPub, salts)] = key;
  }

  int? get conversationId => _conversationId;
  ChatUserInfo? get other => _other;
  bool get unlocked => status == RoomStatus.unlocked && _key != null;
  int get undecryptable =>
      messages.where((m) => m.decryptFailed).length;

  List<Uint8List> get _conversationKeys {
    final keys = <Uint8List>[];
    if (_key != null) keys.add(_key!);
    for (final k in _legacyKeys) {
      if (!keys.any((x) => _bytesEqual(x, k))) keys.add(k);
    }
    return keys;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ------------------------------------------------------------ lifecycle

  Future<void> open(int conversationId, ChatUserInfo other) async {
    _conversationId = conversationId;
    _other = other;
    _key = null;
    _legacyKeys.clear();
    _pubCount = 0;
    _identityBackups = await identity.allStoredIdentities();
    messages.clear();
    _mediaCache.clear();
    lastId = 0;
    firstId = 0;
    replyTo = null;
    error = null;
    status = RoomStatus.waiting;
    loading = true;
    notifyListeners();

    _startKeyRetry();
    // Fetch the message history NOW, in parallel with key resolution, so the
    // history is already on screen (as encrypted placeholders) by the time the
    // conversation key lands -- decrypting in place instead of waiting for a
    // second round-trip after derivation.
    unawaited(_loadInitialMessages());
    await _tryFetchKeys();
    _startPolling();
  }

  /// Called once the chat identity is available (local key matched against the
  /// server or vault unlocked). Kicks the derivation immediately instead of
  /// waiting for the next 1s retry tick.
  Future<void> identityReady() async {
    if (_conversationId == null || unlocked) return;
    await _tryFetchKeys();
  }

  void _startKeyRetry() {
    _keyTimer?.cancel();
    // Retry quickly for the first 3 attempts (covers the common case of a
    // brand-new account whose provisioned key was just created server-side)
    // then settle to a 3-second cadence.
    int fastTicks = 0;
    _keyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_conversationId == null) return;
      if (unlocked) {
        _keyTimer?.cancel();
        return;
      }
      fastTicks++;
      if (fastTicks <= 3 || fastTicks % 3 == 0) {
        _tryFetchKeys();
      }
    });
  }

  Future<void> _tryFetchKeys() async {
    final other = _other;
    final convId = _conversationId;
    if (other == null || convId == null) return;
    if (_pubCount > 0) return; // already unlocked, refreshRoomKeys handles rotation
    if (_deriving) return;    // derivation already in flight
    try {
      final pubs = await chatService.keysFor(other.username);
      if (_conversationId != convId) return;
      if (pubs.isEmpty) {
        status = RoomStatus.noKey;
        loading = false;
        notifyListeners();
        return;
      }
      // Clear any prior transient error now that we have keys.
      error = null;
      _deriveAllKeys(pubs, other.username);
    } on Exception catch (e) {
      if (_conversationId != convId) return;
      // Keep status as waiting so the timer retries; only show noKey after
      // the server confirms there truly is no key (empty pubs list).
      loading = false;
      error = e.toString();
      notifyListeners();
    }
  }

  void _deriveAllKeys(List<String> pubs, String otherUsername) {
    if (_deriving) return;
    _deriving = true;
    final seenKeyPubs = <String>{};
    pubs = [
      for (final p in pubs)
        if (seenKeyPubs.add(p)) p,
    ];
    _pubCount = pubs.length;
    final salts = ChatCrypto.candidateSalts(myUsername, otherUsername);
    final activePriv = identity.identity?['priv'] as Map<String, dynamic>?;
    // Identity still loading (vault unlock prompt / claim in flight): do NOT
    // run the slow full-candidate derivation yet. Reset so the key-retry
    // timer re-fetches and re-derives the instant the identity is ready.
    if (activePriv == null) {
      _deriving = false;
      _pubCount = 0;
      return;
    }
    // Recovery net: try every private key we have on device, active first.
    final candidates = <Map<String, dynamic>>[activePriv];
    final seenPubs = <String>{identity.identity?['pub'] as String? ?? ''};
    for (final ident in _identityBackups) {
      final priv = ident['priv'];
      final pub = ident['pub'] as String? ?? '';
      if (priv is Map<String, dynamic> && seenPubs.add(pub)) {
        candidates.add(priv);
      }
    }
    final myPub = identity.identity?['pub'] as String? ?? '';
    final convId = _conversationId;
    final latestPub = pubs.isNotEmpty ? pubs.last : null;
    if (latestPub == null) {
      // No keys to derive against yet; legacy path covers the empty case.
      _deriveLegacyKeys(candidates, pubs, salts);
      return;
    }
    // Fast path: reuse the key that was derived and persisted earlier for this
    // exact (identity, other key) pair -- restarts stay instant, no ECDH.
    unawaited(() async {
      final cached = convId != null
          ? await identity.cachedConvoKey(
              conversationId: convId, myPub: myPub, otherPub: latestPub)
          : null;
      if (cached != null) {
        final bytes = ChatCrypto.b64ToBytes(cached);
        _key = bytes;
        _cacheKeyPut(myPub, latestPub, salts, bytes);
        status = RoomStatus.unlocked;
        loading = false;
        _deriving = false;
        notifyListeners();
        if (messages.isEmpty) {
          _loadInitialMessages();
        } else {
          _decryptVisible(retryFailed: true);
        }
        // Legacy keys (rotated identities) come from the result cache too,
        // so repeat opens never re-run the heavy batch derivation.
        _deriveLegacyKeys(candidates, pubs, salts);
        return;
      }
      _deriveFastKey(candidates, pubs, salts, myPub, latestPub, convId);
    }());
  }

  void _deriveFastKey(
      List<Map<String, dynamic>> candidates,
      List<String> pubs,
      List<String> salts,
      String myPub,
      String latestPub,
      int? convId) {
    final activePriv =
        candidates.isNotEmpty ? candidates.first : null;
    if (activePriv == null) return;
    // Fast path: derive the key for the ACTIVE identity and the other user's
    // latest public key (one ECDH, ~1 second) so the room unlocks right away.
    // The full candidate x pub x salt derivation then runs in the background
    // to also recover keys for old identities and rotated keys.
    compute(ChatCrypto.deriveConversationKeyInIsolate, {
      'priv': activePriv,
      'pub': latestPub,
      'salts': salts,
    }).then((result) {
        if (_conversationId == null) return;
        final keyB64 = result['key'] as String?;
        if (keyB64 != null) {
          final derived = ChatCrypto.b64ToBytes(keyB64);
          _cacheKeyPut(myPub, latestPub, salts, derived);
          if (convId != null) {
            identity.saveConvoKey(
              conversationId: convId,
              myPub: myPub,
              otherPub: latestPub,
              keyB64: keyB64,
            );
          }
          _key = derived;
          status = RoomStatus.unlocked;
          loading = false;
          notifyListeners();
          if (messages.isEmpty) {
            _loadInitialMessages();
          } else {
            _decryptVisible(retryFailed: true);
          }
        }
        _deriveLegacyKeys(candidates, pubs, salts);
      }).catchError((_) {
        if (_conversationId == null) return;
        _deriveLegacyKeys(candidates, pubs, salts);
      });
  }

  void _deriveLegacyKeys(
      List<Map<String, dynamic>> candidates,
      List<String> pubs,
      List<String> salts) {
    // ECDH P-256 derivation is slow in pure Dart: run it off the UI isolate,
    // and remember the result so repeat opens are instant.
    final sig = [
      for (final c in candidates) c['pub'] as String? ?? '',
      '|${pubs.join('|')}|${salts.join(',')}',
    ].join('|');
    final hit = _legacyCache[sig];
    if (hit != null) {
      _applyLegacyResult(hit['keys'], hit['activeIndex']);
      return;
    }
    compute(ChatCrypto.deriveConversationKeysInIsolate, {
      'candidates': candidates,
      'pubs': pubs,
      'salts': salts,
    }).then((result) {
      final keysB64 = (result['keys'] as List).cast<String>();
      final activeIdx = result['activeIndex'] as int;
      if (_legacyCache.length >= 100) _legacyCache.clear();
      _legacyCache[sig] = {'keys': keysB64, 'activeIndex': activeIdx};
      _applyLegacyResult(keysB64, activeIdx);
    }).catchError((_) {
      _deriving = false;
      _pubCount = 0;  // ensure retry timer can re-enter _tryFetchKeys
      if (_conversationId == null) return;
      status = RoomStatus.waiting;  // keep retrying instead of giving up
      loading = false;
      notifyListeners();
    });
  }

  void _applyLegacyResult(List<String> keysB64, int activeIdx) {
    _deriving = false;
    if (_conversationId == null) return;
    _legacyKeys.clear();
    for (var i = 0; i < keysB64.length; i++) {
      if (i != activeIdx) _legacyKeys.add(ChatCrypto.b64ToBytes(keysB64[i]));
    }
    if (_key == null && keysB64.isNotEmpty) {
      _key = ChatCrypto.b64ToBytes(keysB64[activeIdx]);
    }
    status = _key != null ? RoomStatus.unlocked : RoomStatus.noKey;
    loading = false;
    notifyListeners();
    _decryptVisible(retryFailed: true);
  }

  /// Called periodically: if the other user rotated their key, re-derive so
  /// new messages encrypt under their LATEST public key.
  Future<void> refreshRoomKeys() async {
    final other = _other;
    final convId = _conversationId;
    if (other == null || convId == null || _pubCount == 0) return;
    try {
      final pubs = await chatService.keysFor(other.username);
      if (_conversationId != convId || pubs.isEmpty) return;
      if (pubs.length <= _pubCount) return;
      _deriveAllKeys(pubs, other.username);
    } on Exception {
      // Retried next tick.
    }
  }

  Future<void> _loadInitialMessages() async {
    final convId = _conversationId;
    if (convId == null || _fetchingInitial) return;
    _fetchingInitial = true;
    try {
      final res = await chatService.messages(convId);
      if (_conversationId != convId) return;
      _applyFetched(res.messages, res.deletedIds, initial: true);
      await chatService.markRead(convId);
    } on Exception catch (e) {
      if (_conversationId != convId) return;
      error = e.toString();
      notifyListeners();
    } finally {
      _fetchingInitial = false;
      // The key may have landed while history was being fetched: decrypt what
      // is now on screen without waiting for the next poll tick.
      if (_conversationId == convId) _decryptVisible(retryFailed: true);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    var pollCount = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      pollCount++;
      if (_conversationId == null) return;
      if (_polling) return;
      _polling = true;
      try {
        await _pollMessages();
        await _pollReactions();
        if (pollCount % 5 == 0) await refreshRoomKeys();
      } finally {
        _polling = false;
      }
    });
  }

  Future<void> _pollMessages() async {
    final convId = _conversationId;
    if (convId == null || !unlocked) return;
    try {
      final res = await chatService.messages(convId, after: lastId);
      if (_conversationId != convId) return;
      final removed = res.deletedIds.isNotEmpty;
      final hadIds = messages.map((m) => m.id).toSet();
      final fresh = res.messages.where((m) => !identity.isHidden(m.id)).toList();
      final added = fresh.where((m) => !hadIds.contains(m.id)).toList();
      if (added.isNotEmpty) {
        _applyAdded(added);
        await chatService.markRead(convId);
      } else if (removed) {
        messages.removeWhere((m) => res.deletedIds.contains(m.id));
        _updateBounds();
        _decryptVisible();
        notifyListeners();
      } else {
        _updateReadMarks(res.messages);
      }
    } on Exception {
      // Transient; retried next tick.
    }
  }

  void _updateReadMarks(List<ChatMessage> fresh) {
    final byId = {for (final f in fresh) f.id: f};
    var changed = false;
    for (final m in messages) {
      final live = byId[m.id];
      if (live != null &&
          (live.deliveredAt != m.deliveredAt || live.readAt != m.readAt)) {
        m
          ..deliveredAt = live.deliveredAt
          ..readAt = live.readAt;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  Future<void> _pollReactions() async {
    final convId = _conversationId;
    if (convId == null) return;
    try {
      final fresh = await chatService.reactions(convId);
      if (_conversationId != convId) return;
      final byMsg = <int, List<ReactionInfo>>{};
      for (final r in fresh) {
        (byMsg[r.messageId] ??= []).add(r);
      }
      var changed = false;
      for (final m in messages) {
        final list = byMsg[m.id] ?? <ReactionInfo>[];
        if (_reactionSignature(m.reactions) != _reactionSignature(list)) {
          m.reactions = list;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } on Exception {
      // Transient.
    }
  }

  static String _reactionSignature(List<ReactionInfo> reactions) => reactions
      .map((r) =>
          '${r.id}:${r.userId}:${r.ciphertext}:${r.nonce}')
      .join('|');

  void _applyFetched(List<ChatMessage> fresh, List<int> deletedIds,
      {required bool initial}) {
    messages.clear();
    messages.addAll(fresh.where(
        (m) => !identity.isHidden(m.id) && !deletedIds.contains(m.id)));
    _updateBounds();
    _decryptVisible();
    loading = false;
    notifyListeners();
  }

  void _applyAdded(List<ChatMessage> added) {
    messages.addAll(added);
    _updateBounds();
    for (final m in added) {
      _decryptOne(m);
    }
    notifyListeners();
  }

  void _updateBounds() {
    if (messages.isNotEmpty) {
      firstId = messages.first.id;
      lastId = messages.last.id;
    }
  }

  // ------------------------------------------------------------ decrypt

  Future<void> _decryptVisible({bool retryFailed = false}) async {
    final pending = <ChatMessage>[];
    for (final m in messages) {
      if (retryFailed) m.decryptFailed = false;
      if (m.decrypted == null && !m.decryptFailed) pending.add(m);
    }
    if (pending.isNotEmpty && unlocked) {
      if (pending.length >= 12) {
        // Batch AES-GCM decrypt on a background isolate so long histories
        // never stall the UI thread.
        try {
          final keysB64 =
              _conversationKeys.map(ChatCrypto.bytesToB64).toList();
          final items = [
            for (final m in pending)
              {'ciphertext': m.ciphertext, 'nonce': m.nonce},
          ];
          final results = await compute(ChatCrypto.decryptPayloadsInIsolate, {
            'keys': keysB64,
            'items': items,
          });
          for (var i = 0; i < pending.length; i++) {
            final payload = results[i];
            if (payload != null) {
              pending[i].decrypted = ChatPayload.fromJson(payload);
            } else {
              pending[i].decryptFailed = true;
            }
          }
        } on Exception {
          for (final m in pending) {
            await _decryptOne(m);
          }
        }
      } else {
        for (final m in pending) {
          await _decryptOne(m);
        }
      }
    }
    notifyListeners();
  }

  Future<void> _decryptOne(ChatMessage m) async {
    if (m.decrypted != null || m.decryptFailed) return;
    if (!unlocked) return;
    try {
      final payload = await _decryptWithAny(m.ciphertext, m.nonce);
      m.decrypted = ChatPayload.fromJson(payload);
    } catch (_) {
      m.decryptFailed = true;
    }
  }

  Future<Map<String, dynamic>> _decryptWithAny(
      String ciphertext, String nonce) async {
    Object? lastError;
    for (final key in _conversationKeys) {
      try {
        return ChatCrypto.decryptPayload(key, ciphertext, nonce);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('no key');
  }

  /// Decrypts a reaction emoji; returns null when not possible.
  Future<String?> decryptEmoji(ReactionInfo r) async {
    if (r.ciphertext == null || r.nonce == null) return null;
    try {
      final payload = await _decryptWithAny(r.ciphertext!, r.nonce!);
      return payload['emoji'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Media for a message, decrypted on first request and cached.
  Future<({Uint8List bytes, String mime, String name})> mediaFor(
      ChatMessage m) async {
    final cached = _mediaCache[m.id];
    if (cached != null) return cached;
    if (m.media == null || m.mediaIv == null || m.decrypted?.media == null) {
      throw Exception('No media on this message');
    }
    final key = m.decrypted!.media!.key;
    if (key == null) throw Exception('Missing media key');
    final ct = await chatService.downloadMedia(m.media!);
    final plain = ChatCrypto.decryptFileBytes(key, m.mediaIv!, ct);
    final result = (
      bytes: plain,
      mime: m.mediaMime ?? m.decrypted!.media!.mime ?? 'application/octet-stream',
      name: m.mediaName ?? m.decrypted!.media!.name ?? 'file',
    );
    _mediaCache[m.id] = result;
    return result;
  }

  // ------------------------------------------------------------- sending

  Future<void> sendText(String text) async {
    final convId = _conversationId;
    if (convId == null || !unlocked) return;
    final payload = <String, dynamic>{
      't': 'text',
      'text': text,
      if (replyTo != null) ..._replyPayload(),
    };
    final enc = ChatCrypto.encryptPayload(_key!, payload);
    final data = await chatService.send(
      convId,
      ciphertext: enc.$1,
      nonce: enc.$2,
    );
    _appendLocal(ChatMessage(
      id: data.id,
      senderId: myUserId,
      isMe: true,
      ciphertext: enc.$1,
      nonce: enc.$2,
      createdAt: DateTime.tryParse(data.createdAt) ?? DateTime.now(),
      decrypted: ChatPayload.fromJson(payload),
    ));
    replyTo = null;
  }

  Future<void> sendMedia({
    required List<int> bytes,
    required String name,
    required String mime,
    String? caption,
  }) async {
    final convId = _conversationId;
    if (convId == null || !unlocked) return;
    final enc = ChatCrypto.encryptFileBytes(bytes);
    final payload = <String, dynamic>{
      't': 'media',
      'text': caption ?? '',
      'm': {'key': enc.key, 'mime': mime, 'name': name, 'size': bytes.length},
      if (replyTo != null) ..._replyPayload(),
    };
    final encMsg = ChatCrypto.encryptPayload(_key!, payload);
    final data = await chatService.send(
      convId,
      ciphertext: encMsg.$1,
      nonce: encMsg.$2,
      mediaBytes: enc.ciphertext,
      mediaFileName: 'encrypted.bin',
      mediaIv: enc.iv,
      mediaMime: mime,
      mediaName: name,
    );
    _appendLocal(ChatMessage(
      id: data.id,
      senderId: myUserId,
      isMe: true,
      ciphertext: encMsg.$1,
      nonce: encMsg.$2,
      media: data.media,
      mediaIv: enc.iv,
      mediaMime: mime,
      mediaName: name,
      createdAt: DateTime.tryParse(data.createdAt) ?? DateTime.now(),
      decrypted: ChatPayload.fromJson(payload),
    ));
    replyTo = null;
  }

  Map<String, dynamic> _replyPayload() {
    final m = replyTo;
    if (m == null) return const {};
    final p = m.decrypted;
    final preview = p?.type == 'media' ? (p?.text ?? '📷 Photo') : (p?.text ?? '');
    return {
      'reply_to': m.id,
      'reply_text': preview.isEmpty ? (p?.type == 'media' ? '📷 Photo' : '') : preview,
    };
  }

  void _appendLocal(ChatMessage m) {
    messages.add(m);
    _updateBounds();
    notifyListeners();
  }

  // ---------------------------------------------------------- reactions

  Future<void> setReaction(ChatMessage m, String emoji) async {
    final convId = _conversationId;
    if (convId == null || !unlocked) return;
    final enc = ChatCrypto.encryptPayload(_key!, {'emoji': emoji});
    final id = await chatService.react(
      convId,
      m.id,
      ciphertext: enc.$1,
      nonce: enc.$2,
    );
    m.reactions = m.reactions
        .where((r) => r.userId != myUserId)
        .toList();
    m.reactions.add(ReactionInfo(
      id: id,
      messageId: m.id,
      userId: myUserId,
      username: myUsername,
      name: myName,
      ciphertext: enc.$1,
      nonce: enc.$2,
    ));
    notifyListeners();
  }

  Future<void> removeReaction(ChatMessage m) async {
    final convId = _conversationId;
    if (convId == null) return;
    await chatService.react(convId, m.id, remove: true);
    m.reactions = m.reactions.where((r) => r.userId != myUserId).toList();
    notifyListeners();
  }

  Future<void> deleteForEveryone(ChatMessage m) async {
    await chatService.deleteMessage(m.id);
    messages.removeWhere((x) => x.id == m.id);
    _updateBounds();
    notifyListeners();
  }

  Future<void> hideForMe(ChatMessage m) async {
    await identity.hideForMe(m.id);
    messages.removeWhere((x) => x.id == m.id);
    _updateBounds();
    notifyListeners();
  }

  void startReply(ChatMessage m) {
    replyTo = m;
    notifyListeners();
  }

  void clearReply() {
    replyTo = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _keyTimer?.cancel();
    super.dispose();
  }
}
