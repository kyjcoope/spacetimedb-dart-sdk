import 'dart:async';
import 'dart:math' as math;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:logger/logger.dart';
import 'package:spacetimedb_dart_sdk/src/connection/connection_state.dart';
import 'package:spacetimedb_dart_sdk/src/connection/connection_status.dart';
import 'package:spacetimedb_dart_sdk/src/connection/connection_quality.dart';
import 'package:spacetimedb_dart_sdk/src/connection/connection_config.dart';
import 'package:spacetimedb_dart_sdk/src/connection/keep_alive_monitor.dart';
import 'package:spacetimedb_dart_sdk/src/messages/client_messages.dart';
import 'package:spacetimedb_dart_sdk/src/utils/custom_log_printer.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Factory function for creating WebSocket channels
/// Allows dependency injection for testing
typedef WebSocketFactory = WebSocketChannel Function(
  Uri uri,
  Iterable<String>? protocols,
  Map<String, dynamic>? headers,
);

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
///   initialToken: 'optional-token',
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
  final String? initialToken;
  final bool ssl;
  final ConnectionConfig config;
  final WebSocketFactory _socketFactory;

  final Logger _logger = Logger(printer: CustomLogPrinter());
  static final _rng = Random.secure();

  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;
  int _nextRequestId = 1;

  // Current authentication token
  String? _currentToken;

  // Keep-alive monitoring
  KeepAliveMonitor? _keepAlive;
  DateTime? _lastMessageReceived;
  DateTime? _lastPingSent;

  WebSocketChannel? _channel;
  ConnectionState _state = ConnectionState.disconnected;

  // Public connection status (for UI binding)
  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();

  // Connection quality tracking
  final StreamController<ConnectionQuality> _qualityController =
      StreamController<ConnectionQuality>.broadcast();
  String? _lastError;
  DateTime? _lastSuccessfulConnection;

  final StreamController<ConnectionState> _stateController =
      StreamController<ConnectionState>.broadcast();
  final StreamController<Uint8List> _messageController =
      StreamController<Uint8List>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  /// Stream of connection status changes for UI binding
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  /// Stream of connection quality metrics
  Stream<ConnectionQuality> get connectionQuality => _qualityController.stream;

  /// Current connection status
  ConnectionStatus get status => _currentStatus;

  Stream<ConnectionState> get onStateChanged => _stateController.stream;

  Stream<Uint8List> get onMessage => _messageController.stream;

  Stream<String> get onError => _errorController.stream;

  SpacetimeDbConnection({
    required this.host,
    required this.database,
    this.initialToken,
    this.ssl = false,
    this.config = const ConnectionConfig(),
    WebSocketFactory? socketFactory,
  })  : _currentToken = initialToken,
        _socketFactory = socketFactory ??
            ((uri, protocols, headers) => IOWebSocketChannel.connect(
                  uri,
                  protocols: protocols,
                  headers: headers,
                  connectTimeout: const Duration(seconds: 10),
                )) {
    _shouldReconnect = config.autoReconnect;
  }

  ConnectionState get state => _state;

  bool get isConnected => _state == ConnectionState.connected;

  /// The current authentication token, if any
  String? get token => _currentToken;

  /// Updates the current authentication token
  ///
  /// This is typically called automatically when an IdentityToken message
  /// is received from the server.
  void updateToken(String token) {
    _currentToken = token;
    _logger.i('Authentication token updated');
  }

  Future<void> connect() async {
    if (_state != ConnectionState.disconnected) {
      _logger.i('Already connected or connecting');
      return;
    }
    _shouldReconnect = true;
    _updateState(ConnectionState.connecting);
    _updateStatus(ConnectionStatus.connecting);

    try {
      final protocol = ssl ? 'wss' : 'ws';
      final uri = Uri.parse('$protocol://$host/v1/database/$database/subscribe');

      final headers = <String, dynamic>{};
      if (_currentToken != null) {
        headers['Authorization'] = 'Bearer $_currentToken';
      }

      _channel = _socketFactory(
        uri,
        ['v1.bsatn.spacetimedb'],
        headers,
      );
      await _channel!.ready;
      _setupMessageListener();
      _setupKeepAlive();
      _updateState(ConnectionState.connected);
      _updateStatus(ConnectionStatus.connected);
      _reconnectAttempts = 0; // Reset on successful connection
    } catch (e) {
      _logger.e('Connection failed: $e');

      // FIX: Update BOTH State and Status to prevent desynchronization
      _updateState(ConnectionState.disconnected);
      _updateStatus(ConnectionStatus.disconnected);

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
    _keepAlive?.stop(); // Stop keep-alive monitoring
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

  void _updateStatus(ConnectionStatus newStatus) {
    if (_currentStatus != newStatus) {
      _currentStatus = newStatus;
      _statusController.add(newStatus);
      _logger.i('Connection status: $newStatus');

      if (newStatus == ConnectionStatus.connected) {
        _lastSuccessfulConnection = DateTime.now();
      }

      _updateQuality();
    }
  }

  void _updateQuality() {
    final quality = ConnectionQuality(
      status: _currentStatus,
      reconnectAttempts: _reconnectAttempts,
      timeSinceLastConnection: _lastSuccessfulConnection != null
          ? DateTime.now().difference(_lastSuccessfulConnection!)
          : null,
      lastError: _lastError,
      lastPingSent: _lastPingSent,
      lastPongReceived: _lastMessageReceived,
    );

    _qualityController.add(quality);
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
      _logger.i('Cannot send: not connected');
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
        // Every single message pushes the next ping 30 seconds into the future
        _keepAlive?.notifyMessageReceived();
        _lastMessageReceived = DateTime.now();

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
        _lastError = errorMsg;
        _errorController.add(errorMsg);
        _updateState(ConnectionState.disconnected);
        _updateQuality();
      },
      onDone: () {
        _logger.i('WebSocket closed');
        _keepAlive?.stop();
        _updateState(ConnectionState.disconnected);

        // Determine if this is first disconnect or a reconnection scenario
        if (_currentStatus == ConnectionStatus.connecting) {
          // First connection failed
          _updateStatus(ConnectionStatus.disconnected);
        } else if (_currentStatus == ConnectionStatus.connected) {
          // Was connected, now lost connection
          _updateStatus(ConnectionStatus.reconnecting);
        }

        _channel = null;
        _attemptReconnect();
      },
    );
  }

  Duration _getReconnectDelay() {
    // Exponential backoff based on config
    final baseSeconds = config.baseReconnectDelay.inMilliseconds;
    final delayMs = baseSeconds * math.pow(2, _reconnectAttempts);
    final maxMs = config.maxReconnectDelay.inMilliseconds;
    return Duration(milliseconds: delayMs.toInt().clamp(baseSeconds, maxMs));
  }

  Future<void> _attemptReconnect() async {
    if (!config.autoReconnect || !_shouldReconnect) return;

    // Check for fatal error condition
    if (_reconnectAttempts >= config.maxReconnectAttempts) {
      _logger.e('Max reconnection attempts reached. Giving up.');
      _updateStatus(ConnectionStatus.fatalError);
      _shouldReconnect = false;
      return;
    }

    _reconnectAttempts++;
    final delay = _getReconnectDelay();
    _logger.i(
        'Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts/${config.maxReconnectAttempts})');

    _updateState(ConnectionState.reconnecting);
    _updateStatus(ConnectionStatus.reconnecting);
    _reconnectTimer = Timer(delay, () async {
      try {
        await connect();
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

  /// Manually retry connection after fatal error
  ///
  /// Resets the reconnection counter and attempts to connect again.
  /// Should only be called when status is [ConnectionStatus.fatalError] or
  /// [ConnectionStatus.disconnected].
  ///
  /// Example:
  /// ```dart
  /// if (connection.status == ConnectionStatus.fatalError) {
  ///   await connection.retryConnection();
  /// }
  /// ```
  Future<void> retryConnection() async {
    if (_currentStatus != ConnectionStatus.fatalError &&
        _currentStatus != ConnectionStatus.disconnected) {
      throw StateError('Cannot retry when status is $_currentStatus');
    }

    _logger.i('Manual retry initiated');
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
  ///
  /// **Note:** This is a low-level method that sends the message but doesn't
  /// track the response. For full async/await support with TransactionResult,
  /// use `SubscriptionManager.reducers.call()` instead.
  @Deprecated('Use SubscriptionManager.reducers.call() for async/await support')
  Future<void> callReducer(String reducerName, Uint8List args,
      {int? requestId}) async {
    final message = CallReducerMessage(
      reducerName: reducerName,
      args: args,
      requestId: requestId ?? _nextRequestId++,
    );

    send(message.encode());
  }

  // Keep-alive monitoring

  void _setupKeepAlive() {
    _keepAlive = KeepAliveMonitor(
      onSendPing: () {
        _logger.i('Connection idle - sending keep-alive ping');
        try {
          final messageId = Uint8List(16);
          for (var i = 0; i < 16; i++) {
            messageId[i] = _rng.nextInt(256);
          }
          const pingQuery = 'SELECT * FROM __spacetime_dart_sdk_keepalive__';

          // 3. Send the keep-alive query
          final message = OneOffQueryMessage(
            messageId: messageId,
            queryString: pingQuery,
          );
          send(message.encode());
          _lastPingSent = DateTime.now();
        } catch (e) {
          _logger.e('Failed to send keep-alive ping: $e');
        }
      },
      onDisconnect: () {
        _logger.i('Keep-alive timeout - connection declared dead');
        _handleStaleConnection();
      },
      idleThreshold: config.pingInterval,
      pongTimeout: config.pongTimeout,
    );
  }

  void _handleStaleConnection() {
    // Close the connection
    _channel?.sink.close();
    _channel = null;

    _updateState(ConnectionState.disconnected);
    _updateStatus(ConnectionStatus.reconnecting);

    _attemptReconnect();
  }

  /// Disposes of resources used by this connection
  ///
  /// Closes all stream controllers and disconnects from the server.
  /// Should be called when the connection is no longer needed.
  ///
  /// Example:
  /// ```dart
  /// await connection.dispose();
  /// ```
  Future<void> dispose() async {
    _keepAlive?.stop();
    await disconnect();
    await _statusController.close();
    await _qualityController.close();
    await _stateController.close();
    await _messageController.close();
    await _errorController.close();
  }
}
