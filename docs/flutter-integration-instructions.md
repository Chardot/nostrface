# Flutter App Integration Guide - Connecting to Nostr Indexing Server

## Overview
This guide explains how to modify your existing Flutter Nostr client to use the profile indexing server instead of filtering profiles locally on the device.

## Server API Specification

### Base URLs
```dart
// Development
const String DEV_API_URL = 'http://localhost:8000';

// Production (update after deployment)
const String PROD_API_URL = 'https://nostr-profile-indexer.deno.dev';
```

### API Endpoints

#### 1. Get Profile Batch
```
GET /api/profiles/batch
```

Query Parameters:
- `count` (optional): Number of profiles to return (default: 50)
- `exclude` (optional): Comma-separated list of pubkeys to exclude
- `session_id` (optional): Session identifier for better curation

Response Format:
```json
{
  "profiles": [
    {
      "pubkey": "hex_string_64_chars",
      "relays": ["wss://relay1.com", "wss://relay2.com"],
      "score": 0.95,
      "last_updated": "2024-06-09T10:30:00Z"
    }
  ],
  "next_cursor": "optional_pagination_token"
}
```

#### 2. Report Interaction (Optional)
```
POST /api/profiles/interaction
```

Request Body:
```json
{
  "session_id": "uuid_string",
  "pubkey": "profile_pubkey",
  "action": "like" | "pass" | "view"
}
```

## Integration Steps

### Step 1: Create API Service
Add a new file `lib/services/indexer_api_service.dart`:

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class IndexerApiService {
  static const String baseUrl = DEV_API_URL; // Change to PROD_API_URL for production
  static final String sessionId = const Uuid().v4();
  
  static Future<List<ProfileReference>> getProfileBatch({
    int count = 50,
    List<String> excludeIds = const [],
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/profiles/batch').replace(
        queryParameters: {
          'count': count.toString(),
          if (excludeIds.isNotEmpty) 'exclude': excludeIds.join(','),
          'session_id': sessionId,
        },
      );
      
      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return (data['profiles'] as List)
            .map((p) => ProfileReference.fromJson(p))
            .toList();
      } else {
        throw Exception('Failed to load profiles: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching profile batch: $e');
      throw e;
    }
  }
  
  static Future<void> reportInteraction({
    required String pubkey,
    required String action,
  }) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/profiles/interaction'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
          'pubkey': pubkey,
          'action': action,
        }),
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      // Don't throw - this is optional functionality
      print('Failed to report interaction: $e');
    }
  }
}
```

### Step 2: Create Profile Reference Model
Add to your models:

```dart
class ProfileReference {
  final String pubkey;
  final List<String> relays;
  final double score;
  final DateTime lastUpdated;
  
  ProfileReference({
    required this.pubkey,
    required this.relays,
    required this.score,
    required this.lastUpdated,
  });
  
  factory ProfileReference.fromJson(Map<String, dynamic> json) {
    return ProfileReference(
      pubkey: json['pubkey'],
      relays: List<String>.from(json['relays']),
      score: json['score'].toDouble(),
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }
}
```

### Step 3: Update Your Profile Buffer Manager

Replace your current local filtering logic:

```dart
class ProfileBufferManager {
  static const int BUFFER_SIZE = 50;
  static const int REFILL_THRESHOLD = 20;
  
  final Queue<Profile> _profileBuffer = Queue();
  final Set<String> _seenProfileIds = {};
  bool _isFetching = false;
  
  // Your existing Nostr service for fetching full profiles
  final NostrService _nostrService;
  
  ProfileBufferManager(this._nostrService);
  
  Future<void> ensureBuffer() async {
    if (_profileBuffer.length < REFILL_THRESHOLD && !_isFetching) {
      _isFetching = true;
      try {
        await _fetchNextBatch();
      } finally {
        _isFetching = false;
      }
    }
  }
  
  Future<void> _fetchNextBatch() async {
    try {
      // 1. Get curated profile IDs from indexing server
      final profileRefs = await IndexerApiService.getProfileBatch(
        count: BUFFER_SIZE,
        excludeIds: _seenProfileIds.toList(),
      );
      
      if (profileRefs.isEmpty) {
        print('No more profiles available from server');
        return;
      }
      
      // 2. Fetch full profiles from Nostr relays using your existing code
      final profiles = await _fetchProfilesFromRelays(profileRefs);
      
      // 3. Add to buffer and track seen IDs
      for (final profile in profiles) {
        _profileBuffer.add(profile);
        _seenProfileIds.add(profile.pubkey);
      }
      
      print('Added ${profiles.length} profiles to buffer');
      
    } catch (e) {
      print('Error fetching batch: $e');
      // Implement retry logic or fallback behavior
    }
  }
  
  Future<List<Profile>> _fetchProfilesFromRelays(
    List<ProfileReference> profileRefs,
  ) async {
    // Use your existing Nostr service to fetch profiles
    // Prioritize relays provided by the server
    final profiles = <Profile>[];
    
    // Parallel fetch with timeout
    final futures = profileRefs.map((ref) async {
      try {
        final profile = await _nostrService.fetchProfile(
          pubkey: ref.pubkey,
          relayHints: ref.relays,
        ).timeout(const Duration(seconds: 3));
        return profile;
      } catch (e) {
        print('Failed to fetch profile ${ref.pubkey}: $e');
        return null;
      }
    });
    
    final results = await Future.wait(futures);
    profiles.addAll(results.where((p) => p != null).cast<Profile>());
    
    return profiles;
  }
  
