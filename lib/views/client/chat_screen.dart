import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../models/provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../widgets/state_views.dart';

/// Direct chat between a client and a provider.
///
/// Streams the thread from `public.messages` via Supabase Realtime, renders
/// the conversation oldest-first and lets the user send a new message. Used
/// from the client Messages tab and the Bookings tab ("Message Provider"),
/// and from the provider dashboard ("Message Client").
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.provider,
    required this.clientId,
    this.counterpartName,
  });

  /// The provider on the other side of the thread (both sides of the app
  /// show this as the thread title).
  final Provider provider;

  /// The client participant of the thread.
  final String clientId;

  /// Optional display name for the counterpart (used on the provider side,
  /// where the client's name is shown as the thread title instead).
  final String? counterpartName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final supabase = SupabaseService.instance;
  final _input = TextEditingController();

  late final Stream<List<Message>> _stream = supabase.watchMessages(
    clientId: widget.clientId,
    providerId: widget.provider.id,
  );

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    final user = supabase.currentUser;
    if (body.isEmpty || user == null) return;
    _input.clear();
    try {
      await supabase.sendMessage(
        clientId: widget.clientId,
        providerId: widget.provider.id,
        senderId: user.id,
        body: body,
      );
      // The realtime stream pushes the message back; no local append needed.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send message: $e'),
          backgroundColor: const Color(0xFFB3261E),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: 0,
        title: Row(
          children: [
            _Avatar(provider: widget.provider),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.counterpartName ?? widget.provider.businessName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.counterpartName == null
                        ? '${widget.provider.category} · ${widget.provider.city}'
                        : 'StyleLink chat / Discussion',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return ErrorRetry(
                    message: 'Could not load messages.\n${snapshot.error}',
                    onRetry: () => setState(() {}),
                  );
                }
                final messages = snapshot.data ?? const <Message>[];
                if (messages.isEmpty) {
                  return const EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'Say hello!',
                    subtitle:
                        'Start the conversation with your stylist.\n'
                        'Commencez la conversation avec votre styliste.',
                  );
                }
                final userId = supabase.currentUser?.id;
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final message = messages[messages.length - 1 - i];
                    return _MessageBubble(
                      message: message,
                      mine: message.senderId == userId,
                    );
                  },
                );
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .05),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Message…',
                  filled: true,
                  fillColor: const Color(0xFFF3EFEC),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: _send,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF4665C),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFF4665C) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: const Color(0x14000000)),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: mine ? Colors.white : const Color(0xFF2A2730),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              formatTime(message.createdAt.toLocal()),
              style: TextStyle(
                fontSize: 10,
                color: mine
                    ? Colors.white.withValues(alpha: .75)
                    : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.provider});

  final Provider provider;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = provider.avatarUrl;
    return Container(
      width: 36,
      height: 36,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFFF8B7B), Color(0xFF9E86E6)],
        ),
      ),
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? Image.network(
              avatarUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initials(),
            )
          : _initials(),
    );
  }

  Widget _initials() => Center(
        child: Text(
          provider.businessName.isEmpty
              ? '?'
              : provider.businessName.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
