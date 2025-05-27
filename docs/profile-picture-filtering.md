# Profile Picture Filtering

## Overview
The app filters out profiles with invalid or missing profile pictures to ensure a better user experience. Only profiles with valid URLs are shown in the discovery feed.

## Implementation

### 1. Validation Method (`_isValidProfilePicture`)
The method performs minimal validation to ensure maximum compatibility:
- URL is not null or empty
- URL has valid http/https scheme
- URL has a valid host/authority
- That's it! Any valid http/https URL is accepted

This approach allows users to host their profile images anywhere - on personal servers, custom CDNs, or any hosting provider.

### 2. Filtering Applied
Profile picture validation is applied in two places:
1. **From Relay Events**: When processing metadata events from relays
2. **From Cache**: When loading cached profiles from local storage

### 3. Debug Logging
When a profile is filtered out due to invalid picture URL, a debug message is logged:
```
Filtered out profile [pubkey] with invalid picture URL: [url]
```

## Benefits
1. **Better UX**: Users only see profiles with actual image URLs
2. **Maximum Compatibility**: Works with any image hosting provider
3. **User Freedom**: No restrictions on where images can be hosted
4. **Simple & Reliable**: Basic URL validation ensures stability

## Examples

### Valid URLs
- `https://example.com/avatar.jpg` ✓
- `https://my-server.local/images/me.png` ✓
- `https://192.168.1.100:8080/profile.webp` ✓
- `https://cdn.example.org/user/12345` ✓
- `http://localhost:3000/avatar` ✓ (for development)
- Any valid http/https URL ✓

### Invalid URLs
- `null` or empty string ✗
- `not-a-url` ✗ (invalid URL format)
- `ftp://example.com/image.jpg` ✗ (not http/https)
- `file:///home/user/avatar.png` ✗ (local file)
- `https://` ✗ (no host)
- `javascript:alert('hi')` ✗ (not http/https)

## Future Improvements
1. Implement image URL verification (HEAD request to check availability)
2. Add support for data URLs for small avatars
3. Cache validation results to avoid re-checking
4. Consider adding ipfs:// protocol support for decentralized image hosting