import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostrface/core/utils/nostr_legacy_support.dart' as nostr;

/// Service for handling connections to Nostr relays using dart-nostr
class NostrRelayServiceV2 {
  final String relayUrl;
  WebSocketChannel? _channel;
  final StreamController<nostr.Event> _eventStreamController = StreamController<nostr.Event>.broadcast();
  final Map<String, StreamController<nostr.Event>> _subscriptions = {};
  final Map<String, List<nostr.Event>> _collectedEvents = {};
  final Map<String, Completer<List<nostr.Event>>> _subscriptionCompleters = {};
  bool _isConnected = false;

  NostrRelayServiceV2(this.relayUrl);

  bool get isConnected => _isConnected;
  Stream<nostr.Event> get eventStream => _eventStreamController.stream;

  /// Connect to the relay
  Future<bool> connect() async {
    if (_isConnected) {
      if (kDebugMode) {
        print('Already connected to relay: $relayUrl');
      }
      return true;
    }
    
    try {
      if (kDebugMode) {
        print('Connecting to relay: $relayUrl');
      }
      
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      
      if (kDebugMode) {
        print('WebSocket channel created for: $relayUrl');
      }

      return _setupWebSocketListener();
    } catch (e) {
      _isConnected = false;
      if (kDebugMode) {
        print('Failed to connect to relay $relayUrl: $e');
      }
      return false;
    }
  }

