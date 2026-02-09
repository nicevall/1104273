// lib/data/services/chat_service.dart
// Servicio de chat en tiempo real entre conductor y pasajero
// Estructura Firestore: chats/{tripId}__{passengerId}/messages/{msgId}
// Chat activo solo desde status 'accepted' hasta 'picked_up'

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_message.dart';

class ChatService {
  final _firestore = FirebaseFirestore.instance;

  /// Genera el chatId único para un viaje + pasajero
  String _chatId(String tripId, String passengerId) =>
      '${tripId}__$passengerId';

  /// Inicializa el chat (crea documento metadata)
  Future<void> initializeChat({
    required String tripId,
    required String passengerId,
    required String driverId,
  }) async {
    final chatId = _chatId(tripId, passengerId);
    final chatRef = _firestore.collection('chats').doc(chatId);

    final doc = await chatRef.get();
    if (!doc.exists) {
      await chatRef.set({
        'tripId': tripId,
        'passengerId': passengerId,
        'driverId': driverId,
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  /// Envía un mensaje al chat
  Future<void> sendMessage({
    required String tripId,
    required String passengerId,
    required String senderId,
    required String senderRole,
    required String text,
    bool isQuickMessage = false,
  }) async {
    final chatId = _chatId(tripId, passengerId);

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'senderId': senderId,
      'senderRole': senderRole,
      'text': text,
      'isQuickMessage': isQuickMessage,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Actualizar lastMessage en metadata
    await _firestore.collection('chats').doc(chatId).update({
      'lastMessage': text,
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastSenderRole': senderRole,
    });
  }

  /// Stream de mensajes en tiempo real
  Stream<List<ChatMessage>> getMessagesStream(
    String tripId,
    String passengerId,
  ) {
    final chatId = _chatId(tripId, passengerId);

    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => ChatMessage.fromFirestore(doc)).toList());
  }

  /// Verifica si el chat está activo
  Future<bool> isChatActive(String tripId, String passengerId) async {
    final chatId = _chatId(tripId, passengerId);
    try {
      final doc = await _firestore.collection('chats').doc(chatId).get();
      return doc.exists && (doc.data()?['isActive'] ?? false);
    } catch (e) {
      debugPrint('Error checking chat status: $e');
      return false;
    }
  }

  /// Desactiva el chat (cuando el pasajero es recogido)
  Future<void> deactivateChat(String tripId, String passengerId) async {
    final chatId = _chatId(tripId, passengerId);
    try {
      await _firestore.collection('chats').doc(chatId).update({
        'isActive': false,
        'deactivatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error deactivating chat: $e');
    }
  }
}
