/// A participant in chat as returned by the API.
class ChatUserInfo {
  const ChatUserInfo({
    required this.id,
    required this.username,
    required this.name,
    this.avatar,
    this.hasKey = false,
  });

  final int id;
  final String username;
  final String name;
  final String? avatar;
  final bool hasKey;

  factory ChatUserInfo.fromJson(Map<String, dynamic> json) {
    return ChatUserInfo(
      id: json['id'] as int,
      username: json['username'] as String,
      name: (json['name'] ?? json['username']) as String,
      avatar: json['avatar'] as String?,
      hasKey: json['has_key'] == true,
    );
  }
}

/// A row in the conversation list.
class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.other,
    this.lastMessageAt,
    this.lastIsMe = false,
    this.unread = 0,
  });

  final int id;
  final ChatUserInfo other;
  final DateTime? lastMessageAt;
  final bool lastIsMe;
  final int unread;

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      id: json['id'] as int,
      other: ChatUserInfo.fromJson(json['other'] as Map<String, dynamic>),
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.tryParse(json['last_message_at'] as String)
          : null,
      lastIsMe: json['last_is_me'] == true,
      unread: json['unread'] as int? ?? 0,
    );
  }
}

/// Decrypted payload of a message (or reaction).
class ChatPayload {
  const ChatPayload({
    this.type = 'text',
    this.text,
    this.media,
    this.replyTo,
    this.replyText,
    this.emoji,
  });

  final String type; // 'text' | 'media'
  final String? text;
  final MediaMeta? media;
  final int? replyTo;
  final String? replyText;
  final String? emoji;

  factory ChatPayload.fromJson(Map<String, dynamic> json) {
    return ChatPayload(
      type: json['t'] as String? ?? 'text',
      text: json['text'] as String?,
      media: json['m'] != null
          ? MediaMeta.fromJson(json['m'] as Map<String, dynamic>)
          : null,
      replyTo: json['reply_to'] as int?,
      replyText: json['reply_text'] as String?,
      emoji: json['emoji'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      't': type,
      if (text != null) 'text': text,
      if (media != null) 'm': media!.toJson(),
      if (replyTo != null) 'reply_to': replyTo,
      if (replyText != null) 'reply_text': replyText,
      if (emoji != null) 'emoji': emoji,
    };
  }
}

class MediaMeta {
  const MediaMeta({
    this.key,
    this.mime,
    this.name,
    this.size,
  });

  final String? key;
  final String? mime;
  final String? name;
  final int? size;

  bool get isImage => (mime ?? '').startsWith('image/');

  factory MediaMeta.fromJson(Map<String, dynamic> json) {
    return MediaMeta(
      key: json['key'] as String?,
      mime: json['mime'] as String?,
      name: json['name'] as String?,
      size: json['size'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (key != null) 'key': key,
      if (mime != null) 'mime': mime,
      if (name != null) 'name': name,
      if (size != null) 'size': size,
    };
  }
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.isMe,
    required this.ciphertext,
    required this.nonce,
    this.media,
    this.mediaIv,
    this.mediaMime,
    this.mediaName,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
    this.reactions = const [],
    this.decrypted,
    this.decryptFailed = false,
  });

  final int id;
  final int senderId;
  final bool isMe;
  final String ciphertext;
  final String nonce;
  final String? media;
  final String? mediaIv;
  final String? mediaMime;
  final String? mediaName;
  final DateTime createdAt;
  DateTime? deliveredAt;
  DateTime? readAt;
  List<ReactionInfo> reactions;
  ChatPayload? decrypted;
  bool decryptFailed;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      senderId: json['sender_id'] as int,
      isMe: json['is_me'] == true,
      ciphertext: json['ciphertext'] as String? ?? '',
      nonce: json['nonce'] as String? ?? '',
      media: json['media'] as String?,
      mediaIv: json['media_iv'] as String?,
      mediaMime: json['media_mime'] as String?,
      mediaName: json['media_name'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      deliveredAt: json['delivered_at'] != null
          ? DateTime.tryParse(json['delivered_at'] as String)
          : null,
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'] as String)
          : null,
      reactions: (json['reactions'] as List<dynamic>? ?? [])
          .map((e) => ReactionInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ReactionInfo {
  const ReactionInfo({
    required this.id,
    required this.messageId,
    required this.userId,
    this.username,
    this.name,
    this.ciphertext,
    this.nonce,
  });

  final int id;
  final int messageId;
  final int userId;
  final String? username;
  final String? name;
  final String? ciphertext;
  final String? nonce;

  factory ReactionInfo.fromJson(Map<String, dynamic> json) {
    return ReactionInfo(
      id: json['id'] as int,
      messageId: json['message_id'] as int,
      userId: json['user_id'] as int,
      username: json['username'] as String?,
      name: json['name'] as String?,
      ciphertext: json['ciphertext'] as String?,
      nonce: json['nonce'] as String?,
    );
  }
}

/// An admin broadcast.
class BroadcastInfo {
  const BroadcastInfo({
    required this.id,
    required this.message,
    required this.audience,
    required this.createdAt,
    this.sender,
    this.isNew = false,
  });

  final int id;
  final String message;
  final String audience;
  final DateTime createdAt;
  final ChatUserInfo? sender;
  final bool isNew;

  factory BroadcastInfo.fromJson(Map<String, dynamic> json) {
    return BroadcastInfo(
      id: json['id'] as int,
      message: json['message'] as String,
      audience: json['audience'] as String? ?? 'all',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      sender: json['sender'] != null
          ? ChatUserInfo.fromJson(json['sender'] as Map<String, dynamic>)
          : null,
      isNew: json['is_new'] == true,
    );
  }
}

/// The password-wrapped identity backup stored server-side.
class VaultData {
  const VaultData({required this.salt, required this.iv, required this.wrappedKey});

  final String salt;
  final String iv;
  final String wrappedKey;

  factory VaultData.fromJson(Map<String, dynamic> json) {
    return VaultData(
      salt: json['salt'] as String,
      iv: json['iv'] as String,
      wrappedKey: json['wrapped_key'] as String,
    );
  }
}
