import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        margin: EdgeInsets.only(
          left: isUser ? 48 : 12,
          right: isUser ? 12 : 48,
          top: 6,
          bottom: 6,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 20),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isUser
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.85)
                    : Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: isUser 
                      ? Colors.white.withOpacity(0.15)
                      : Colors.white.withOpacity(0.1),
                  width: 1,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action result badge
                  if (message.actionResult != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: message.actionResult!.success
                            ? const Color(0xFF00FFC6).withOpacity(0.15) // Neon Cyan
                            : const Color(0xFFFF3366).withOpacity(0.15), // Neon Red
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: message.actionResult!.success
                              ? const Color(0xFF00FFC6).withOpacity(0.3)
                              : const Color(0xFFFF3366).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            message.actionResult!.success
                                ? Icons.verified_rounded
                                : Icons.error_outline_rounded,
                            size: 16,
                            color: message.actionResult!.success
                                ? const Color(0xFF00FFC6)
                                : const Color(0xFFFF3366),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            message.actionResult!.actionType.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.0,
                              color: message.actionResult!.success
                                  ? const Color(0xFF00FFC6)
                                  : const Color(0xFFFF3366),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // Message text
                  SelectableText(
                    message.content,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      height: 1.5,
                      letterSpacing: 0.2,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  // Timestamp
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: Colors.white.withOpacity(0.4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '\$hour:\$minute';
  }
}
