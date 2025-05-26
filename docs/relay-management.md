# Relay Management Implementation Guide for Nostrface

This document provides a comprehensive guide for implementing relay management in a Nostr client application. Following these steps will create a robust relay management system that handles WebSocket connections, event publishing, and subscription management.

## Overview

The relay management system consists of several key components:
1. **NostrRelayService**: Individual relay connection management
2. **RelayManagementService**: Centralized relay coordination
3. **ProfileService**: Integration with relay services for data fetching
4. **Event Publishing**: Handling event creation and relay responses
5. **Web Platform Support**: Special handling for browser environments

## Architecture

```
┌─────────────────────────┐
│   RelayManagementService│ (Singleton for Web)
│   - Manages all relays  │
│   - Coordinates events  │
└───────────┬─────────────┘
            │
      ┌─────┴─────┬─────────┬─────────┐
      │           │         │         │
┌─────▼─────┐ ┌──▼───┐ ┌──▼───┐ ┌──▼───┐
│NostrRelay │ │Relay │ │Relay │ │Relay │
│Service #1 │ │  #2  │ │  #3  │ │  #n  │
└───────────┘ └──────┘ └──────┘ └──────┘
```

## Step 1: Create the NostrEvent Model

Create `/lib/core/models/nostr_event.dart`:

```dart
class NostrEvent {
  static const int metadataKind = 0;
  static const int textNoteKind = 1;
  static const int contactsKind = 3;
  static const int directMessageKind = 4;
  static const int encryptedDirectMessageKind = 44;

  final String id;
  final String pubkey;
  final int created_at;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  NostrEvent({
    required this.id,
    required this.pubkey,
    required this.created_at,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  factory NostrEvent.fromJson(Map<String, dynamic> json) {
    return NostrEvent(
      id: json['id'] as String,
      pubkey: json['pubkey'] as String,
      created_at: json['created_at'] as int,
      kind: json['kind'] as int,
      tags: (json['tags'] as List<dynamic>)
          .map((tag) => (tag as List<dynamic>).map((e) => e.toString()).toList())
          .toList(),
      content: json['content'] as String,
      sig: json['sig'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': created_at,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };
}
```

## Step 2: Create the Relay Publish Result Model

Create `/lib/core/models/relay_publish_result.dart`:

```dart
class RelayPublishResult {
  final String eventId;
  final Map<String, bool> relayResults;

  RelayPublishResult({
    required this.eventId,
    required this.relayResults,
  });

  int get successCount => relayResults.values.where((success) => success).length;
  int get totalRelays => relayResults.length;
  double get successRate => totalRelays > 0 ? successCount / totalRelays : 0.0;
  bool get isSuccess => successCount > 0;
  
  List<String> get failedRelays => relayResults.entries
      .where((entry) => !entry.value)
      .map((entry) => entry.key)
      .toList();
}
```

## Step 3: Implement NostrRelayService

Create `/lib/core/services/nostr_relay_service.dart`:

### Key Features:
1. **WebSocket Connection Management**
2. **Subscription Handling with Timeouts**
3. **Event Publishing with OK Response Handling**
4. **Automatic Reconnection Logic**
5. **Platform-Specific Connection Handling**

### Implementation Details:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/html.dart';

class NostrRelayService {
  final String relayUrl;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  
  // Event stream for incoming events
  final StreamController<NostrEvent> _eventStreamController = 
      StreamController<NostrEvent>.broadcast();
  
  // Active subscriptions
  final Map<String, StreamSubscription<NostrEvent>> _subscriptions = {};
  
  // Pending publish operations waiting for OK responses
  final Map<String, Completer<bool>> _pendingPublishes = {};
  
  // Connection state tracking
  bool _isConnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  bool get isConnected => _isConnected;
  Stream<NostrEvent> get eventStream => _eventStreamController.stream;

