/// Strongly-typed model for the `public.messages` table.
///
/// One row is one direct message inside a client<->provider thread. The
/// thread is identified by (`clientId`, `providerId`); `senderId` tells
/// which participant wrote the row. Realtime on this table keeps open chat
/// screens live.
class Message {
  final String id;
  final String clientId; // references profiles(id)
  final String providerId; // references providers(id)
  final String senderId; // references profiles(id)
  final String body;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.clientId,
    required this.providerId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      providerId: json['provider_id'] as String,
      senderId: json['sender_id'] as String,
      body: json['body'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'provider_id': providerId,
        'sender_id': senderId,
        'body': body,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  /// Whether the given user wrote this message.
  bool sentBy(String userId) => senderId == userId;
}
