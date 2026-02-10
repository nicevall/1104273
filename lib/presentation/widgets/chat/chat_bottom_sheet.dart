// lib/presentation/widgets/chat/chat_bottom_sheet.dart
// Bottom sheet de chat reutilizable para conductor y pasajero
// Mensajes rápidos predefinidos + texto libre
// Se desactiva cuando el pasajero es recogido (picked_up)

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/services/chat_service.dart';

class ChatBottomSheet extends StatefulWidget {
  final String tripId;
  final String passengerId;
  final String currentUserId;
  final String currentUserRole; // 'conductor' o 'pasajero'
  final bool isActive;
  final String otherUserName;

  const ChatBottomSheet({
    super.key,
    required this.tripId,
    required this.passengerId,
    required this.currentUserId,
    required this.currentUserRole,
    required this.isActive,
    required this.otherUserName,
  });

  /// Mostrar el chat como bottom sheet
  static Future<void> show(
    BuildContext context, {
    required String tripId,
    required String passengerId,
    required String currentUserId,
    required String currentUserRole,
    required bool isActive,
    required String otherUserName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatBottomSheet(
        tripId: tripId,
        passengerId: passengerId,
        currentUserId: currentUserId,
        currentUserRole: currentUserRole,
        isActive: isActive,
        otherUserName: otherUserName,
      ),
    );
  }

  @override
  State<ChatBottomSheet> createState() => _ChatBottomSheetState();
}

class _ChatBottomSheetState extends State<ChatBottomSheet> {
  final _chatService = ChatService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  // Mensajes rápidos por rol
  static const Map<String, List<String>> _quickMessages = {
    'pasajero': [
      'Ya estoy afuera 👋',
      'Estoy saliendo, 2 min',
      'Soy el de mochila',
      '¿Ya estás cerca?',
      '¿Puedes esperarme?',
    ],
    'conductor': [
      'Estoy afuera 🚗',
      'Llego en 2 min',
      'Estoy en la esquina',
      'No te veo, ¿dónde estás?',
      'Soy el carro blanco',
    ],
  };

  @override
  void initState() {
    super.initState();
    // Inicializar chat si no existe
    _chatService.initializeChat(
      tripId: widget.tripId,
      passengerId: widget.passengerId,
      driverId: widget.currentUserRole == 'conductor'
          ? widget.currentUserId
          : '', // Se completará en el servicio
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text, {bool isQuick = false}) async {
    if (text.trim().isEmpty || _isSending || !widget.isActive) return;

    setState(() => _isSending = true);

    try {
      await _chatService.sendMessage(
        tripId: widget.tripId,
        passengerId: widget.passengerId,
        senderId: widget.currentUserId,
        senderRole: widget.currentUserRole,
        text: text.trim(),
        isQuickMessage: isQuick,
      );

      if (!isQuick) {
        _textController.clear();
      }

      // Scroll al final
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      debugPrint('Error enviando mensaje: $e');
    }

    if (mounted) {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              _buildHeader(),

              const Divider(height: 1),

              // Chat inactivo banner
              if (!widget.isActive)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: AppColors.warning.withOpacity(0.1),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Text(
                        'Chat cerrado — Pasajero recogido',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

              // Lista de mensajes
              Expanded(
                child: _buildMessagesList(),
              ),

              // Mensajes rápidos
              if (widget.isActive) _buildQuickMessages(),

              // Input de texto
              if (widget.isActive)
                _buildTextInput(bottomInset),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.1),
            ),
            child: Center(
              child: Text(
                widget.otherUserName.isNotEmpty
                    ? widget.otherUserName[0].toUpperCase()
                    : '?',
                style: AppTextStyles.body1.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.otherUserName,
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.isActive ? 'En línea' : 'Chat cerrado',
                  style: AppTextStyles.caption.copyWith(
                    color: widget.isActive ? AppColors.success : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatService.getMessagesStream(
        widget.tripId,
        widget.passengerId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        final messages = snapshot.data ?? [];

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 48,
                  color: AppColors.textSecondary.withOpacity(0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Envía un mensaje rápido o escribe',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        // Auto-scroll al final cuando llegan nuevos mensajes
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final isMe = msg.senderId == widget.currentUserId;
            return _buildMessageBubble(msg, isMe);
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe
                  ? AppColors.primary.withOpacity(0.15)
                  : AppColors.tertiary,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isMe
                    ? const Radius.circular(16)
                    : const Radius.circular(4),
                bottomRight: isMe
                    ? const Radius.circular(4)
                    : const Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: AppTextStyles.body2.copyWith(
                    color: isMe ? AppColors.primary : AppColors.textPrimary,
                    fontWeight:
                        message.isQuickMessage ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.createdAt),
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickMessages() {
    final quickMsgs = _quickMessages[widget.currentUserRole] ?? [];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: quickMsgs.map((msg) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _sendMessage(msg, isQuick: true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    msg,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTextInput(double bottomInset) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 1,
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...',
                hintStyle: AppTextStyles.body2.copyWith(
                  color: AppColors.textTertiary,
                ),
                filled: true,
                fillColor: AppColors.tertiary,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (text) => _sendMessage(text),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _sendMessage(_textController.text),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _isSending
                    ? AppColors.primary.withOpacity(0.5)
                    : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
