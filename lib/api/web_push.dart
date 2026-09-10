// Payloads of the Web Push notifications sent by Consort's server.
//
// These are shaped for a browser's service worker to show directly,
// so they carry a ready-made title and body rather than the details
// of the message.  For how the server builds them, see
// zerver/lib/push_notifications.py in Consort's Zulip server fork.

/// A Web Push notification payload from the server.
sealed class WebPushPayload {
  const WebPushPayload();

  /// Throws if [json] isn't a payload we understand.
  factory WebPushPayload.fromJson(Map<String, dynamic> json) {
    return switch (json['type']) {
      'add' => WebPushAddPayload.fromJson(json),
      'remove' => WebPushRemovePayload.fromJson(json),
      _ => throw const FormatException('unexpected Web Push payload type'),
    };
  }
}

/// A payload announcing a new message.
class WebPushAddPayload extends WebPushPayload {
  const WebPushAddPayload({
    required this.messageId,
    required this.title,
    required this.body,
  });

  final int messageId;
  final String title;
  final String body;

  factory WebPushAddPayload.fromJson(Map<String, dynamic> json) => WebPushAddPayload(
    messageId: json['message_id'] as int,
    title: json['title'] as String,
    body: json['body'] as String,
  );
}

/// A payload saying these messages were read,
/// so their notifications should go away.
class WebPushRemovePayload extends WebPushPayload {
  const WebPushRemovePayload({required this.messageIds});

  final List<int> messageIds;

  factory WebPushRemovePayload.fromJson(Map<String, dynamic> json) => WebPushRemovePayload(
    messageIds: (json['message_ids'] as List<dynamic>)
      .map((id) => id as int).toList(),
  );
}