  /// Connect to the relay
  Future<bool> connect() async {
    if (_isConnected || _isConnecting) return _isConnected;
    
    _isConnecting = true;
    
    try {
      // Platform-specific WebSocket creation
      if (kIsWeb) {
        _channel = HtmlWebSocketChannel.connect(relayUrl);
      } else {
        final uri = Uri.parse(relayUrl);
        _channel = IOWebSocketChannel.connect(uri);
      }
      
      // Listen to incoming messages
      _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleConnectionClosed,
      );
      
      // Test connection with a simple subscription
      await _testConnection();
      
      _isConnected = true;
      _reconnectAttempts = 0;
      
      return true;
    } catch (e) {
      print('Error connecting to $relayUrl: $e');
      _handleReconnection();
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final List<dynamic> data = jsonDecode(message);
      final String messageType = data[0];
      
      switch (messageType) {
        case 'EVENT':
          _handleEventMessage(data);
          break;
        case 'OK':
          _handleOkMessage(data);
          break;
        case 'EOSE':
          // End of stored events - subscription complete
          print('EOSE received for subscription ${data[1]}');
          break;
        case 'NOTICE':
          print('Notice from $relayUrl: ${data[1]}');
          break;
      }
    } catch (e) {
      print('Error handling message from $relayUrl: $e');
    }
  }

  /// Handle EVENT messages
  void _handleEventMessage(List<dynamic> data) {
    if (data.length >= 3) {
      try {
        final event = NostrEvent.fromJson(data[2]);
        _eventStreamController.add(event);
      } catch (e) {
        print('Error parsing event: $e');
      }
    }
  }

  /// Handle OK messages for event publishing
  void _handleOkMessage(List<dynamic> data) {
    if (data.length >= 4) {
      final eventId = data[1] as String;
      final success = data[2] as bool;
      final message = data.length > 3 ? data[3] as String : '';
      
      if (_pendingPublishes.containsKey(eventId)) {
        _pendingPublishes[eventId]!.complete(success);
        _pendingPublishes.remove(eventId);
        
        if (!success) {
          print('Event $eventId rejected by $relayUrl: $message');
        }
      }
    }
  }

  /// Subscribe to events with a filter
  Future<List<NostrEvent>> subscribe(
    Map<String, dynamic> filter, {
    Duration? timeout = const Duration(seconds: 5),
  }) async {
    if (!_isConnected) {
      await connect();
      if (!_isConnected) return [];
    }
    
    final subscriptionId = DateTime.now().millisecondsSinceEpoch.toString();
    final completer = Completer<List<NostrEvent>>();
    final collectedEvents = <NostrEvent>[];
    
    // Listen for events matching this subscription
    final eventListener = _eventStreamController.stream.listen((event) {
      if (_eventMatchesFilter(event, filter)) {
        collectedEvents.add(event);
      }
    });
    
    _subscriptions[subscriptionId] = eventListener;
    
    // Send subscription request
    final request = ['REQ', subscriptionId, filter];
    _channel?.sink.add(jsonEncode(request));
    
    // Set up timeout
    if (timeout != null) {
      Timer(timeout, () {
        if (!completer.isCompleted) {
          // Close subscription
          _channel?.sink.add(jsonEncode(['CLOSE', subscriptionId]));
          
          // Complete with collected events
          completer.complete(collectedEvents);
          
          // Clean up
          _subscriptions[subscriptionId]?.cancel();
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
      if (!_isConnected) return false;
    }
    
    try {
      // Create completer for OK response
      final completer = Completer<bool>();
      _pendingPublishes[event.id] = completer;
      
      // Send event
      final message = ['EVENT', event.toJson()];
      _channel?.sink.add(jsonEncode(message));
      
      // Wait for OK response with timeout
      final result = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _pendingPublishes.remove(event.id);
          return false;
        },
      );
      
      return result;
    } catch (e) {
      print('Error publishing event to $relayUrl: $e');
      _pendingPublishes.remove(event.id);
      return false;
    }
  }

  /// Check if an event matches a filter
  bool _eventMatchesFilter(NostrEvent event, Map<String, dynamic> filter) {
    // Kind filter
    if (filter['kinds'] != null) {
      final kinds = filter['kinds'] as List;
      if (!kinds.contains(event.kind)) return false;
    }
    
    // Author filter
    if (filter['authors'] != null) {
      final authors = filter['authors'] as List;
      if (!authors.contains(event.pubkey)) return false;
    }
    
    // ID filter
    if (filter['ids'] != null) {
      final ids = filter['ids'] as List;
      if (!ids.contains(event.id)) return false;
    }
    
    // Tag filters (#e, #p, etc.)
    for (final key in filter.keys) {
      if (key.startsWith('#')) {
        final tagName = key.substring(1);
        final tagValues = filter[key] as List;
        
        bool hasMatchingTag = false;
        for (final tag in event.tags) {
          if (tag.isNotEmpty && tag[0] == tagName && 
              tag.length > 1 && tagValues.contains(tag[1])) {
            hasMatchingTag = true;
            break;
          }
        }
        
        if (!hasMatchingTag) return false;
      }
    }
    
    return true;
  }

  /// Disconnect from the relay
  void disconnect() {
    _isConnected = false;
    _channel?.sink.close();
    _channel = null;
    
    // Cancel all subscriptions
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    
    // Cancel pending publishes
    for (final completer in _pendingPublishes.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _pendingPublishes.clear();
    
    // Cancel reconnection timer
    _reconnectTimer?.cancel();
  }

  /// Clean up resources
  void dispose() {
    disconnect();
    _eventStreamController.close();
  }
}
```

## Step 4: Create RelayManagementService

Create `/lib/core/services/relay_management_service.dart`:

### Purpose:
- Centralized management of multiple relay connections
- Singleton pattern for web environments to avoid duplicate connections
- Coordinates event publishing across all relays
- Manages relay health and connection states

### Implementation:

```dart
class RelayManagementService {
  final List<String> _relayUrls;
  final Map<String, NostrRelayService> _relayServices = {};
  static RelayManagementService? _instance;
  
  // Singleton for web environments
  static RelayManagementService getInstance(List<String> relayUrls) {
    _instance ??= RelayManagementService._(relayUrls);
    return _instance!;
  }
  
  RelayManagementService._(this._relayUrls) {
    _initializeRelays();
  }
  
  Future<void> _initializeRelays() async {
    for (final url in _relayUrls) {
      final relay = NostrRelayService(url);
      _relayServices[url] = relay;
      
      // Connect to relay
      relay.connect().then((connected) {
        if (connected) {
          print('Connected to relay: $url');
        }
      });
    }
  }
  
  /// Publish event to all connected relays
  Future<RelayPublishResult> publishToAllRelays(NostrEvent event) async {
    final results = <String, bool>{};
    
    for (final entry in _relayServices.entries) {
      if (entry.value.isConnected) {
        final success = await entry.value.publishEvent(event);
        results[entry.key] = success;
      } else {
        results[entry.key] = false;
      }
    }
    
    return RelayPublishResult(
      eventId: event.id,
      relayResults: results,
    );
  }
  
  /// Get all connected relay services
  List<NostrRelayService> get connectedRelays {
    return _relayServices.values
        .where((relay) => relay.isConnected)
        .toList();
  }
}
```

## Step 5: Configure Default Relays

Create `/lib/core/providers/app_providers.dart`:

```dart
final defaultRelayUrls = [
  'wss://relay.damus.io',
  'wss://relay.nostr.band',
  'wss://nos.lol',
  'wss://relay.snort.social',
  'wss://relay.current.fyi',
  'wss://relay.nostr.info',
  'wss://nostr.wine',
  'wss://relay.nostr.bg',
  'wss://nostr.mom',
  'wss://relay.nostr.com.au',
];
```

## Step 6: Integrate with ProfileService

Update ProfileService to use relay services:

### Web Environment:
```dart
ProfileService.withRelayManagement(RelayManagementService relayManagementService) {
  // Use shared relay connections from RelayManagementService
  _relayServices.addAll(relayManagementService.connectedRelays);
}
```

### Mobile Environment:
```dart
ProfileService(List<String> relayUrls) {
  // Create dedicated relay connections
  for (final url in relayUrls) {
    final relay = NostrRelayService(url);
    _relayServices.add(relay);
    relay.connect();
  }
}
```

## Step 7: Handle Event Publishing

When publishing events (e.g., follow lists):

```dart
Future<RelayPublishResult> publishContactList(List<String> followedPubkeys) async {
  // Create contact list event using dart-nostr
  final event = nostr.Event.from(
    kind: 3, // Contact list
    tags: followedPubkeys.map((pk) => ['p', pk]).toList(),
    content: '',
    privkey: userPrivateKey,
  );
  
  // Convert to app's NostrEvent model
  final nostrEvent = NostrEvent.fromJson({
    'id': event.id,
    'pubkey': event.pubkey,
    'created_at': event.createdAt,
    'kind': event.kind,
    'tags': event.tags,
    'content': event.content,
    'sig': event.sig,
  });
  
  // Publish to all relays
  final results = <String, bool>{};
  
  for (final relay in _relayServices) {
    if (relay.isConnected) {
      final success = await relay.publishEvent(nostrEvent);
      results[relay.relayUrl] = success;
      
      // Log for debugging
      print('### Event ID: ${event.id} published to relay: ${relay.relayUrl} - Success: $success');
    }
  }
  
  return RelayPublishResult(
    eventId: event.id,
    relayResults: results,
  );
}
```

## Step 8: Web-Specific Considerations

### CORS Issues:
Some relays may have CORS restrictions. Handle gracefully:

```dart
// In web environments, connection failures might be due to CORS
if (kIsWeb && !connected) {
  print('Relay $relayUrl may have CORS restrictions');
}
```

### Connection Pooling:
Use singleton pattern to avoid multiple connections to same relay:

```dart
// In main.dart for web
if (kIsWeb) {
  final relayManagement = RelayManagementService.getInstance(defaultRelayUrls);
  // Share this instance across services
}
```

## Step 9: Error Handling and Resilience

### Automatic Reconnection:
```dart
void _handleReconnection() {
  if (_reconnectAttempts < _maxReconnectAttempts) {
    _reconnectTimer = Timer(
      Duration(seconds: math.pow(2, _reconnectAttempts).toInt()),
      () {
        _reconnectAttempts++;
        connect();
      },
    );
  }
}
```

### Timeout Handling:
- Subscriptions timeout after specified duration (default 5s)
- Publish operations timeout after 10s
- Connection tests timeout after 2s

## Step 10: UI Integration

### Show Relay Status:
```dart
// In UI
Text('Published to ${result.successCount}/${result.totalRelays} relays')
```

### Handle Publishing Feedback:
```dart
final result = await profileService.toggleFollowProfile(pubkey);

if (result.isSuccess) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Published to ${result.successCount} relays'),
    ),
  );
}
```

## Testing Considerations

1. **Mock WebSocket Connections**: Use mock channels for testing
2. **Test Timeout Scenarios**: Ensure graceful handling
3. **Test Reconnection Logic**: Verify exponential backoff
4. **Test CORS Handling**: For web platform testing

## Performance Optimizations

1. **Connection Pooling**: Reuse connections across services
2. **Batch Operations**: Send multiple subscriptions together
3. **Event Deduplication**: Filter duplicate events from multiple relays
4. **Lazy Connection**: Connect to relays only when needed

## Security Considerations

1. **Validate Events**: Verify event signatures
2. **Sanitize Content**: Handle malicious content safely
3. **Rate Limiting**: Implement client-side rate limiting
4. **Secure WebSocket**: Always use wss:// (never ws://)

## Debugging

Enable debug logs to see:
- Connection status for each relay
- Event publishing results
- Subscription responses
- OK message handling

Example debug output:
```
### Event ID: abc123... published to relays: wss://relay.damus.io, wss://nos.lol, wss://relay.snort.social
```

This comprehensive relay management system provides robust handling of Nostr relay connections with proper error handling, platform-specific considerations, and user feedback mechanisms.