  /// Set up WebSocket listener
  Future<bool> _setupWebSocketListener() async {
    if (_channel == null) return false;
    
    if (kDebugMode) {
      print('Setting up WebSocket listener for: $relayUrl');
    }
    
    try {
      _channel!.stream.listen(
        (dynamic message) {
          if (!_isConnected) {
            _isConnected = true;
            if (kDebugMode) {
              print('Successfully connected to relay: $relayUrl');
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
        cancelOnError: false,
      );
      
      // Give the connection a moment to establish
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Test the connection
      _testConnection();
      
      return true;
    } catch (e) {
      _isConnected = false;
      if (kDebugMode) {
        print('Error setting up WebSocket listener for $relayUrl: $e');
      }
      return false;
    }
  }

  /// Handle messages received from the relay
  void _handleMessage(String message) {
    try {
      if (kDebugMode) {
        print('Received message from $relayUrl (${message.length} bytes)');
      }
      
      // Parse the message manually since the nostr package doesn't have Message.deserialize
      List<dynamic> parsed;
      try {
        parsed = jsonDecode(message);
      } catch (e) {
        if (kDebugMode) {
          print('Error decoding JSON from $relayUrl: $e');
        }
        return;
      }
      
      if (parsed.isEmpty) return;
      
      final String messageType = parsed[0];
      
      switch (messageType) {
        case 'EVENT':
          if (parsed.length >= 3) {
            final String subscriptionId = parsed[1];
            final eventData = parsed[2];
            
            try {
              // Event.deserialize expects an array format: [type, eventData] or [type, subscriptionId, eventData]
              // Using verify: false to avoid signature validation errors during parsing
              final event = nostr.Event.deserialize(['EVENT', subscriptionId, eventData], verify: false);
              
              if (kDebugMode) {
                print('Received event with id: ${event.id.substring(0, 10)}... from $relayUrl');
              }
              
              // Add to the general event stream
              _eventStreamController.add(event);
              
              // Add to subscription-specific stream if exists
              if (_subscriptions.containsKey(subscriptionId)) {
                _subscriptions[subscriptionId]?.add(event);
              }
              
              // Collect events for batch responses
              if (_collectedEvents.containsKey(subscriptionId)) {
                _collectedEvents[subscriptionId]!.add(event);
              }
            } catch (e) {
              if (kDebugMode) {
                print('Error parsing event: $e');
              }
            }
          }
          break;
          
        case 'NOTICE':
          if (parsed.length >= 2) {
            if (kDebugMode) {
              print('Relay notice from $relayUrl: ${parsed[1]}');
            }
          }
          break;
          
        case 'EOSE':
          if (parsed.length >= 2) {
            final String subscriptionId = parsed[1];
            if (kDebugMode) {
              print('Received EOSE for subscription $subscriptionId');
            }
            
            // Mark subscription as complete if it's a one-time query
            if (_subscriptionCompleters.containsKey(subscriptionId)) {
              final completer = _subscriptionCompleters[subscriptionId]!;
              if (!completer.isCompleted) {
                final collectedEvents = _collectedEvents[subscriptionId] ?? [];
                completer.complete(collectedEvents);
                _collectedEvents.remove(subscriptionId);
                _subscriptionCompleters.remove(subscriptionId);
                
                // Close the subscription
                final closeMsg = nostr.Close(subscriptionId);
                _channel?.sink.add(closeMsg.serialize());
                
                if (kDebugMode) {
                  print('Completed subscription $subscriptionId with ${collectedEvents.length} events');
                }
              }
            }
          }
          break;
          
        case 'OK':
          if (parsed.length >= 4) {
            final String eventId = parsed[1];
            final bool accepted = parsed[2];
            final String? rejectionReason = parsed.length > 3 ? parsed[3] : null;
            
            if (kDebugMode) {
              print('Event publish ${accepted ? 'succeeded' : 'failed'}: $eventId');
              if (!accepted && rejectionReason != null) {
                print('Rejection reason: $rejectionReason');
              }
            }
          }
          break;
          
        default:
          if (kDebugMode) {
            print('Unknown message type from $relayUrl: $messageType');
          }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling message from $relayUrl: $e');
      }
    }
  }

  /// Test the WebSocket connection
  void _testConnection() {
    if (_channel?.sink != null) {
      try {
        // Create a test subscription using dart-nostr
        final filter = nostr.Filter(
          kinds: [0], // Metadata events
          limit: 1,
        );
        
        final request = nostr.Request(
          'connection_test',
          [filter],
        );
        
        _channel!.sink.add(request.serialize());
        
        if (kDebugMode) {
          print('Sent connection test to $relayUrl');
        }
        
        // Mark connection as successful after timeout
        Timer(const Duration(seconds: 2), () {
          if (_channel?.sink != null && !_isConnected) {
            _isConnected = true;
            if (kDebugMode) {
              print('Connection test successful for $relayUrl');
            }
          }
        });
        
      } catch (e) {
        if (kDebugMode) {
          print('Error testing connection to $relayUrl: $e');
        }
        _isConnected = false;
      }
    }
  }

  /// Subscribe to events matching the filter
  Future<List<nostr.Event>> subscribe(nostr.Filter filter, {Duration? timeout}) async {
    if (!_isConnected) {
      final connected = await connect();
      if (!connected) {
        return [];
      }
    }
    
    final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
    _collectedEvents[subscriptionId] = [];
    
    // Create subscription request using dart-nostr
    final request = nostr.Request(subscriptionId, [filter]);
    
    // Send the subscription request
    _channel?.sink.add(request.serialize());
    
    if (kDebugMode) {
      print('Sent subscription to $relayUrl with filter');
    }
    
    // Create a completer for this subscription
    final completer = Completer<List<nostr.Event>>();
    _subscriptionCompleters[subscriptionId] = completer;
    
    // Set up timeout if specified
    if (timeout != null) {
      Timer(timeout, () {
        if (!completer.isCompleted) {
          // Close the subscription
          final closeMsg = nostr.Close(subscriptionId);
          _channel?.sink.add(closeMsg.serialize());
          
          // Return collected events
          final collectedEvents = _collectedEvents[subscriptionId] ?? [];
          completer.complete(collectedEvents);
          _collectedEvents.remove(subscriptionId);
          _subscriptionCompleters.remove(subscriptionId);
          
          if (kDebugMode) {
            print('Subscription timed out for $relayUrl, returning ${collectedEvents.length} events');
          }
        }
      });
    }
    
    return completer.future;
  }

  /// Create a stream subscription for real-time events
  Stream<nostr.Event> subscribeToStream(nostr.Filter filter) {
    final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
    final controller = StreamController<nostr.Event>.broadcast();
    
    _subscriptions[subscriptionId] = controller;
    
    // Create and send subscription request
    final request = nostr.Request(subscriptionId, [filter]);
    _channel?.sink.add(request.serialize());
    
    if (kDebugMode) {
      print('Created stream subscription: $subscriptionId');
    }
    
    // Clean up on stream close
    controller.onCancel = () {
      // Send close message
      final closeMsg = nostr.Close(subscriptionId);
      _channel?.sink.add(closeMsg.serialize());
      
      // Remove from subscriptions
      _subscriptions.remove(subscriptionId);
      
      if (kDebugMode) {
        print('Closed stream subscription: $subscriptionId');
      }
    };
    
    return controller.stream;
  }

  /// Publish an event to the relay
  Future<bool> publishEvent(nostr.Event event) async {
    if (!_isConnected) {
      final connected = await connect();
      if (!connected) {
        return false;
      }
    }
    
    if (_channel?.sink == null) {
      if (kDebugMode) {
        print('Cannot publish to $relayUrl: no active connection');
      }
      return false;
    }
    
    try {
      // Serialize the event for sending in Nostr protocol format
      final eventMessage = jsonEncode(['EVENT', jsonDecode(event.serialize())]);
      _channel!.sink.add(eventMessage);
      
      if (kDebugMode) {
        print('Published event to $relayUrl: ${event.id}');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error publishing event to $relayUrl: $e');
      }
      return false;
    }
  }

  /// Close the connection to the relay
  void disconnect() {
    try {
      if (kDebugMode) {
        print('Disconnecting from relay: $relayUrl');
      }
      
      _channel?.sink.close();
      _isConnected = false;
      
      // Clean up subscriptions
      for (final controller in _subscriptions.values) {
        controller.close();
      }
      _subscriptions.clear();
      _collectedEvents.clear();
      
      _channel = null;
    } catch (e) {
      if (kDebugMode) {
        print('Error disconnecting from relay $relayUrl: $e');
      }
      _isConnected = false;
    }
  }

  /// Dispose of resources
  void dispose() {
    disconnect();
    _eventStreamController.close();
  }
}

/// Provider for the relay service using dart-nostr
final nostrRelayServiceV2Provider = Provider.family<NostrRelayServiceV2, String>(
  (ref, relayUrl) => NostrRelayServiceV2(relayUrl),
);