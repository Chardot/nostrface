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
  bool _isConnected = false;

  NostrRelayService(this.relayUrl);

  bool get isConnected => _isConnected;
  Stream<NostrEvent> get eventStream => _eventStreamController.stream;

  /// Connect to the relay
  Future<bool> connect() async {
    if (_isConnected) return true;

    try {
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
              _eventStreamController.add(event);
              
              // If this is part of a subscription, add it to the results
              if (_subscriptions.containsKey(subscriptionId)) {
                // This is a trick to collect events for a subscription while it's active
                // The actual completion of the subscription happens via EOSE
              }
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
            if (_subscriptions.containsKey(subscriptionId)) {
              // In a real implementation, you would collect the events
              // and resolve the completer with the collected events
              _subscriptions[subscriptionId]?.complete([]);
              _subscriptions.remove(subscriptionId);
            }
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
              print('Relay notice: ${parsed[1]}');
            }
          }
          break;
          
        default:
          if (kDebugMode) {
            print('Unknown message type: $messageType');
          }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling message: $e');
      }
    }
  }

  /// Subscribe to events matching the filter
  Future<List<NostrEvent>> subscribe(Map<String, dynamic> filter, {Duration? timeout}) async {
    if (!_isConnected) {
      await connect();
    }
    
    final subscriptionId = const Uuid().v4();
    final completer = Completer<List<NostrEvent>>();
    _subscriptions[subscriptionId] = completer;
    
    // Create the subscription request
    final List<dynamic> request = ['REQ', subscriptionId, filter];
    
    // Send the subscription request to the relay
    _channel?.sink.add(jsonEncode(request));
    
    // If a timeout is specified, close the subscription after the timeout
    if (timeout != null) {
      Timer(timeout, () {
        if (_subscriptions.containsKey(subscriptionId)) {
          // Close the subscription on the relay
          _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
          
          // If the completer is not completed yet, complete it with an empty list
          if (!completer.isCompleted) {
            completer.complete([]);
          }
          
          _subscriptions.remove(subscriptionId);
        }
      });
    }
    
    return completer.future;
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
    'wss://relay.current.fyi',
    'wss://relay.snort.social',
  ];
});