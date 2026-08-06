import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/chat.dart';

/// Chat endpoints (conversations, keys, vault, messages, media, reactions,
/// broadcasts). Crypto never happens here — only ciphertext crosses the wire.
class ChatService {
  ChatService(this.api);

  final ApiClient api;

  Future<List<ConversationSummary>> conversations() async {
    final data = await api.request('/api/chat/conversations/');
    return ((data as Map<String, dynamic>)['conversations'] as List<dynamic>? ?? [])
        .map((e) => ConversationSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ChatUserInfo>> users(String query) async {
    final data = await api.request(
      '/api/chat/users/',
      query: {'q': query},
    );
    return ((data as Map<String, dynamic>)['users'] as List<dynamic>? ?? [])
        .map((e) => ChatUserInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<({int id, ChatUserInfo other})> start(String username) async {
    final data = await api.request(
      '/api/chat/start/',
      method: 'POST',
      body: {'username': username},
    ) as Map<String, dynamic>;
    return (
      id: data['id'] as int,
      other: ChatUserInfo.fromJson(data['other'] as Map<String, dynamic>),
    );
  }

  /// All public keys this user ever uploaded, oldest first.
  Future<List<String>> keysFor(String username) async {
    try {
      final data = await api.request('/api/chat/keys/$username/');
      return ((data as Map<String, dynamic>)['public_keys'] as List<dynamic>? ?? [])
          .cast<String>();
    } on ApiException catch (e) {
      if (e.statusCode == 404) return const [];
      rethrow;
    }
  }

  Future<void> saveKey(String publicKey) async {
    await api.request(
      '/api/chat/keys/',
      method: 'POST',
      body: {'public_key': publicKey},
    );
  }

  Future<VaultData?> vault() async {
    try {
      final data = await api.request('/api/chat/vault/');
      return VaultData.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> saveVault({
    required String salt,
    required String iv,
    required String wrappedKey,
  }) async {
    await api.request(
      '/api/chat/vault/',
      method: 'POST',
      body: {'salt': salt, 'iv': iv, 'wrapped_key': wrappedKey},
    );
  }

  Future<void> deleteVault() async {
    await api.request('/api/chat/vault/', method: 'DELETE');
  }

  Future<({List<ChatMessage> messages, List<int> deletedIds})> messages(
    int conversationId, {
    int? after,
    int? before,
    int? limit,
  }) async {
    final data = await api.request(
      '/api/chat/$conversationId/messages/',
      query: {
        if (after != null) 'after': '$after',
        if (before != null) 'before': '$before',
        if (limit != null) 'limit': '$limit',
      },
    ) as Map<String, dynamic>;
    return (
      messages: (data['messages'] as List<dynamic>? ?? [])
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      deletedIds: (data['deleted_ids'] as List<dynamic>? ?? []).cast<int>(),
    );
  }

  Future<({int id, String createdAt, String? media})> send(
    int conversationId, {
    required String ciphertext,
    required String nonce,
    List<int>? mediaBytes,
    String? mediaFileName,
    String? mediaIv,
    String? mediaMime,
    String? mediaName,
  }) async {
    final data = await api.upload(
      '/api/chat/$conversationId/send/',
      fields: {
        'ciphertext': ciphertext,
        'nonce': nonce,
        if (mediaIv != null) 'media_iv': mediaIv,
        if (mediaMime != null) 'media_mime': mediaMime,
        if (mediaName != null) 'media_name': mediaName,
      },
      file: mediaBytes != null
          ? MultipartFile.fromBytes(mediaBytes, filename: mediaFileName ?? 'encrypted.bin')
          : null,
      fileField: mediaBytes != null ? 'media' : null,
    ) as Map<String, dynamic>;
    return (
      id: data['id'] as int,
      createdAt: data['created_at'] as String? ?? '',
      media: data['media'] as String?,
    );
  }

  Future<void> markRead(int conversationId) async {
    await api.request('/api/chat/$conversationId/read/', method: 'POST');
  }

  Future<void> markDelivered(int conversationId) async {
    await api.request('/api/chat/$conversationId/delivered/', method: 'POST');
  }

  Future<List<ReactionInfo>> reactions(int conversationId, {int? after}) async {
    final data = await api.request(
      '/api/chat/$conversationId/reactions/',
      query: {if (after != null) 'after': '$after'},
    );
    return ((data as Map<String, dynamic>)['reactions'] as List<dynamic>? ?? [])
        .map((e) => ReactionInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> react(int conversationId, int messageId,
      {String? ciphertext, String? nonce, bool remove = false}) async {
    final data = await api.request(
      '/api/chat/$conversationId/react/',
      method: 'POST',
      body: {
        'message_id': messageId,
        if (remove) 'remove': true,
        if (ciphertext != null) 'ciphertext': ciphertext,
        if (nonce != null) 'nonce': nonce,
      },
    ) as Map<String, dynamic>;
    return data['id'] as int? ?? 0;
  }

  Future<void> deleteMessage(int messageId) async {
    await api.request('/api/chat/messages/$messageId/delete/', method: 'POST');
  }

  /// Raw encrypted media bytes (participant-only endpoint).
  Future<List<int>> downloadMedia(String url) => api.download(url);

  Future<int> unread() async {
    final data = await api.request('/api/chat/unread/');
    return (data as Map<String, dynamic>)['unread'] as int? ?? 0;
  }

  Future<List<BroadcastInfo>> broadcasts() async {
    final data = await api.request('/api/chat/broadcasts/');
    return ((data as Map<String, dynamic>)['broadcasts'] as List<dynamic>? ?? [])
        .map((e) => BroadcastInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BroadcastInfo>> broadcastHistory() async {
    final data = await api.request('/api/chat/broadcasts/history/');
    return ((data as Map<String, dynamic>)['broadcasts'] as List<dynamic>? ?? [])
        .map((e) => BroadcastInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> broadcastRead(int id) async {
    await api.request('/api/chat/broadcasts/$id/read/', method: 'POST');
  }

  Future<void> broadcastDismiss(int id) async {
    await api.request('/api/chat/broadcasts/$id/dismiss/', method: 'POST');
  }
}