  Profile? getNextProfile() {
    ensureBuffer(); // Trigger background fetch if needed
    return _profileBuffer.isEmpty ? null : _profileBuffer.removeFirst();
  }
  
  void reportInteraction(String pubkey, String action) {
    // Fire and forget - don't await
    IndexerApiService.reportInteraction(
      pubkey: pubkey,
      action: action,
    );
  }
}
```

### Step 4: Update Your UI Layer

In your swipe screen:

```dart
class SwipeScreen extends StatefulWidget {
  @override
  _SwipeScreenState createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  late ProfileBufferManager _bufferManager;
  Profile? _currentProfile;
  bool _isInitialLoading = true;
  
  @override
  void initState() {
    super.initState();
    _bufferManager = ProfileBufferManager(widget.nostrService);
    _loadInitialProfiles();
  }
  
  Future<void> _loadInitialProfiles() async {
    setState(() => _isInitialLoading = true);
    
    try {
      // Ensure we have some profiles before showing UI
      await _bufferManager.ensureBuffer();
      
      // Wait a bit for buffer to fill
      await Future.delayed(const Duration(seconds: 2));
      
      _loadNextProfile();
    } catch (e) {
      // Handle error - maybe show retry button
      print('Failed to load initial profiles: $e');
    } finally {
      setState(() => _isInitialLoading = false);
    }
  }
  
  void _loadNextProfile() {
    final profile = _bufferManager.getNextProfile();
    setState(() => _currentProfile = profile);
    
    if (profile == null) {
      // No profiles available - show empty state
      _showEmptyState();
    }
  }
  
  void _onSwipe(String action) {
    if (_currentProfile != null) {
      // Report interaction to improve curation
      _bufferManager.reportInteraction(_currentProfile!.pubkey, action);
      
      // Load next profile
      _loadNextProfile();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isInitialLoading) {
      return LoadingScreen(
        message: 'Finding interesting people...',
      );
    }
    
    if (_currentProfile == null) {
      return EmptyStateScreen(
        onRetry: _loadInitialProfiles,
      );
    }
    
    return YourExistingSwipeWidget(
      profile: _currentProfile!,
      onLike: () => _onSwipe('like'),
      onPass: () => _onSwipe('pass'),
    );
  }
}
```

### Step 5: Error Handling and Fallbacks

Add robust error handling:

```dart
class ProfileBufferManager {
  // Add retry logic
  int _retryCount = 0;
  static const int MAX_RETRIES = 3;
  
  Future<void> _fetchNextBatchWithRetry() async {
    try {
      await _fetchNextBatch();
      _retryCount = 0; // Reset on success
    } catch (e) {
      _retryCount++;
      if (_retryCount < MAX_RETRIES) {
        print('Retrying batch fetch (${_retryCount}/$MAX_RETRIES)...');
        await Future.delayed(Duration(seconds: _retryCount * 2));
        await _fetchNextBatchWithRetry();
      } else {
        print('Max retries reached. Falling back to local relay fetch.');
        // Implement fallback to direct relay fetching if needed
        _retryCount = 0;
        throw e;
      }
    }
  }
}
```

## Testing Your Integration

### 1. Local Testing
```dart
// In your debug configuration
const bool USE_LOCAL_SERVER = true;
const String API_BASE_URL = USE_LOCAL_SERVER 
    ? 'http://localhost:8000'  // or your local IP for device testing
    : 'https://your-app.deno.dev';
```

### 2. Test Checklist
- [ ] App successfully fetches profile batches from server
- [ ] Profiles load quickly without 15-second delay
- [ ] Swiping is smooth with no interruptions
- [ ] App handles server downtime gracefully
- [ ] Seen profiles are not shown again
- [ ] Background fetching works while swiping

### 3. Debug Logging
Add debug prints to track the flow:
```dart
print('[BufferManager] Current buffer size: ${_profileBuffer.length}');
print('[BufferManager] Fetching new batch...');
print('[API] Requesting ${BUFFER_SIZE} profiles, excluding ${_seenProfileIds.length} seen');
print('[Nostr] Fetching ${profiles.length} profiles from relays');
```

## Performance Tips

1. **Preload Images**: Start loading profile images as soon as they enter the buffer
2. **Parallel Relay Fetching**: Fetch multiple profiles simultaneously from relays
3. **Smart Caching**: Cache fetched profiles for the session duration
4. **Progressive Loading**: Show profiles as they load rather than waiting for all

## Migration Checklist

- [ ] Add IndexerApiService to your project
- [ ] Update ProfileBufferManager to use server API
- [ ] Add error handling and retry logic
- [ ] Update UI to handle loading states
- [ ] Test with local server
- [ ] Update API URL for production
- [ ] Test on real devices with various network conditions
- [ ] Monitor performance improvements

## Troubleshooting

### Server Connection Issues
- Ensure server is running (`curl http://localhost:8000/api/health`)
- Check CORS settings if getting cross-origin errors
- Verify your device can reach localhost (use computer IP for physical devices)

### Slow Profile Loading
- Check relay connectivity in your Nostr service
- Increase parallel fetch limit
- Add timeout to relay requests

### Empty Profile Buffer
- Verify server is indexing profiles (check server logs)
- Ensure your filter criteria match what server indexes
- Check if you're excluding too many profiles