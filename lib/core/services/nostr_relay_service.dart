import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:nostrface/core/models/nostr_event.dart';

/// Service for handling connections to Nostr relays
class NostrRelayService {
  final String relayUrl;
  WebSocketChannel? _channel;
  final StreamController<NostrEvent> _eventStreamController = StreamController<NostrEvent>.broadcast();
  final Map<String, Completer<List<NostrEvent>>> _subscriptions = {};
  final Map<String, Completer<bool>> _pendingPublishes = {};
  bool _isConnected = false;

  NostrRelayService(this.relayUrl);

  bool get isConnected => _isConnected;
  Stream<NostrEvent> get eventStream => _eventStreamController.stream;

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
      
      // For web platforms, use a different strategy due to CORS restrictions
      if (kIsWeb) {
        return _connectWeb();
      } else {
        return _connectNative();
      }
    } catch (e) {
      _isConnected = false;
      if (kDebugMode) {
        print('Failed to connect to relay $relayUrl: $e');
      }
      return false;
    }
  }

  /// Connect using native WebSocket for mobile/desktop platforms
  Future<bool> _connectNative() async {
    try {
      if (kDebugMode) {
        print('Creating native WebSocket connection to: $relayUrl');
      }
      
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      
      if (kDebugMode) {
        print('WebSocket channel created for: $relayUrl');
      }

      return _setupNativeWebSocketListener();
    } catch (e) {
      _isConnected = false;
      if (kDebugMode) {
        print('Failed to create native WebSocket for $relayUrl: $e');
      }
      return false;
    }
  }

  /// Connect using a web-compatible approach
  Future<bool> _connectWeb() async {
    if (kDebugMode) {
      print('Using web-compatible connection strategy for: $relayUrl');
    }
    
    try {
      // Try to connect to the actual relay through WebSocket
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      
      if (kDebugMode) {
        print('WebSocket channel created for web: $relayUrl');
      }
      
      return _setupNativeWebSocketListener();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to create WebSocket for web $relayUrl: $e');
      }
      
      // If real connection fails, we could fall back to simulated data
      // But for now, let's just return false to indicate connection failure
      _isConnected = false;
      return false;
    }
  }

  /// Set up WebSocket listener for native platforms
  Future<bool> _setupNativeWebSocketListener() async {
    if (_channel == null) return false;
    
    if (kDebugMode) {
      print('Setting up native WebSocket listener for: $relayUrl');
    }
    
    try {
      _channel!.stream.listen(
        (dynamic message) {
          // If we get a message, we're definitely connected
          if (!_isConnected) {
            _isConnected = true;
            if (kDebugMode) {
              print('Successfully connected to relay: $relayUrl');
            }
          }
          
          if (kDebugMode) {
            print('Received message from $relayUrl (${message.toString().length} bytes)');
          }
          
          try {
            _handleMessage(message.toString());
          } catch (e) {
            if (kDebugMode) {
              print('Error handling message from $relayUrl: $e');
            }
          }
        },
        onDone: () {
          _isConnected = false;
          if (kDebugMode) {
            print('Disconnected from relay: $relayUrl (stream done)');
          }
        },
        onError: (error) {
          _isConnected = false;
          if (kDebugMode) {
            print('Error from relay $relayUrl: $error');
          }
        },
        cancelOnError: false, // Don't cancel on errors, keep trying
      );
      
      if (kDebugMode) {
        print('WebSocket listener set up successfully for: $relayUrl');
      }
      
      // Give the connection a moment to establish
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // Test the connection by sending a simple subscription
      _testConnection();
      
      return true;
    } catch (e) {
      _isConnected = false;
      if (kDebugMode) {
        print('Error setting up WebSocket stream listener for $relayUrl: $e');
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
      
      // Cancel any pending publishes
      for (final completer in _pendingPublishes.values) {
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      }
      _pendingPublishes.clear();
      
      // Force garbage collection of channel in web
      if (kIsWeb) {
        _channel = null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error disconnecting from relay $relayUrl: $e');
      }
      _isConnected = false;
    }
  }

  /// Test the WebSocket connection by sending a simple subscription
  void _testConnection() {
    if (_channel?.sink != null) {
      try {
        // Send a simple subscription to test the connection
        // This subscription requests recent metadata events (kind 0)
        final testSubscription = [
          'REQ',
          'connection_test',
          {
            'kinds': [0], // Metadata events
            'limit': 1,
          }
        ];
        
        final message = jsonEncode(testSubscription);
        _channel!.sink.add(message);
        
        if (kDebugMode) {
          print('Sent connection test to $relayUrl');
        }
        
        // Set up a timeout to mark connection as successful if no immediate error
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

  /// Handle messages received from the relay
  void _handleMessage(String message) {
    try {
      // Don't log the full message to avoid UTF-8 issues in console
      if (kDebugMode) {
        print('Received message from $relayUrl (${message.length} bytes)');
      }
      
      // Safely parse JSON with try-catch
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
              // Sanitize event content if it's a profile metadata event
              if (eventData is Map && 
                  eventData['kind'] == NostrEvent.metadataKind && 
                  eventData['content'] is String) {
                try {
                  // Try to sanitize the content
                  final content = eventData['content'] as String;
                  
                  // Check if content is valid JSON
                  try {
                    // Parse the content to see if it's valid JSON
                    final contentMap = jsonDecode(content);
                    
                    // If name contains invalid UTF-8, sanitize it
                    if (contentMap is Map && contentMap['name'] is String) {
                      final name = contentMap['name'] as String;
                      if (name.contains('\u{FFFD}')) {
                        // Replace the name with a sanitized version
                        contentMap['name'] = _sanitizeString(name);
                        // Replace the content with the sanitized JSON
                        eventData['content'] = jsonEncode(contentMap);
                      }
                    }
                  } catch (_) {
                    // If content is not valid JSON, leave it as is
                  }
                } catch (_) {
                  // Ignore sanitization errors and continue with original data
                }
              }
              
              final event = NostrEvent.fromJson(eventData);
              
              if (kDebugMode) {
                print('Received event with id: ${event.id.substring(0, 10)}... from $relayUrl');
              }
              
              // Add the event to the stream so listeners can handle it
              _eventStreamController.add(event);
              
            } catch (e) {
              if (kDebugMode) {
                print('Error parsing event from $relayUrl: $e');
              }
            }
          }
          break;
          
        case 'EOSE':
          // End of stored events for a subscription
          if (parsed.length >= 2) {
            final String subscriptionId = parsed[1];
            if (kDebugMode) {
              print('Received EOSE for subscription $subscriptionId');
            }
            
            // We don't complete the completer here anymore.
            // The timeout will handle completion with the collected events.
            // This allows us to receive events after EOSE (realtime updates).
          }
          break;
          
        case 'OK':
          // Event publish confirmation
          if (parsed.length >= 3) {
            final String eventId = parsed[1];
            final bool success = parsed[2] as bool;
            final String message = parsed.length > 3 ? parsed[3] : '';
            
            if (kDebugMode) {
              print('\n=== OK RESPONSE FROM $relayUrl ===');
              print('Event ID: $eventId');
              print('Accepted: $success');
              if (message.isNotEmpty) {
                print('Message: $message');
              }
              print('================================\n');
            }
            
            // Complete the pending publish future
            if (_pendingPublishes.containsKey(eventId)) {
              _pendingPublishes[eventId]!.complete(success);
              _pendingPublishes.remove(eventId);
            }
          }
          break;
          
        case 'NOTICE':
          // Relay notice
          if (parsed.length >= 2) {
            if (kDebugMode) {
              print('Relay notice from $relayUrl: ${parsed[1]}');
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

  /// Subscribe to events matching the filter
  Future<List<NostrEvent>> subscribe(Map<String, dynamic> filter, {Duration? timeout}) async {
    if (!_isConnected) {
      final connected = await connect();
      
      // If connection failed, return empty list
      if (!connected) {
        return [];
      }
    }
    
    // Store collected events for this subscription
    List<NostrEvent> collectedEvents = [];
    
    final subscriptionId = const Uuid().v4();
    final completer = Completer<List<NostrEvent>>();
    _subscriptions[subscriptionId] = completer;
    
    // Listen for events and store them
    final eventListener = _eventStreamController.stream.listen((event) {
      // Check if this event matches our filter
      if (_eventMatchesFilter(event, filter)) {
        collectedEvents.add(event);
        if (kDebugMode) {
          print('Got matching event from $relayUrl: ${event.id.substring(0, 10)}...');
        }
      }
    });
    
    // Create the subscription request
    final List<dynamic> request = ['REQ', subscriptionId, filter];
    
    // Send the subscription request to the relay
    _channel?.sink.add(jsonEncode(request));
    
    if (kDebugMode) {
      print('Sent subscription to $relayUrl: ${jsonEncode(filter)}');
    }
    
    // If a timeout is specified, close the subscription after the timeout
    if (timeout != null) {
      Timer(timeout, () {
        if (_subscriptions.containsKey(subscriptionId)) {
          // Close the subscription on the relay
          _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
          
          // If the completer is not completed yet, complete it with collected events
          if (!completer.isCompleted) {
            if (kDebugMode) {
              print('Subscription timed out for $relayUrl, returning ${collectedEvents.length} events');
            }
            completer.complete(collectedEvents);
          }
          
          // Clean up
          _subscriptions.remove(subscriptionId);
          eventListener.cancel();
        }
      });
    }
    
    return completer.future;
  }
  
  /// Check if an event matches a filter
  bool _eventMatchesFilter(NostrEvent event, Map<String, dynamic> filter) {
    // Check kind
    if (filter['kinds'] != null) {
      if (filter['kinds'] is List && !filter['kinds'].contains(event.kind)) {
        return false;
      }
    }
    
    // Check authors
    if (filter['authors'] != null) {
      if (filter['authors'] is List && !filter['authors'].contains(event.pubkey)) {
        return false;
      }
    }
    
    // Add more filter checks as needed
    
    return true; // Event matches filter
  }
  
  /// Sanitize a string by removing invalid UTF-8 characters
  String _sanitizeString(String input) {
    // Replace the Unicode replacement character with empty string
    String sanitized = input.replaceAll('\u{FFFD}', '');
    
    // Replace any other problematic characters
    sanitized = sanitized.replaceAll(RegExp(r'[\u{D800}-\u{DFFF}]'), '');
    
    // Remove any zero-width characters
    sanitized = sanitized.replaceAll(RegExp(r'[\u{200B}-\u{200D}\u{FEFF}]'), '');
    
    return sanitized;
  }
  

  /// Publish an event to the relay
  Future<bool> publishEvent(NostrEvent event) async {
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
      // Create a completer for this event publish
      final completer = Completer<bool>();
      _pendingPublishes[event.id] = completer;
      
      // Create the publish request
      final List<dynamic> request = ['EVENT', event.toJson()];
      
      // Send the publish request to the relay
      _channel!.sink.add(jsonEncode(request));
      
      if (kDebugMode) {
        print('Publishing event to $relayUrl: ${event.id}');
      }
      
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
      
      if (kDebugMode) {
        print('Event ${event.id} ${result ? 'accepted' : 'rejected'} by $relayUrl');
      }
      
      return result;
    } catch (e) {
      if (kDebugMode) {
        print('Error publishing event to $relayUrl: $e');
      }
      _pendingPublishes.remove(event.id);
      return false;
    }
  }
}

/// Provider for the relay service
final nostrRelayServiceProvider = Provider.family<NostrRelayService, String>(
  (ref, relayUrl) => NostrRelayService(relayUrl),
);

// The provider moved to app_providers.dart