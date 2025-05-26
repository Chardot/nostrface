# Single Relay Implementation - relay.nos.social

## Overview
The app has been simplified to connect only to a single hardcoded relay: `wss://relay.nos.social`

## Changes Made

### 1. App Providers (`lib/core/providers/app_providers.dart`)
```dart
/// Hardcoded relay for the app
final defaultRelaysProvider = Provider<List<String>>((ref) {
  return [
    'wss://relay.nos.social',
  ];
});

/// Provider for relay URLs - hardcoded to relay.nos.social
final relayUrlsProvider = Provider<List<String>>((ref) {
  return ref.watch(defaultRelaysProvider);
});
```

### 2. Removed Components
- ❌ Relay management screen
- ❌ Relay management service
- ❌ Relay management routes
- ❌ Multiple relay selection UI
- ❌ Relay health monitoring
- ❌ User relay customization

### 3. Current Architecture
- **Single Relay**: All operations go through `relay.nos.social`
- **No UI for relay management**: Users cannot change the relay
- **Simplified ProfileService**: Still supports the infrastructure for multiple relays but only receives one URL
- **Simplified Settings**: No relay-related settings shown to users

## Benefits
1. **Simplicity**: No confusion about which relays to use
2. **Consistency**: All users connect to the same relay
3. **Performance**: No need to manage multiple WebSocket connections
4. **Reliability**: relay.nos.social is a well-maintained, reliable relay

## Technical Details

### Connection Flow
1. App starts → Reads hardcoded relay URL from provider
2. ProfileService initializes with `['wss://relay.nos.social']`
3. Single NostrRelayService instance created
4. All queries and publishes go through this single connection

### Publishing Events
When publishing events (like follow lists), the app:
1. Connects to relay.nos.social
2. Publishes the event
3. Waits for OK response
4. Shows success/failure to user

### Fetching Data
When fetching profiles or notes:
1. Queries relay.nos.social
2. Uses cache for performance
3. Returns results to UI

## Future Considerations
If you need to add relay management back:
1. Create a relay management UI
2. Store user relay preferences
3. Update the provider to read from user preferences
4. Add relay health monitoring

## Current Relay Status
- **URL**: wss://relay.nos.social
- **Type**: General purpose relay
- **Features**: Full NIP support, reliable uptime
- **Geographic**: Global coverage