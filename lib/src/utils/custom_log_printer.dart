import 'package:logger/logger.dart';

/// Custom log printer for SpacetimeDB SDK
///
/// Provides different output formats based on log level:
/// - Info (.i): Single-line format with file:line location
/// - Debug (.d): Multi-line pretty format with stack traces
/// - Other levels: Single-line format with level indicator
class CustomLogPrinter extends LogPrinter {
  static final _prettyPrinter = PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.none,
  );

  @override
  List<String> log(LogEvent event) {
    if (event.level == Level.debug) {
      // Use pretty printer for debug logs, but prefix the message
      final modifiedEvent = LogEvent(
        event.level,
        '[SpacetimeDB-Dart-SDK] ${event.message}',
        time: event.time,
        error: event.error,
        stackTrace: event.stackTrace,
      );
      return _prettyPrinter.log(modifiedEvent);
    } else {
      // Single-line format for info and other levels
      return _formatSingleLine(event);
    }
  }

  List<String> _formatSingleLine(LogEvent event) {
    final message = event.message;
    final location = _getCallerLocation();
    final levelIcon = _getLevelIcon(event.level);

    return ['$levelIcon [SpacetimeDB-Dart-SDK] $message ($location)'];
  }

  String _getLevelIcon(Level level) {
    switch (level) {
      case Level.info:
        return '📘';
      case Level.warning:
        return '⚠️';
      case Level.error:
        return '❌';
      case Level.wtf:
        return '💥';
      default:
        return '📝';
    }
  }

  String _getCallerLocation() {
    // Get the stack trace
    final stackTrace = StackTrace.current.toString();
    final lines = stackTrace.split('\n');

    // Look for the first line that's NOT in logger package or this file
    for (final line in lines) {
      if (line.contains('package:logger/') ||
          line.contains('custom_log_printer.dart') ||
          line.contains('dart:core')) {
        continue;
      }

      // Parse the stack trace line to extract file:line
      // Format is typically: "#1      ClassName.methodName (package:name/file.dart:123:45)"
      final match = RegExp(r'\(([^)]+):(\d+):\d+\)').firstMatch(line);
      if (match != null) {
        final fullPath = match.group(1)!;
        final lineNumber = match.group(2)!;

        // Extract just the file name from the path
        final fileName = fullPath.split('/').last;

        return '$fileName:$lineNumber';
      }
    }

    return 'unknown';
  }
}
