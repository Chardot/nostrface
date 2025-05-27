# Profile Content Filtering

## Overview
The app now filters profiles to ensure a high-quality discovery experience by requiring:
1. Valid profile picture URL
2. At least one proper name (name or display_name)
3. A bio/about section

## Requirements

### 1. Profile Picture
- Must have a valid HTTP/HTTPS URL
- See [profile-picture-filtering.md](./profile-picture-filtering.md) for details

### 2. Name Requirements
Profiles must have at least ONE of:
- **name**: Non-empty, trimmed, and not starting with "npub"
- **display_name**: Non-empty, trimmed, and not starting with "npub"

This ensures users have set an actual name rather than just using their public key.

### 3. Bio Requirements
- **about**: Must be non-empty after trimming whitespace
- This ensures users have taken time to describe themselves

## Implementation

### Validation Method (`_hasRequiredProfileInfo`)
```dart
bool _hasRequiredProfileInfo(NostrProfile profile) {
  // Must have either name or display_name (not just npub)
  final hasName = profile.name != null && 
                 profile.name!.trim().isNotEmpty && 
                 !profile.name!.startsWith('npub');
  
  final hasDisplayName = profile.display_name != null && 
                        profile.display_name!.trim().isNotEmpty &&
                        !profile.display_name!.startsWith('npub');
  
  // Must have at least one name
  if (!hasName && !hasDisplayName) {
    return false;
  }
  
  // Must have a bio/about
  final hasBio = profile.about != null && profile.about!.trim().isNotEmpty;
  
  return hasBio;
}
```

## Benefits

1. **Quality Control**: Only shows complete, thoughtful profiles
2. **Better UX**: Users see profiles with actual content to read
3. **Spam Reduction**: Filters out low-effort or bot profiles
4. **Meaningful Connections**: Ensures profiles have enough info for users to make informed follow decisions

## Examples

### Valid Profiles ✓
- Has name: "Alice", display_name: "Alice in Nostrland", about: "Bitcoin enthusiast..."
- Has name: null, display_name: "Bob", about: "Developer building on Nostr"
- Has name: "Carol", display_name: null, about: "Artist and creator"

### Invalid Profiles ✗
- Only has npub as name, no bio
- Has picture but no name and no bio
- Has name but no bio
- Has bio but no name (only npub)
- Empty or whitespace-only fields

## Debug Logging
When profiles are filtered out, debug logs show:
```
Filtered out profile [pubkey] - Has name: false, Has bio: false
Filtered out profile [pubkey] - Has name: true, Has bio: false
Filtered out profile [pubkey] - Has name: false, Has bio: true
```

## User Impact
This filtering ensures that the discovery feed only shows profiles that:
- Have taken time to set up their profile properly
- Provide enough information for meaningful discovery
- Are likely to be real, active users rather than bots or abandoned accounts