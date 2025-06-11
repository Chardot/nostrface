import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:http/http.dart' as http;
import 'package:nostrface/core/utils/cors_helper.dart';

/// Service to check if profiles are ready for presentation
class ProfileReadinessService {
  // Cache for image preload status
  final Map<String, bool> _imagePreloadCache = {};
  
  // Cache for user post counts
  final Map<String, int> _postCountCache = {};
  
  /// Check if a profile is ready for presentation
  Future<bool> isProfileReady(NostrProfile profile, {int? postCount}) async {
    // Check basic requirements
    if (!_hasBasicRequirements(profile)) {
      return false;
    }
    
    // Check if user has posts
    if (postCount != null) {
      _postCountCache[profile.pubkey] = postCount;
    }
    
    final userPostCount = _postCountCache[profile.pubkey] ?? postCount ?? 0;
    if (userPostCount == 0) {
      if (kDebugMode) {
        print('Profile ${profile.displayNameOrName} has no posts, not ready for presentation');
      }
      return false;
    }
    
    // Check if image is preloaded
    if (profile.picture != null) {
      return await _isImagePreloaded(profile.picture!);
    }
    
    return true;
  }
  
  /// Check if profile has basic requirements
  bool _hasBasicRequirements(NostrProfile profile) {
    // Must have name/username
    final hasName = profile.name != null && 
                   profile.name!.trim().isNotEmpty && 
                   !profile.name!.startsWith('npub');
    
    final hasDisplayName = profile.displayName != null && 
                          profile.displayName!.trim().isNotEmpty &&
                          !profile.displayName!.startsWith('npub');
    
    if (!hasName && !hasDisplayName) {
      return false;
    }
    
    // Must have bio
    final hasBio = profile.about != null && profile.about!.trim().isNotEmpty;
    if (!hasBio) {
      return false;
    }
    
    // Must have valid picture URL
    if (profile.picture == null || profile.picture!.isEmpty) {
      return false;
    }
    
    return true;
  }
  
  /// Check if an image is preloaded and ready
  Future<bool> _isImagePreloaded(String imageUrl) async {
    // Check cache first (using original URL)
    if (_imagePreloadCache.containsKey(imageUrl)) {
      return _imagePreloadCache[imageUrl]!;
    }
    
    try {
      // First, try to get it from cache (check both original and CORS-wrapped URLs)
      final cacheManager = DefaultCacheManager();
      final corsUrl = CorsHelper.wrapWithCorsProxy(imageUrl);
      
      // Check original URL first
      var fileInfo = await cacheManager.getFileFromCache(imageUrl);
      
      // If not found and CORS proxy is needed, check CORS URL
      if (fileInfo == null && corsUrl != imageUrl) {
        fileInfo = await cacheManager.getFileFromCache(corsUrl);
      }
      
      if (fileInfo != null && fileInfo.file.existsSync()) {
        _imagePreloadCache[imageUrl] = true;
        return true;
      }
      
      // Not in cache, need to download it
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking image cache for $imageUrl: $e');
      }
      return false;
    }
  }
  
  /// Preload a profile's image
  Future<bool> preloadProfileImage(NostrProfile profile) async {
    if (profile.picture == null || profile.picture!.isEmpty) {
      return false;
    }
    
    // Use the original URL for cache key, but download with CORS proxy if needed
    final originalUrl = profile.picture!;
    final downloadUrl = CorsHelper.wrapWithCorsProxy(originalUrl);
    
    // Check if already preloaded (using original URL as key)
    if (_imagePreloadCache[originalUrl] == true) {
      return true;
    }
    
    try {
      if (kDebugMode) {
        print('[ProfileReadiness] Preloading image for ${profile.displayNameOrName}: $originalUrl');
        if (downloadUrl != originalUrl) {
          print('[ProfileReadiness] Using CORS proxy: $downloadUrl');
        }
      }
      
      // Download and cache the image
      final cacheManager = DefaultCacheManager();
      
      // Try to download the file with appropriate headers
      final file = await cacheManager.downloadFile(
        downloadUrl,
        authHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
          'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      );
      
      if (file.file.existsSync()) {
        _imagePreloadCache[originalUrl] = true;
        if (kDebugMode) {
          print('[ProfileReadiness] ✅ Successfully preloaded image for ${profile.displayNameOrName}');
        }
        return true;
      }
      
      _imagePreloadCache[originalUrl] = false;
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('[ProfileReadiness] ❌ Failed to preload image for ${profile.displayNameOrName}: $e');
      }
      _imagePreloadCache[originalUrl] = false;
      return false;
    }
  }
  
  /// Clear the preload cache
  void clearCache() {
    _imagePreloadCache.clear();
    _postCountCache.clear();
  }
  
  /// Mark an image as failed
  void markImageAsFailed(String imageUrl) {
    _imagePreloadCache[imageUrl] = false;
  }
  
  /// Update post count for a profile
  void updatePostCount(String pubkey, int count) {
    _postCountCache[pubkey] = count;
  }
}