import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../models/provider.dart';
import '../../providers/language_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';
import 'chat_screen.dart';

/// Client Messages tab.
///
/// Derives live conversations from the client's message threads (streamed
/// via Supabase Realtime), grouped by provider and sorted by recency. Tapping
/// a conversation opens the [ChatScreen] for that thread.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

/// A thread with its provider and messages (newest last).
class _Conversation {
  const _Conversation({required this.provider, required this.messages});

  final Provider provider;
  final List<Message> messages;

  Message get last => messages.last;
}

class _MessagesScreenState extends State<MessagesScreen> {
  final supabase = SupabaseService.instance;

  late final Stream<List<_Conversation>> _stream = _buildStream();

  Stream<List<_Conversation>> _buildStream() {
    final userId = supabase.currentUser?.id;
    if (userId == null) return Stream.value(const []);
    return supabase.watchMessagesForClient(userId).asyncMap((messages) async {
      final providerIds = messages.map((m) => m.providerId).toSet().toList();
      final providers = await supabase.fetchProvidersByIds(providerIds);
      final byId = {for (final p in providers) p.id: p};

      final grouped = <String, List<Message>>{};
      for (final m in messages) {
        grouped.putIfAbsent(m.providerId, () => []).add(m);
      }

      final conversations = grouped.entries
          .map((e) => _Conversation(
                provider: byId[e.key]!,
                messages: e.value,
              ))
          .toList()
        ..sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
      return conversations;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Text(
              context.t('messages'),
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<_Conversation>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: ListSkeleton(count: 4),
                  );
                }
                if (snapshot.hasError) {
                  return ErrorRetry(
                    message: 'Could not load conversations.\n${snapshot.error}',
                    onRetry: () => setState(() {}),
                  );
                }
                final conversations = snapshot.data ?? const <_Conversation>[];
                if (conversations.isEmpty) {
                  return const EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'No conversations yet',
                    subtitle:
                        'Message a stylist from your bookings and it will '
                        'appear here.\n'
                        'Vos discussions apparaîtront ici.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: conversations.length,
                  itemBuilder: (context, i) {
                    final convo = conversations[i];
                    return _ConversationTile(
                      convo: convo,
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              provider: convo.provider,
                              clientId: supabase.currentUser!.id,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.convo, required this.onTap});

  final _Conversation convo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final provider = convo.provider;
    final last = convo.last;
    final avatarUrl = provider.avatarUrl;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0x14000000)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
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
                        errorBuilder: (_, __, ___) => _initials(provider),
                      )
                    : _initials(provider),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.businessName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      last.body,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeLabel(last.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeLabel(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) return formatTime(local);
    return formatShortDate(local);
  }

  Widget _initials(Provider provider) => Center(
        child: Text(
          provider.businessName.isEmpty
              ? '?'
              : provider.businessName.substring(0, 1).toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
