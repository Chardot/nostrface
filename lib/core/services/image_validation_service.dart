import 'package:flutter/foundation.dart';

/// Service to validate image URLs format (not accessibility)
class ImageValidationService {
  // Cache validation results to avoid repeated checks
  final Map<String, bool> _validationCache = {};
  
  /// Check if an image URL has valid format
  /// This doesn't check if the image is actually accessible,
  /// just that the URL is properly formatted
  bool isValidImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return false;
    }
    
    // Check cache first
    if (_validationCache.containsKey(imageUrl)) {
      return _validationCache[imageUrl]!;
    }
    
    // Check if this is one of the problematic URLs
    final problematicUrls = [
      'https://media.misskeyusercontent.com/io/fbecabe1-d5e5-4c23-af51-74bce7197807.jpg',
      'https://poliverso.org/photo/profile/eventilinux.gif?ts=1665132509',
      'https://s3.solarcom.ch/headeravatarfederati/accounts/avatars/000/000/005/original/75f890c814bfb687.jpg',
    ];
    
    if (problematicUrls.contains(imageUrl)) {
      if (kDebugMode) {
        print('⚠️  Found problematic URL during validation: $imageUrl');
      }
    }
    
    try {
      // Validate URL format
      final uri = Uri.parse(imageUrl);
      
      // Must be http or https
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        _validationCache[imageUrl] = false;
        return false;
      }
      
      // Must have a valid host
      if (!uri.hasAuthority || uri.host.isEmpty) {
        _validationCache[imageUrl] = false;
        return false;
      }
      
      // Accept all properly formatted HTTP/HTTPS URLs
      // Let the image loading widget handle actual loading/errors
      _validationCache[imageUrl] = true;
      return true;
      
    } catch (e) {
      if (kDebugMode) {
        print('Error parsing image URL $imageUrl: $e');
      }
      _validationCache[imageUrl] = false;
      return false;
    }
  }
  
  /// Clear the validation cache
  void clearCache() {
    _validationCache.clear();
  }
}