# NostrFace Performance Analysis

## App Launch to First Profile Display Timeline

This document analyzes the performance characteristics of NostrFace from app launch to the first profile cards being displayed in the UI, based on console output from a test run.

## Executive Summary

- **Total time to first profiles**: 17,918ms (~18 seconds)
- **Main bottleneck**: Profile discovery from relay (15 seconds)
- **Initial profiles displayed**: Only 2 profiles (despite fetching 121 events)
- **Profile rejection rate**: ~87% (106 out of 121 rejected)

## Detailed Timeline

### Phase 1: App Initialization (0-147ms) ✅
Very fast initialization phase.

| Milestone | Time | Duration | Notes |
|-----------|------|----------|-------|
| App Start | 0ms | - | Baseline timestamp |
| Flutter Binding | 12ms | 12ms | Framework initialization |
| Hive Database | 14ms | 2ms | Local storage setup |
| runApp() | 15ms | 1ms | App widget tree creation |
| Discovery Screen | 147ms | 132ms | Navigation and screen init |

### Phase 2: Network Setup (147-1,004ms) ⚡
Establishing WebSocket connections to Nostr relay.

| Milestone | Time | Duration | Notes |
|-----------|------|----------|-------|
| ProfileService Init | ~150ms | 5ms | Service setup |
| Relay Connection Start | ~150ms | - | Connecting to relay.nos.social |
| Relay Connected | 1,004ms | ~854ms | WebSocket established |

### Phase 3: Profile Discovery (1,004-16,018ms) 🐌
**This is the primary bottleneck.**

| Milestone | Time | Duration | Notes |
|-----------|------|----------|-------|
| First Fetch Attempt | 1,004ms | - | Returned 0 profiles |
| Second Fetch Start | ~1,100ms | - | Retry mechanism triggered |
| Events Received | ~15,000ms | ~14s | 121 events from relay |
| Profile Filtering | 16,018ms | ~1s | Reduced to 15 candidates |

**Filtering Statistics:**
- Total events received: 121
- Profiles with invalid/missing images: ~60
- Profiles without bio: ~46
- Final candidates: 15 (12% acceptance rate)

### Phase 4: Profile Preparation (16,018-17,918ms) ⚡
Preparing profiles for display.

| Milestone | Time | Duration | Notes |
|-----------|------|----------|-------|
| Preparation Start | 16,018ms | - | Processing 15 candidates |
| Note Fetching | 16,100ms | ~5s | Verify profiles have posts |
| Image Preloading | 17,000ms | ~1s | Load profile pictures |
| **First Display** | **17,918ms** | - | **2 profiles shown** |

**Preparation Results:**
- Candidates processed: 15
- Successfully prepared: 2 (initially)
- Failed image loads: 6
- No posts found: 2

### Phase 5: Background Loading (17,918-25,420ms)
Continued profile preparation after initial display.

| Milestone | Time | Duration | Notes |
|-----------|------|----------|-------|
| Additional Processing | 17,918ms | 7.5s | Background preparation |
| Final State | 25,420ms | - | 7 profiles ready, 8 failed |

## Performance Issues Identified

### 1. Slow Relay Response (Critical)
- **Issue**: 15 seconds to receive profile data
- **Impact**: Users wait 18 seconds before seeing any content
- **Possible Causes**:
  - Relay timeout set too high (15s)
  - Sequential subscription requests
  - No caching of recent profiles

### 2. High Profile Rejection Rate
- **Issue**: 87% of profiles filtered out
- **Impact**: Need to fetch many profiles to get few usable ones
- **Filtering Reasons**:
  - No profile picture: ~50%
  - No bio text: ~38%
  - Failed image validation: ~25%

### 3. Image Loading Failures
- **Issue**: 50%+ image load failure rate
- **Failed Domains**:
  - gravure.club
  - mr.am
  - media.social.lol
  - hell.twtr.plus
  - pol.social
  - media.misskeyusercontent.com
- **Impact**: Further reduces available profiles

### 4. Small Initial Batch
- **Issue**: Only 2 profiles displayed initially
- **Impact**: Poor user experience, limited content

## Recommendations

### Immediate Optimizations

1. **Reduce Relay Timeout**
   - Current: 15 seconds
   - Recommended: 3-5 seconds
   - Implement progressive loading

2. **Parallel Processing**
   - Fetch from multiple relays simultaneously
   - Process profiles as they arrive
   - Don't wait for all results

3. **Relax Filtering**
   - Allow profiles without bios initially
   - Use placeholder images for failed loads
   - Filter quality in background

4. **Implement Caching**
   - Cache last 50-100 profiles locally
   - Show cached profiles immediately
   - Refresh in background

### Long-term Improvements

1. **Profile Quality Scoring**
   - Score profiles based on completeness
   - Prioritize high-quality profiles
   - Load lower quality as fallback

2. **Predictive Loading**
   - Pre-fetch profiles during idle time
   - Maintain a ready buffer of profiles

3. **CDN for Images**
   - Proxy images through reliable CDN
   - Implement image resizing/optimization
   - Cache processed images

4. **WebSocket Connection Pool**
   - Maintain persistent connections
   - Reduce connection setup time

## Target Performance Goals

| Metric | Current | Target | Improvement |
|--------|---------|--------|-------------|
| Time to First Profile | 18s | <3s | 83% faster |
| Initial Profile Count | 2 | 10+ | 5x more content |
| Profile Acceptance Rate | 13% | 50%+ | Better filtering |
| Image Load Success | 50% | 90%+ | Reliable images |

## Conclusion

The primary issue is the 15-second wait for relay data. By implementing the recommended optimizations, particularly reducing timeouts, parallel processing, and local caching, the app can achieve sub-3-second load times for initial profile display, dramatically improving user experience.