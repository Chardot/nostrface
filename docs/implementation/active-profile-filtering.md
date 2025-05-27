# Active Profile Filtering

## Overview

The Active Profile Filtering feature ensures that users only discover profiles from active Nostr users who have posted content. This prevents the discovery feed from being cluttered with inactive or placeholder accounts, significantly improving the quality of profile recommendations.

## Problem Statement

Many Nostr profiles exist without any posted content:
- Users who created accounts but never posted
- Bot accounts that were never activated
- Test accounts or placeholders
- Users who only lurk without contributing

These empty profiles dilute the discovery experience, as users expect to find interesting people with content to explore.

## Solution Design

### 1. Post Count Integration

The post count check is integrated into the profile readiness validation:

```dart
// In ProfileReadinessService
Future<bool> isProfileReady(NostrProfile profile, {int? postCount}) async {
  // ... other checks ...
  
  // Check if user has posts
  final userPostCount = _postCountCache[profile.pubkey] ?? postCount ?? 0;
  if (userPostCount == 0) {
    if (kDebugMode) {
      print('Profile ${profile.displayNameOrName} has no posts, not ready for presentation');
    }
    return false;
  }
  
  // ... continue with other validations
}
```

### 2. Efficient Post Detection

The system uses an optimized approach to check for posts:

```dart
// In profile preparation phase
try {
  // Only fetch 1 post to check if user has any content
  final notes = await _profileService.getUserNotes(profile.pubkey, limit: 1);
  postCount = notes.isNotEmpty ? 1 : 0;
  
  if (postCount > 0) {
    _readinessService.updatePostCount(profile.pubkey, postCount);
  }
} catch (e) {
  // Handle errors gracefully
  postCount = 0;
}
```

Key optimizations:
- **Minimal Fetch**: Only retrieves 1 post per user
- **Early Exit**: Stops as soon as any post is found
- **Parallel Processing**: Checks multiple profiles simultaneously
- **Caching**: Stores results to avoid repeated checks

### 3. Batch Processing Flow

The system processes profiles in efficient batches:

```dart
// Process profiles in small batches
const batchSize = 3;

final results = await Future.wait(
  batch.map((profile) async {
    // 1. Check post count
    final notes = await _profileService.getUserNotes(profile.pubkey, limit: 1);
    final postCount = notes.isNotEmpty ? 1 : 0;
    
    // 2. Validate profile with post count
    final isReady = await _readinessService.isProfileReady(
      profile, 
      postCount: postCount
    );
    
    // 3. Only preload images for profiles with posts
    if (!isReady && profile.picture != null && postCount > 0) {
      final preloaded = await _readinessService.preloadProfileImage(profile);
      return (profile, preloaded);
    }
    
    return (profile, isReady);
  }),
);
```

## Implementation Details

### Profile Discovery Enhancement

An optional post checking feature was added to the discovery method:

```dart
Future<List<NostrProfile>> discoverProfiles({
  int limit = 10,
  DiscardedProfilesService? discardedService,
  FailedImagesService? failedImagesService,
  bool checkPosts = false  // Optional post filtering
}) async {
  // ... fetch profiles ...
  
  if (checkPosts && candidateProfiles.isNotEmpty) {
    // Filter profiles with posts in parallel batches
    final profilesWithPosts = await _filterProfilesWithPosts(
      candidateProfiles, 
      limit
    );
    return profilesWithPosts;
  }
  
  return candidateProfiles.take(limit).toList();
}
```

### Caching Strategy

Post counts are cached to improve performance:

```dart
class ProfileReadinessService {
  // Cache for user post counts
  final Map<String, int> _postCountCache = {};
  
  void updatePostCount(String pubkey, int count) {
    _postCountCache[pubkey] = count;
  }
}
```

## User Experience Impact

1. **Quality over Quantity**: Users see fewer but more relevant profiles
2. **Engagement**: Every discovered profile has content to explore
3. **Efficiency**: No wasted swipes on empty profiles
4. **Performance**: Smart caching minimizes relay queries

## Performance Considerations

- **Relay Load**: Each profile requires 1 additional query for posts
- **Mitigation**: Batch processing and caching reduce impact
- **Timeout Handling**: Failed post queries don't block profile loading
- **Graceful Degradation**: Profiles with query errors are filtered out

## Future Enhancements

1. **Post Frequency Analysis**: Prioritize recently active users
2. **Content Type Filtering**: Filter by specific post types (text, images, etc.)
3. **Engagement Metrics**: Consider replies and interactions
4. **Configurable Thresholds**: Let users set minimum post counts

## Testing Guidelines

When testing this feature:
1. Create test profiles with varying post counts (0, 1, many)
2. Verify only profiles with posts appear in discovery
3. Check console logs for filtering messages
4. Test with slow network to ensure timeout handling
5. Verify profile view shows "No posts available" for empty profiles

## Configuration

Currently, the post filter is always active during profile preparation. Future versions could make this configurable:

```dart
// Potential future configuration
final profileSettings = ProfileFilterSettings(
  requirePosts: true,
  minimumPostCount: 1,
  checkPostsWithinDays: 30,  // Only check recent activity
);
```

## Conclusion

The Active Profile Filtering feature significantly improves the discovery experience by ensuring users only encounter profiles with actual content. This creates a more engaging and valuable social discovery platform where every swipe leads to interesting content and potential connections.