import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// IO (mobile/desktop) WebSocket implementation
WebSocketChannel connectWebSocket(
  Uri uri,
  Iterable<String>? protocols,
  Map<String, dynamic>? headers,
) {
  return IOWebSocketChannel.connect(
    uri,
    protocols: protocols,
    headers: headers,
    connectTimeout: const Duration(seconds: 10),
  );
}
