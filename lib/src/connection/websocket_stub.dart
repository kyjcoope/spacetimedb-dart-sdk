import 'package:web_socket_channel/web_socket_channel.dart';

/// Stub implementation that throws - replaced by conditional imports
WebSocketChannel connectWebSocket(
  Uri uri,
  Iterable<String>? protocols,
  Map<String, dynamic>? headers,
) {
  throw UnsupportedError('No WebSocket implementation for this platform');
}
