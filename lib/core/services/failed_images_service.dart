import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Service to track image URLs that fail to load
class FailedImagesService {
  static const String _boxName = 'failed_images';
  static const int _maxFailedUrls = 1000; // Limit cache size
  
  Box<String>? _failedImagesBox;
  final Set<String> _failedUrls = {};
  
  FailedImagesService();
  
  /// Initialize the service
  Future<void> init() async {
    try {
      _failedImagesBox = await Hive.openBox<String>(_boxName);
      
      // Load failed URLs from storage
      for (int i = 0; i < _failedImagesBox!.length; i++) {
        final url = _failedImagesBox!.getAt(i);
        if (url != null) {
          _failedUrls.add(url);
        }
      }
      
      if (kDebugMode) {
        print('Loaded ${_failedUrls.length} failed image URLs from storage');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing failed images service: $e');
      }
    }
  }
  
  /// Check if an image URL has failed before
  bool hasImageFailed(String imageUrl) {
    return _failedUrls.contains(imageUrl);
  }
  
  /// Mark an image URL as failed
  Future<void> markImageAsFailed(String imageUrl) async {
    if (_failedUrls.contains(imageUrl)) {
      return; // Already marked
    }
    
    _failedUrls.add(imageUrl);
    
    // Persist to storage
    try {
      if (_failedImagesBox != null) {
        // Clean up if we have too many failed URLs
        if (_failedImagesBox!.length >= _maxFailedUrls) {
          await _failedImagesBox!.clear();
          
          // Re-add the current set (limited to max size)
          final urlsToStore = _failedUrls.toList()
            ..sort() // Sort for consistency
            ..take(_maxFailedUrls);
          
          for (final url in urlsToStore) {
            await _failedImagesBox!.add(url);
          }
        } else {
          await _failedImagesBox!.add(imageUrl);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error persisting failed image URL: $e');
      }
    }
    
    if (kDebugMode) {
      print('Marked image as failed: $imageUrl');
      print('Total failed images: ${_failedUrls.length}');
    }
  }
  
  /// Clear all failed image records
  Future<void> clearAll() async {
    _failedUrls.clear();
    
    try {
      await _failedImagesBox?.clear();
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing failed images: $e');
      }
    }
  }
  
  /// Get count of failed images
  int get failedImageCount => _failedUrls.length;
}