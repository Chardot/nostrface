import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:http/http.dart' as http;

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
    // Check cache first
    if (_imagePreloadCache.containsKey(imageUrl)) {
      return _imagePreloadCache[imageUrl]!;
    }
    
    try {
      // First, try to get it from cache
      final cacheManager = DefaultCacheManager();
      final fileInfo = await cacheManager.getFileFromCache(imageUrl);
      
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
    
    final imageUrl = profile.picture!;
    
    // Check if already preloaded
    if (_imagePreloadCache[imageUrl] == true) {
      return true;
    }
    
    try {
      if (kDebugMode) {
        print('Preloading image for profile ${profile.displayNameOrName}: $imageUrl');
      }
      
      // Download and cache the image
      final cacheManager = DefaultCacheManager();
      
      // First try to download the file
      final file = await cacheManager.downloadFile(imageUrl);
      
      if (file.file.existsSync()) {
        _imagePreloadCache[imageUrl] = true;
        if (kDebugMode) {
          print('Successfully preloaded image for ${profile.displayNameOrName}');
        }
        return true;
      }
      
      _imagePreloadCache[imageUrl] = false;
      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Failed to preload image for ${profile.displayNameOrName}: $e');
      }
      _imagePreloadCache[imageUrl] = false;
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