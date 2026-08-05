import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../config/theme.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 8,
          right: isUser ? 8 : 48,
          top: 4,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isUser
              ? AppColors.amber.withOpacity(0.12)
              : scheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isUser ? 12 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 12),
          ),
          border: Border.all(
            color: isUser
                ? AppColors.amber.withOpacity(0.4)
                : scheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Container(
                width: 3,
                height: 26,
                margin: const EdgeInsets.only(top: 2, right: 10),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action result badge
                  if (message.actionResult != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: (message.actionResult!.success
                                ? AppColors.bull
                                : AppColors.bear)
                            .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (message.actionResult!.success
                                  ? AppColors.bull
                                  : AppColors.bear)
                              .withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            message.actionResult!.success
                                ? Icons.check_circle_rounded
                                : Icons.error_rounded,
                            size: 14,
                            color: message.actionResult!.success
                                ? AppColors.bull
                                : AppColors.bear,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            message.actionResult!.actionType.toUpperCase().replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 10,
                              color: message.actionResult!.success
                                  ? AppColors.bull
                                  : AppColors.bear,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
            // Trading Mode attachments (only present on trading messages;
            // Phone Control messages always carry an empty list, so this
            // never renders outside Trading Mode).
            if (message.attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...message.attachments.map(_buildAttachment),
              const SizedBox(height: 8),
            ],
            // Message text
            if (isUser)
              SelectableText(
                message.content,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 15,
                  height: 1.4,
                ),
              )
            else
              MarkdownBody(
                data: message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    height: 1.45,
                  ),
                  listBullet: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                  ),
                ),
              ),
            // Timestamp
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
        ],
      ),
    ),
  );

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Build the inline widget for one attachment: a rounded, tappable image
  /// thumbnail for images, or a file chip (icon + name + size) for files.
  ///
  /// TRADING MODE: never add tap-based execution here.
  /// Opening the image viewer only navigates within the app; it never
  /// performs on-screen automation or device actions.
  Widget _buildAttachment(ChatAttachment attachment) {
    if (attachment.type == 'image') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Hero(
            tag: _attachmentHeroTag(attachment),
            child: GestureDetector(
              onTap: () => _openImageViewer(context, attachment),
              child: Image.file(
                File(attachment.path),
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _brokenImageBox(),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 14,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                attachment.sizeBytes != null
                    ? '${attachment.name} · ${_formatSize(attachment.sizeBytes!)}'
                    : attachment.name,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Simple full-screen image viewer with pinch-zoom and a Hero transition.
  void _openImageViewer(BuildContext context, ChatAttachment attachment) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Center(
                    child: Hero(
                      tag: _attachmentHeroTag(attachment),
                      child: InteractiveViewer(
                        maxScale: 5,
                        child: Image.file(
                          File(attachment.path),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              _brokenImageBox(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// TRADING MODE: never add tap-based execution here.
  Widget _brokenImageBox() {
    return Container(
      width: double.infinity,
      height: 200,
      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
      ),
    );
  }

  /// TRADING MODE: never add tap-based execution here.
  String _attachmentHeroTag(ChatAttachment attachment) =>
      'trading_attachment_${message.timestamp.microsecondsSinceEpoch}_'
      '${attachment.path}';

  /// TRADING MODE: never add tap-based execution here.
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
