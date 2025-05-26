import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostrface/core/models/nostr_event.dart';

/// Improved relay service that waits for OK responses
class NostrRelayServiceImproved {
  final String relayUrl;
  WebSocketChannel? _channel;
  final StreamController<NostrEvent> _eventStreamController = StreamController<NostrEvent>.broadcast();
  final Map<String, Completer<bool>> _pendingPublishes = {};
  bool _isConnected = false;

  NostrRelayServiceImproved(this.relayUrl);

  bool get isConnected => _isConnected;
  Stream<NostrEvent> get eventStream => _eventStreamController.stream;

  Future<bool> connect() async {
    if (_isConnected) return true;
    
    try {
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      
      _channel!.stream.listen(
        (dynamic message) {
          if (!_isConnected) {
            _isConnected = true;
            if (kDebugMode) {
              print('Connected to relay: $relayUrl');
            }
          }
          _handleMessage(message.toString());
        },
        onDone: () {
          _isConnected = false;
          if (kDebugMode) {
            print('Disconnected from relay: $relayUrl');
          }
        },
        onError: (error) {
          _isConnected = false;
          if (kDebugMode) {
            print('Error from relay $relayUrl: $error');
          }
        },
      );
      
      // Wait a moment for connection
      await Future.delayed(const Duration(seconds: 1));
      
      // Test connection with a simple request
      _testConnection();
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to connect to relay $relayUrl: $e');
      }
      return false;
    }
  }

  void _testConnection() {
    if (_channel?.sink != null) {
      try {
        final testRequest = jsonEncode([
          'REQ',
          'test_${DateTime.now().millisecondsSinceEpoch}',
          {'kinds': [0], 'limit': 1}
        ]);
        _channel!.sink.add(testRequest);
        
        Timer(const Duration(seconds: 2), () {
          if (!_isConnected && _channel?.sink != null) {
            _isConnected = true;
          }
        });
      } catch (e) {
        if (kDebugMode) {
          print('Error testing connection: $e');
        }
      }
    }
  }

  void _handleMessage(String message) {
    try {
      final parsed = jsonDecode(message);
      if (parsed is! List || parsed.isEmpty) return;
      
      final messageType = parsed[0];
      
      switch (messageType) {
        case 'EVENT':
          if (parsed.length >= 3) {
            try {
              final event = NostrEvent.fromJson(parsed[2]);
              _eventStreamController.add(event);
            } catch (e) {
              if (kDebugMode) {
                print('Error parsing event: $e');
              }
            }
          }
          break;
          
        case 'OK':
          if (parsed.length >= 4) {
            final eventId = parsed[1] as String;
            final accepted = parsed[2] as bool;
            final message = parsed.length > 3 ? parsed[3] : '';
            
            if (kDebugMode) {
              print('OK from $relayUrl: Event $eventId ${accepted ? 'accepted' : 'rejected'}${message.isNotEmpty ? ' - $message' : ''}');
            }
            
            // Complete any pending publish futures
            if (_pendingPublishes.containsKey(eventId)) {
              _pendingPublishes[eventId]!.complete(accepted);
              _pendingPublishes.remove(eventId);
            }
          }
          break;
          
        case 'NOTICE':
          if (parsed.length >= 2) {
            if (kDebugMode) {
              print('NOTICE from $relayUrl: ${parsed[1]}');
            }
          }
          break;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling message from $relayUrl: $e');
      }
    }
  }

  /// Publish an event and wait for OK response
  Future<bool> publishEvent(NostrEvent event) async {
    if (!_isConnected) {
      final connected = await connect();
      if (!connected) return false;
    }
    
    if (_channel?.sink == null) {
      if (kDebugMode) {
        print('Cannot publish to $relayUrl: no active connection');
      }
      return false;
    }
    
    try {
      // Create a completer for this event
      final completer = Completer<bool>();
      _pendingPublishes[event.id] = completer;
      
      // Send the event
      final request = ['EVENT', event.toJson()];
      final requestJson = jsonEncode(request);
      
      if (kDebugMode) {
        print('Publishing to $relayUrl: ${event.id}');
        print('Event JSON: $requestJson');
      }
      
      _channel!.sink.add(requestJson);
      
      // Wait for OK response with timeout
      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          if (kDebugMode) {
            print('Timeout waiting for OK from $relayUrl for event ${event.id}');
          }
          _pendingPublishes.remove(event.id);
          return false;
        },
      );
      
      return result;
    } catch (e) {
      if (kDebugMode) {
        print('Error publishing event to $relayUrl: $e');
      }
      _pendingPublishes.remove(event.id);
      return false;
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
    _eventStreamController.close();
    
    // Cancel any pending publishes
    for (final completer in _pendingPublishes.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _pendingPublishes.clear();
  }
}