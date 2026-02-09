// lib/data/models/chat_message.dart
// Modelo de mensaje de chat entre conductor y pasajero

import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String messageId;
  final String senderId;
  final String senderRole; // 'conductor' o 'pasajero'
  final String text;
  final bool isQuickMessage;
  final DateTime createdAt;

  ChatMessage({
    required this.messageId,
    required this.senderId,
    required this.senderRole,
    required this.text,
    this.isQuickMessage = false,
    required this.createdAt,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      messageId: doc.id,
      senderId: data['senderId'] ?? '',
      senderRole: data['senderRole'] ?? '',
      text: data['text'] ?? '',
      isQuickMessage: data['isQuickMessage'] ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderRole': senderRole,
      'text': text,
      'isQuickMessage': isQuickMessage,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
