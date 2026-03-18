import 'package:flutter/material.dart';

enum MessageRole { user, assistant, system }
enum MessageStatus { sending, streaming, done, error }

class ChatMessage {
  final String id;
  final MessageRole role;
  String content;
  MessageStatus status;
  final DateTime timestamp;
  final bool isAgent;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.status = MessageStatus.done,
    DateTime? timestamp,
    this.isAgent = false,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
  bool get isStreaming => status == MessageStatus.streaming;
  bool get isError => status == MessageStatus.error;
}

class ChatSession {
  final String id;
  String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
  })  : messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = DateTime.now();
}
