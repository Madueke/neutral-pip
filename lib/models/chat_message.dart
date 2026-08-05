class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final AgentActionResult? actionResult;

  /// Attached images/files (populated in Trading Mode only).
  final List<ChatAttachment> attachments;

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.actionResult,
    this.attachments = const [],
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'actionResult': actionResult?.toJson(),
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        actionResult: json['actionResult'] != null
            ? AgentActionResult.fromJson(json['actionResult'] as Map<String, dynamic>)
            : null,
        attachments: json['attachments'] != null
            ? (json['attachments'] as List)
                .map((a) => ChatAttachment.fromJson(a as Map<String, dynamic>))
                .toList()
            : const [],
      );
}

/// A single attached file/image on a message (Trading Mode only).
class ChatAttachment {
  final String name; // file name or label
  final String path; // local file path
  final String type; // 'image' or 'file'
  final String? mimeType;
  final int? sizeBytes;

  ChatAttachment({
    required this.name,
    required this.path,
    required this.type,
    this.mimeType,
    this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
      };

  factory ChatAttachment.fromJson(Map<String, dynamic> json) => ChatAttachment(
        name: json['name'] as String,
        path: json['path'] as String,
        type: json['type'] as String,
        mimeType: json['mimeType'] as String?,
        sizeBytes: json['sizeBytes'] as int?,
      );
}

class AgentActionResult {
  final String actionType;
  final bool success;
  final String? details;

  AgentActionResult({
    required this.actionType,
    required this.success,
    this.details,
  });

  Map<String, dynamic> toJson() => {
        'actionType': actionType,
        'success': success,
        'details': details,
      };

  factory AgentActionResult.fromJson(Map<String, dynamic> json) => AgentActionResult(
        actionType: json['actionType'] as String,
        success: json['success'] as bool,
        details: json['details'] as String?,
      );
}
