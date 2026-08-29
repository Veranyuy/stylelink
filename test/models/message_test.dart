import 'package:flutter_test/flutter_test.dart';
import 'package:stylelink/models/message.dart';

void main() {
  group('Message', () {
    group('fromJson', () {
      test('parses a complete message row', () {
        final json = {
          'id': 'm1',
          'client_id': 'c1',
          'provider_id': 'p1',
          'sender_id': 'c1',
          'body': 'Hello, when can I book?',
          'created_at': '2025-08-15T10:30:00Z',
        };

        final message = Message.fromJson(json);

        expect(message.id, 'm1');
        expect(message.clientId, 'c1');
        expect(message.providerId, 'p1');
        expect(message.senderId, 'c1');
        expect(message.body, 'Hello, when can I book?');
        expect(message.createdAt, DateTime.utc(2025, 8, 15, 10, 30));
      });

      test('handles null body gracefully', () {
        final json = {
          'id': 'm2',
          'client_id': 'c1',
          'provider_id': 'p1',
          'sender_id': 'p1',
          'body': null,
          'created_at': '2025-08-15T10:30:00Z',
        };

        final message = Message.fromJson(json);
        expect(message.body, '');
      });
    });

    group('toJson', () {
      test('serializes correctly', () {
        final message = Message(
          id: 'm1',
          clientId: 'c1',
          providerId: 'p1',
          senderId: 'c1',
          body: 'Test message',
          createdAt: DateTime.utc(2025, 8, 15, 10, 30),
        );

        final json = message.toJson();
        expect(json['client_id'], 'c1');
        expect(json['provider_id'], 'p1');
        expect(json['sender_id'], 'c1');
        expect(json['body'], 'Test message');
      });
    });

    group('sentBy', () {
      test('returns true when sender matches', () {
        final message = Message(
          id: 'm1',
          clientId: 'c1',
          providerId: 'p1',
          senderId: 'c1',
          body: 'Hi',
          createdAt: DateTime.now(),
        );

        expect(message.sentBy('c1'), isTrue);
      });

      test('returns false when sender does not match', () {
        final message = Message(
          id: 'm1',
          clientId: 'c1',
          providerId: 'p1',
          senderId: 'c1',
          body: 'Hi',
          createdAt: DateTime.now(),
        );

        expect(message.sentBy('p1'), isFalse);
      });
    });
  });
}
