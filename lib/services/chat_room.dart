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
    await _tryFetchKeys();
    _startPolling();
  }

  void _startKeyRetry() {
    _keyTimer?.cancel();
    _keyTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_conversationId == null) return;
      if (!unlocked) _tryFetchKeys();
    });
  }

  Future<void> _tryFetchKeys() async {
    final other = _other;
    final convId = _conversationId;
    if (other == null || convId == null) return;
    if (_pubCount > 0) return; // already unlocked, refreshRoomKeys handles rotation
    try {
      final pubs = await chatService.keysFor(other.username);
      if (_conversationId != convId) return;
      if (pubs.isEmpty) {
        status = RoomStatus.noKey;
        loading = false;
        notifyListeners();
        return;
      }
      _deriveAllKeys(pubs, other.username);
    } on Exception catch (e) {
      if (_conversationId != convId) return;
      status = RoomStatus.noKey;
      loading = false;
      error = e.toString();
      notifyListeners();
    }
  }

  void _deriveAllKeys(List<String> pubs, String otherUsername) {
    if (_deriving) return;
    _deriving = true;
    _pubCount = pubs.length;
    final salts = ChatCrypto.candidateSalts(myUsername, otherUsername);
    final activePriv = identity.identity?['priv'] as Map<String, dynamic>?;
    // Recovery net: try every private key we have on device, active first.
    final candidates = <Map<String, dynamic>>[
      if (activePriv != null) activePriv,
    ];
    final seenPubs = <String>{identity.identity?['pub'] as String? ?? ''};
    for (final ident in _identityBackups) {
      final priv = ident['priv'];
      final pub = ident['pub'] as String? ?? '';
      if (priv is Map<String, dynamic> && seenPubs.add(pub)) {
        candidates.add(priv);
      }
    }
    // ECDH P-256 derivation is slow in pure Dart: run it off the UI isolate.
    compute(ChatCrypto.deriveConversationKeysInIsolate, {
      'candidates': candidates,
      'pubs': pubs,
      'salts': salts,
    }).then((result) {
      _deriving = false;
      if (_conversationId == null) return;
      final keysB64 = (result['keys'] as List).cast<String>();
      final activeIdx = result['activeIndex'] as int;
      _key =
          keysB64.isNotEmpty ? ChatCrypto.b64ToBytes(keysB64[activeIdx]) : null;
      _legacyKeys.clear();
      if (keysB64.isNotEmpty) {
        for (var i = 0; i < keysB64.length; i++) {
          if (i != activeIdx) _legacyKeys.add(ChatCrypto.b64ToBytes(keysB64[i]));
        }
      }
      status = _key != null ? RoomStatus.unlocked : RoomStatus.noKey;
      loading = false;
      notifyListeners();
      if (messages.isEmpty) {
        _loadInitialMessages();
      } else {
        _decryptVisible(retryFailed: true);
      }
    }).catchError((_) {
      _deriving = false;
      _pubCount = 0;
      if (_conversationId == null) return;
      status = RoomStatus.noKey;
      loading = false;
      notifyListeners();
    });
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
    if (convId == null) return;
    try {
      final res = await chatService.messages(convId);
      if (_conversationId != convId) return;
      _applyFetched(res.messages, res.deletedIds, initial: true);
      await chatService.markRead(convId);
    } on Exception catch (e) {
      if (_conversationId != convId) return;
      error = e.toString();
      notifyListeners();
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
