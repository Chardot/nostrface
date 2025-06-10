# Nostr Indexer Integration Documentation

## Overview
This document describes the integration between nostrface and the Nostr indexing server for faster profile discovery.

## Changes Made

### 1. New Services Created

#### IndexerApiService (`lib/core/services/indexer_api_service.dart`)
- Handles communication with the indexing server
- Provides `getProfileBatch()` to fetch curated profile references
- Provides `reportInteraction()` to send user feedback for better curation
- Configurable between development and production URLs

#### ProfileBufferServiceIndexed (`lib/core/services/profile_buffer_service_indexed.dart`)
- Enhanced buffer service that uses the indexer API
- Maintains a queue of profiles ready for display
- Implements retry logic and fallback to direct relay fetching
- Provides progressive loading with background prefetching

### 2. New UI Components

#### DiscoveryScreenIndexed (`lib/features/profile_discovery/presentation/screens/discovery_screen_indexed.dart`)
- Updated discovery screen that uses the indexed buffer service
- Shows loading state with "Using indexed server for faster loading" message
- Reports user interactions (like/pass/view) back to the indexer

### 3. Configuration

#### API URLs
```dart
// In indexer_api_service.dart
static const String DEV_API_URL = 'http://localhost:8000';
static const String PROD_API_URL = 'https://nostr-profile-indexer.deno.dev';
static const bool USE_LOCAL_SERVER = true; // Toggle this for production
```

### 4. Providers Updated

Added new providers in `app_providers.dart`:
- `profileServiceV2Provider` - ProfileServiceV2 instance
- `profileBufferServiceIndexedProvider` - Indexed buffer service
- `indexedBufferedProfilesProvider` - Stream of buffered profiles
- `indexedBufferLoadingProvider` - Loading state stream

### 5. Router Updated

The app router now uses `DiscoveryScreenIndexed` instead of `DiscoveryScreenNew`.

## How It Works

1. **Initial Load**: When the app starts, it requests an initial batch of profile IDs from the indexer
2. **Profile Fetching**: The app fetches full profile data from Nostr relays using the IDs
3. **Background Loading**: As users swipe, the app prefetches more profiles in the background
4. **User Feedback**: Swipe actions are reported back to the indexer to improve curation
5. **Fallback**: If the indexer is unavailable, the app falls back to direct relay discovery

## Performance Benefits

- **Faster Initial Load**: No more 15-second wait for profile discovery
- **Better Curation**: Server pre-filters profiles for quality
- **Reduced Relay Load**: Only fetches specific profiles instead of scanning all relays
- **Progressive Loading**: Users can start swiping while more profiles load in background

## Testing

### Local Testing
1. Run your indexer server locally on port 8000
2. Set `USE_LOCAL_SERVER = true` in `indexer_api_service.dart`
3. Run the Flutter app

### Production Testing
1. Deploy your indexer to Deno Deploy
2. Update `PROD_API_URL` with your deployment URL
3. Set `USE_LOCAL_SERVER = false`
4. Run the Flutter app

## Debugging

Enable debug output by running in debug mode. Key log prefixes:
- `[IndexerAPI]` - API communication logs
- `[ProfileBuffer]` - Buffer management logs
- `[Discovery]` - Discovery screen logs

## Future Improvements

1. Add caching of profile references for offline support
2. Implement profile scoring based on user preferences
3. Add analytics dashboard for indexer performance
4. Support for filtering profiles by interests/topics