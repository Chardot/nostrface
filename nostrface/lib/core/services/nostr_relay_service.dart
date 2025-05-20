import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'package:nostrface/core/models/nostr_profile.dart';

/// Service for handling connections to Nostr relays
class NostrRelayService {
  final String relayUrl;
  WebSocketChannel? _channel;
  final StreamController<NostrEvent> _eventStreamController = StreamController<NostrEvent>.broadcast();
  final Map<String, Completer<List<NostrEvent>>> _subscriptions = {};
  bool _isConnected = false;

  NostrRelayService(this.relayUrl);

  bool get isConnected => _isConnected;
  Stream<NostrEvent> get eventStream => _eventStreamController.stream;

  /// Connect to the relay
  Future<bool> connect() async {
    if (_isConnected) return true;
    
    try {
      if (kDebugMode) {
        print('Connecting to relay: $relayUrl');
      }
      
      // Use WebSocketChannel for both web and native platforms
      _channel = WebSocketChannel.connect(Uri.parse(relayUrl));
      _isConnected = true;

      // Listen for incoming messages from the relay
      _channel!.stream.listen(
        (dynamic message) {
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

      return true;
    } catch (e) {
      _isConnected = false;
      if (kDebugMode) {
        print('Failed to connect to relay $relayUrl: $e');
      }
      return false;
    }
  }

  /// Close the connection to the relay
  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
  }

  /// Handle messages received from the relay
  void _handleMessage(String message) {
    try {
      if (kDebugMode) {
        print('Received message from $relayUrl: ${message.length > 100 ? message.substring(0, 100) + '...' : message}');
      }
      
      final List<dynamic> parsed = jsonDecode(message);
      
      if (parsed.isEmpty) return;
      
      final String messageType = parsed[0];
      
      switch (messageType) {
        case 'EVENT':
          if (parsed.length >= 3) {
            final String subscriptionId = parsed[1];
            final eventData = parsed[2];
            
            try {
              final event = NostrEvent.fromJson(eventData);
              
              if (kDebugMode) {
                print('Received event with id: ${event.id.substring(0, 10)}... from $relayUrl');
              }
              
              // Add the event to the stream so listeners can handle it
              _eventStreamController.add(event);
              
            } catch (e) {
              if (kDebugMode) {
                print('Error parsing event: $e');
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
            final bool success = parsed[2] as bool;
            if (kDebugMode) {
              print('Event publish ${success ? 'succeeded' : 'failed'}: ${parsed[1]}');
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
      
      // If connection failed and we're on web, fall back to mock data for better UX
      if (!connected && kIsWeb) {
        if (kDebugMode) {
          print('Connection failed, falling back to mock data for $relayUrl');
        }
        return _getMockEvents(filter);
      }
      
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
  
  /// Generate mock events for web platform testing
  List<NostrEvent> _getMockEvents(Map<String, dynamic> filter) {
    List<NostrEvent> mockEvents = [];
    
    // Check if this is a request for profile metadata
    if (filter['kinds'] != null && filter['kinds'].contains(NostrEvent.metadataKind)) {
      // Create some mock profiles
      for (int i = 0; i < 10; i++) {
        final pubkey = 'mock_pubkey_$i';
        final profile = NostrProfile(
          pubkey: pubkey,
          name: 'User $i',
          displayName: 'Test User $i',
          picture: 'https://picsum.photos/500/500?random=$i',
          banner: 'https://picsum.photos/1000/300?random=$i',
          about: 'This is a mock profile bio for testing on the web platform. User $i is a test user.',
          website: 'https://example.com',
          nip05: 'user$i@example.com',
        );
        
        // Create a mock event for this profile
        final event = NostrEvent(
          id: 'mock_event_$i',
          pubkey: pubkey,
          created_at: DateTime.now().subtract(Duration(days: i)).millisecondsSinceEpoch ~/ 1000,
          kind: NostrEvent.metadataKind,
          tags: [],
          content: jsonEncode(profile.toJson()),
          sig: 'mock_signature',
        );
        
        mockEvents.add(event);
      }
    }
    
    return mockEvents;
  }

  /// Publish an event to the relay
  Future<bool> publishEvent(NostrEvent event) async {
    if (!_isConnected) {
      await connect();
    }
    
    // Create the publish request
    final List<dynamic> request = ['EVENT', event.toJson()];
    
    // Send the publish request to the relay
    _channel?.sink.add(jsonEncode(request));
    
    // In a real implementation, you would listen for the OK response
    // For now, just return true
    return true;
  }
}

/// Provider for the relay service
final nostrRelayServiceProvider = Provider.family<NostrRelayService, String>(
  (ref, relayUrl) => NostrRelayService(relayUrl),
);

/// Provider for a list of default relays
final defaultRelaysProvider = Provider<List<String>>((ref) {
  return [
    'wss://relay.damus.io',
    'wss://relay.nostr.band',
    'wss://nos.lol',
    'wss://nostr.wine',
    'wss://relay.snort.social',
    'wss://relay.nostr.bg',
    'wss://purplepag.es',
    'wss://relay.nostr.com.au',
    'wss://nostr-pub.wellorder.net',
    'wss://nostr.mutinywallet.com',
  ];
});