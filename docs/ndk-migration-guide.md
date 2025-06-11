# NDK Migration Guide

This guide helps developers understand how to use the new NDK-based implementation in Nostrface.

## Overview

The migration to NDK provides:
- Better performance with gossip protocol
- More NIPs supported out of the box
- Pluggable architecture for cache and verification
- Automatic relay discovery and management
- Production-tested codebase

## Quick Start

### 1. Initialize Services

```dart
// In your main.dart or app initialization
await ref.read(servicesInitializerProvider.future);
```

### 2. Authentication

```dart
// Check if user is authenticated
final isAuthenticated = await ref.read(isAuthenticatedProvider.future);

// Get current user pubkey
final pubkey = await ref.read(currentUserPubkeyProvider.future);
```

### 3. Profile Operations

```dart
// Get a profile
final profile = await ref.read(profileByPubkeyProvider(pubkey).future);

// Stream profile updates
ref.watch(metadataStreamProvider(pubkey)).when(
  data: (metadata) {
    if (metadata != null) {
      final profile = NostrProfileAdapter.fromMetadata(metadata);
      // Use profile
    }
  },
  loading: () => CircularProgressIndicator(),
  error: (err, stack) => Text('Error: $err'),
);

// Toggle follow
final profileService = ref.read(profileServiceNdkProvider);
await profileService.toggleFollowProfile(pubkey);

// Check if following
final isFollowing = await ref.read(isFollowingProvider(pubkey).future);
```

### 4. Direct Messages

```dart
final dmService = ref.read(directMessageServiceNdkProvider);

// Send a message
await dmService.sendMessage(
  recipientPubkey: recipientPubkey,
  content: 'Hello!',
);

// Subscribe to messages
await dmService.subscribeToMessages();

// Listen to message stream
dmService.messageStream.listen((message) {
  print('New message: ${message.content}');
});

// Get message history
final history = await dmService.getMessageHistory(pubkey);
```

### 5. Reactions (New!)

```dart
final reactionsService = ref.read(reactionsServiceNdkProvider);

// Add a reaction
await reactionsService.addReaction(
  eventId: eventId,
  reaction: '❤️',
);

// Get reactions for an event
final reactions = await reactionsService.getReactions(eventId);

// Get reaction summary
final summary = await reactionsService.getReactionSummary(eventId);
print('Total reactions: ${summary.totalCount}');
print('Hearts: ${summary.reactions['❤️'] ?? 0}');
```

### 6. Lists Management (New!)

```dart
final listsService = ref.read(listsServiceNdkProvider);

// Mute a user
await listsService.muteUser(pubkey);

// Check if user is muted
final isMuted = await listsService.isUserMuted(pubkey);

// Bookmark an event
await listsService.bookmarkEvent(eventId);

// Get all bookmarked events
final bookmarks = await listsService.getBookmarkedEvents();
```

## Provider Changes

### Old Providers → New Providers

| Old Provider | New Provider | Notes |
|--------------|--------------|-------|
| `profileServiceV2Provider` | `profileServiceNdkProvider` | Enhanced with NDK |
| `nostrRelayServiceProvider` | `ndkServiceProvider` | Relay management built-in |
| `directMessageServiceProvider` | `directMessageServiceNdkProvider` | NIP-44 support coming |
| N/A | `reactionsServiceNdkProvider` | New feature |
| N/A | `listsServiceNdkProvider` | New feature |

## Migration Tips

### 1. Update Imports

```dart
// Old
import 'package:nostrface/core/providers/app_providers.dart';

// New
import 'package:nostrface/core/providers/app_providers_ndk.dart';
```

### 2. Handle Async Initialization

NDK requires async initialization. Always ensure services are initialized:

```dart
// In your widgets
ref.watch(servicesInitializerProvider).when(
  data: (_) => YourContent(),
  loading: () => LoadingScreen(),
  error: (err, stack) => ErrorScreen(error: err),
);
```

### 3. Use Stream Providers

NDK provides real-time updates through streams:

```dart
// Watch profile updates
ref.watch(metadataStreamProvider(pubkey)).when(
  data: (metadata) => ProfileWidget(metadata: metadata),
  loading: () => ProfileSkeleton(),
  error: (err, _) => ErrorWidget(error: err),
);

// Watch following list
ref.watch(userFollowingProvider).when(
  data: (following) => Text('Following ${following.length} users'),
  loading: () => Text('Loading...'),
  error: (err, _) => Text('Error: $err'),
);
```

### 4. Error Handling

NDK provides better error information:

```dart
try {
  await profileService.updateProfile(profile);
} catch (e) {
  if (e is NdkException) {
    // Handle NDK-specific errors
    print('NDK Error: ${e.message}');
  } else {
    // Handle other errors
    print('Error: $e');
  }
}
```

## New Features Available

### 1. Relay Management
- Automatic relay discovery via gossip
- Smart relay selection for queries
- Built-in connection management

### 2. Enhanced Performance
- Request deduplication
- Smart caching strategies
- Bandwidth-aware loading

### 3. New NIPs Support
- NIP-25: Reactions
- NIP-42: Relay authentication
- NIP-44: Versioned encryption (coming)
- NIP-51: Lists (mute, bookmarks, pins)
- NIP-57: Zaps (payment support)
- NIP-65: Relay list metadata

### 4. Better Developer Experience
- Strongly typed models
- Stream-based APIs
- Comprehensive error handling
- Built-in logging

## Troubleshooting

### Issue: "NDK not initialized"
**Solution**: Ensure you await `servicesInitializerProvider` before using services.

### Issue: Profile not loading
**Solution**: Check relay connectivity and ensure bootstrap relays are accessible.

### Issue: Messages not decrypting
**Solution**: Verify private key is available and NIP-04 encryption is working.

### Issue: Slow initial load
**Solution**: This is normal on first run. NDK builds relay connections and discovers optimal relays.

## Next Steps

1. Test all existing features with NDK implementation
2. Add UI for new features (reactions, lists)
3. Consider implementing NIP-47 wallet connect
4. Optimize relay configuration for your use case
5. Monitor performance and adjust cache settings

## Resources

- [NDK Documentation](https://dart-nostr.com)
- [Nostr Protocol NIPs](https://github.com/nostr-protocol/nips)
- [Migration Plan](./nostrface-ndk-migration-plan.md)