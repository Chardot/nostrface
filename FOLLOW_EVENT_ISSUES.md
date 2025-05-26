# Follow Event Publishing Issues

## Current Problems:

1. **No OK Response Handling**: The current `publishEvent` method returns `true` immediately without waiting for relay confirmation. This means we don't know if relays actually accepted the events.

2. **Relay Connectivity**: Some relays in the default list may:
   - Require authentication (NIP-42)
   - Have rate limits
   - Reject events from unknown pubkeys
   - Be offline or unreachable

3. **Event Propagation**: Even if events are published to some relays, they need to be on relays that:
   - Your other Nostr clients connect to
   - Are well-connected in the Nostr network
   - Actually store and serve contact list events

## Solution:

### 1. Implement Proper OK Response Handling
```dart
// Wait for OK response from relay
final okResponse = await waitForOK(eventId, timeout: 10.seconds);
if (okResponse.accepted) {
  print('Event accepted by ${relay.url}');
} else {
  print('Event rejected: ${okResponse.message}');
}
```

### 2. Use Popular, Reliable Relays
Add these commonly-used relays that most clients connect to:
- wss://relay.nostr.info
- wss://nostr.fmt.wiz.biz
- wss://relay.current.fyi
- wss://nostr-pub.wellorder.net

### 3. Show Relay Status in UI
Users should see:
- Which relays accepted their follow events
- Which relays they're connected to
- Option to add their own relay preferences

### 4. Verify Event Signature
Ensure the dart-nostr library is generating valid signatures that other clients can verify.

## Testing:
To verify follows are working:
1. Follow someone in Nostrface
2. Check the console for which relays accepted the event
3. In another client, refresh and check if the follow appears
4. If not, check if both clients share common relays