import 'package:flutter/material.dart';

import '../../models/message.dart';
import '../../models/profile.dart';
import '../../providers/language_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/formatters.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_views.dart';
import '../client/chat_screen.dart';

/// Provider Messages tab.
///
/// Shows all conversations grouped by client, sorted by recency.
/// Tapping a conversation opens the [ChatScreen] for that thread.
class ProviderMessagesScreen extends StatefulWidget {
  const ProviderMessagesScreen({super.key});

  @override
  State<ProviderMessagesScreen> createState() => _ProviderMessagesScreenState();
}

class _ProviderConversation {
  const _ProviderConversation({required this.client, required this.messages});

  final Profile client;
  final List<Message> messages;

  Message get last => messages.last;
}

class _ProviderMessagesScreenState extends State<ProviderMessagesScreen> {
  final supabase = SupabaseService.instance;

  late final Stream<List<_ProviderConversation>> _stream = _buildStream();

  Stream<List<_ProviderConversation>> _buildStream() async* {
    final userId = supabase.currentUser?.id;
    if (userId == null) {
      yield const [];
      return;
    }

    final providerId = await _resolveProviderId(userId);
    if (providerId == null) {
      yield const [];
      return;
    }

    await for (final messages in supabase.watchMessagesForProvider(providerId)) {
      final clientIds = messages.map((m) => m.clientId).toSet().toList();
      final clients = await supabase.fetchProfilesByIds(clientIds);
      final clientsById = {for (final c in clients) c.id: c};

      final grouped = <String, List<Message>>{};
      for (final m in messages) {
        grouped.putIfAbsent(m.clientId, () => []).add(m);
      }

      final conversations = grouped.entries
          .map((e) {
            final client = clientsById[e.key];
            if (client == null) return null;
            return _ProviderConversation(
              client: client,
              messages: e.value,
            );
          })
          .whereType<_ProviderConversation>()
          .toList()
        ..sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
      yield conversations;
    }
  }

  Future<String?> _resolveProviderId(String userId) async {
    final provider = await supabase.fetchProviderByUserId(userId);
    return provider?.id;
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
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<_ProviderConversation>>(
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
                    message:
                        'Could not load conversations.\n${snapshot.error}',
                    onRetry: () => setState(() {}),
                  );
                }
                final conversations =
                    snapshot.data ?? const <_ProviderConversation>[];
                if (conversations.isEmpty) {
                  return const EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: 'No conversations yet',
                    subtitle:
                        'Clients will message you from their bookings.\n'
                        'Les clients vous contacteront depuis leurs réservations.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  itemCount: conversations.length,
                  itemBuilder: (context, i) {
                    final convo = conversations[i];
                    return _ProviderConversationTile(
                      convo: convo,
                      onTap: () async {
                        final providerId = await _resolveProviderId(
                          supabase.currentUser!.id,
                        );
                        if (providerId == null || !context.mounted) return;
                        final provider =
                            await supabase.fetchProviderById(providerId);
                        if (provider == null || !context.mounted) return;
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              provider: provider,
                              clientId: convo.client.id,
                              counterpartName: convo.client.fullName,
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

class _ProviderConversationTile extends StatelessWidget {
  const _ProviderConversationTile({
    required this.convo,
    required this.onTap,
  });

  final _ProviderConversation convo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final client = convo.client;
    final last = convo.last;
    final avatarUrl = client.avatarUrl;

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
                    colors: [Color(0xFF9E86E6), Color(0xFFB8A5F0)],
                  ),
                ),
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _initials(client),
                      )
                    : _initials(client),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      client.fullName ?? 'Client',
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

  Widget _initials(Profile client) => Center(
        child: Text(
          (client.fullName ?? '?').isNotEmpty
              ? (client.fullName ?? '?')[0].toUpperCase()
              : '?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
