import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:spacetimedb_dart_sdk/src/connection/connection_state.dart';
import 'package:spacetimedb_dart_sdk/src/messages/client_messages.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket connection to a SpacetimeDB database
///
/// Manages the lifecycle of a WebSocket connection including:
/// - Initial connection and authentication
/// - Automatic reconnection with exponential backoff
/// - Binary message sending/receiving
/// - Connection state tracking
///
/// Example:
/// ```dart
/// final connection = SpacetimeDbConnection(
///   host: 'localhost:3000',
///   database: 'mydb',
///   authToken: 'optional-token',
/// );
///
/// // Listen to connection state changes
/// connection.onStateChanged.listen((state) {
///   print('Connection state: $state');
/// });
///
/// // Connect
/// await connection.connect();
///
/// // Send binary data
/// connection.send(myBsatnData);
///
/// // Disconnect
/// await connection.disconnect();
/// ```
class SpacetimeDbConnection {
  final String host;
  final String database;
  final String? authToken;

  final Logger _logger = Logger();

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  int _nextRequestId = 1;

  WebSocketChannel? _channel;
  ConnectionState _state = ConnectionState.disconnected;

  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast();
  final StreamController<Uint8List> _messageController =
      StreamController<Uint8List>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<ConnectionState> get onStateChanged => _stateController.stream;

  Stream<Uint8List> get onMessage => _messageController.stream;

  Stream<String> get onError => _errorController.stream;

  SpacetimeDbConnection({
    required this.host,
    required this.database,
    this.authToken,
  });

  ConnectionState get state => _state;

  bool get isConnected => _state == ConnectionState.connected;

  Future<void> connect() async {
    if (_state != ConnectionState.disconnected) {
      _logger.w('Already connected or connecting');
      return;
    }
    _shouldReconnect = true;
    _updateState(ConnectionState.connecting);

    try {
      final uri = Uri.parse('ws://$host/v1/database/$database/subscribe');

      final headers = <String, dynamic>{};
      if (authToken != null) {
        headers['Authorization'] = 'Bearer $authToken';
      }

      _channel = IOWebSocketChannel.connect(
        uri,
        protocols: ['v1.bsatn.spacetimedb'],
        headers: headers,
        connectTimeout: const Duration(seconds: 10),
      );
      await _channel!.ready;
      _setupMessageListener();
      _updateState(ConnectionState.connected);
    } catch (e) {
      _updateState(ConnectionState.disconnected);
      _channel = null;
      rethrow;
    }
  }

  /// Closes the WebSocket connection and stops reconnection attempts
  ///
  /// Example:
  /// ```dart
  /// await connection.disconnect();
  /// print('Disconnected');
  /// ```
  Future<void> disconnect() async {
    if (_state == ConnectionState.disconnected) {
      return;
    }
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _updateState(ConnectionState.disconnected);
    await _channel?.sink.close();
    _channel = null;
  }

  void _updateState(ConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
    }
  }

  /// Sends binary data to the SpacetimeDB server
  ///
  /// The data must be BSATN-encoded. Use [BsatnEncoder] to create properly formatted messages.
  ///
  /// Example:
  /// ```dart
  /// final encoder = BsatnEncoder();
  /// encoder.writeString('Hello, SpacetimeDB!');
  /// connection.send(encoder.toBytes());
  /// ```
  void send(Uint8List data) {
    if (!isConnected) {
      _logger.w('Cannot send: not connected');
      return;
    }
    // Debug: Log message type
    // if (data.isNotEmpty) {
    //   final msgType = data[0];
    //   _logger.d('Sending message type $msgType, length ${data.length} bytes');
    // }
    _channel!.sink.add(data);
  }

  void _setupMessageListener() {
    _channel!.stream.listen(
      (dynamic data) {
        if (data is Uint8List) {
          // if (data.isNotEmpty) {
          //   _logger.d('Received message type ${data[0]}, length ${data.length} bytes');
          // }
          _messageController.add(data);
        } else if (data is List<int>) {
          final bytes = Uint8List.fromList(data);
          // if (bytes.isNotEmpty) {
          //   _logger.d('Received message type ${bytes[0]}, length ${bytes.length} bytes');
          // }
          _messageController.add(bytes);
        }
      },
      onError: (error) {
        final errorMsg = 'WebSocket error: $error';
        _logger.e(errorMsg);
        _errorController.add(errorMsg);
        _updateState(ConnectionState.disconnected);
      },
      onDone: () {
        _logger.i('WebSocket closed');
        _updateState(ConnectionState.disconnected);
        _channel = null;
        _attemptReconnect();
      },
    );
  }

  Duration _getReconnectDelay() {
    // Exponential backoff: 1s, 2s, 4s, 8s, 16s
    final seconds = math.pow(2, _reconnectAttempts).toInt();
    return Duration(seconds: seconds.clamp(1, 30));
  }

  Future<void> _attemptReconnect() async {
    if (!_shouldReconnect || _reconnectAttempts >= _maxReconnectAttempts) {
      return;
    }

    _reconnectAttempts++;
    final delay = _getReconnectDelay();
    _logger.i(
        'Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)');

    _updateState(ConnectionState.reconnecting);
    _reconnectTimer = Timer(delay, () async {
      try {
        await connect();
        _reconnectAttempts = 0; // Reset on success
      } catch (e) {
        await _attemptReconnect(); // Try again
      }
    });
  }

  /// Enables or disables automatic reconnection on connection loss
  ///
  /// When enabled, the connection will automatically attempt to reconnect
  /// using exponential backoff (up to 5 attempts).
  ///
  /// Example:
  /// ```dart
  /// connection.enableAutoReconnect(true);
  /// await connection.connect();
  /// // Connection will auto-reconnect if dropped
  /// ```
  void enableAutoReconnect(bool enabled) {
    _shouldReconnect = enabled;
  }

  /// Manually triggers a reconnection
  ///
  /// Disconnects and immediately reconnects, resetting the reconnection attempt counter.
  ///
  /// Example:
  /// ```dart
  /// await connection.reconnect();
  /// ```
  Future<void> reconnect() async {
    await disconnect();
    _reconnectAttempts = 0;
    _shouldReconnect = true;
    await connect();
  }

  /// Calls a reducer with BSATN-encoded arguments
  ///
  /// Sends a reducer call to the SpacetimeDB server. The reducer will execute
  /// server-side and may modify database state.
  ///
  /// Example:
  /// ```dart
  /// final encoder = BsatnEncoder();
  /// encoder.writeString('My Note');
  /// encoder.writeString('Note content');
  ///
  /// await connection.callReducer('create_note', encoder.toBytes());
  /// ```
  Future<void> callReducer(String reducerName, Uint8List args,
      {int? requestId}) async {
    final message = CallReducerMessage(
      reducerName: reducerName,
      args: args,
      requestId: requestId ?? _nextRequestId++,
    );

    send(message.encode());
  }
}
