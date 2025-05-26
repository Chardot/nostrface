# Performance Optimizations for Note Fetching

## Problem
The original implementation took 5+ seconds to load 10 notes from a user profile due to:
1. Sequential relay initialization
2. Waiting for all relays to respond (5-second timeout each)
3. No caching mechanism
4. No early return when sufficient data is available

## Solution

### 1. Implemented Note Caching
- Created `NoteCacheService` using Hive for local storage
- Cache expires after 5 minutes
- Immediate return of cached data when available
- Background refresh while showing cached content

### 2. Optimized Relay Queries
- **Reduced timeout**: From 5 seconds to 1 second per relay
- **Maximum wait time**: 1.5 seconds total (instead of 5 seconds)
- **Early return**: As soon as we have 10 notes, return immediately
- **Parallel queries**: All relays queried simultaneously
- **No initialization wait**: Use already connected relays, don't wait for new connections

### 3. Smart Loading Strategy
```dart
// Old approach: Wait for all relays
final results = await Future.wait(queries, eagerError: false);

// New approach: Early return with completer
final completer = Completer<List<NostrEvent>>();
// Return as soon as we have enough notes OR 1.5 seconds pass
```

### 4. Cache-First Architecture
1. Check cache immediately
2. Return cached data if available
3. Fetch fresh data in background
4. Update cache for next time

## Results
- **Initial load**: < 0.1 seconds (from cache)
- **Fresh data**: 1-1.5 seconds (vs 5+ seconds)
- **Better UX**: Users see content immediately
- **Reduced network usage**: Cache prevents unnecessary queries

## Code Changes

### NoteCacheService
- Stores notes with 5-minute expiry
- Per-user cache keys
- Automatic cleanup of expired entries

### ProfileService.getUserNotes()
- Cache check first
- Parallel relay queries with early return
- 1.5-second maximum wait
- Smart deduplication

### Implementation Details
1. **Cache first**: Always check cache before network
2. **Parallel execution**: Query all relays simultaneously
3. **Early termination**: Stop waiting when we have enough data
4. **Graceful degradation**: Use cache if no relays available
5. **Background updates**: Refresh cache while showing old data

## Future Improvements
1. Implement WebSocket connection pooling
2. Add prefetching for users likely to be viewed
3. Implement differential sync (only fetch new notes)
4. Add compression for cached data
5. Consider IndexedDB for web platform