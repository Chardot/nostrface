import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/indexer_api_service.dart';
import 'package:nostrface/core/services/profile_service_v2.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/services/failed_images_service.dart';
import 'package:nostrface/core/services/profile_readiness_service.dart';

/// Enhanced profile buffer service that uses the indexer API for faster profile discovery
class ProfileBufferServiceIndexed {
  final ProfileServiceV2 _profileService;
  final DiscardedProfilesService? _discardedService;
  final FailedImagesService? _failedImagesService;
  final ProfileReadinessService _readinessService = ProfileReadinessService();
  
  // Configuration
  static const int BUFFER_SIZE = 50;
  static const int REFILL_THRESHOLD = 20;
  static const int INITIAL_LOAD_SIZE = 10;
  
  // Buffers
  final Queue<NostrProfile> _profileBuffer = Queue();
  final Set<String> _seenProfileIds = {};
  final Set<String> _requestedProfileIds = {};
  
  // State
  bool _isFetching = false;
  bool _isInitialLoading = false;
  int _retryCount = 0;
  static const int MAX_RETRIES = 3;
  
  // Track the last viewed index
  int _lastViewedIndex = 0;
  bool _hasInitialized = false;
  
  // Streams
  final StreamController<List<NostrProfile>> _bufferStreamController = 
      StreamController<List<NostrProfile>>.broadcast();
  final StreamController<bool> _loadingStreamController = 
      StreamController<bool>.broadcast();
  
  ProfileBufferServiceIndexed(
    this._profileService, 
    [this._discardedService, this._failedImagesService]
  ) {
    // Start initial load
    if (!_hasInitialized) {
      _loadInitialProfiles();
    }
  }
  
  /// Get the stream of buffered profiles
  Stream<List<NostrProfile>> get profilesStream => _bufferStreamController.stream;
  
  /// Get the loading state stream
  Stream<bool> get loadingStream => _loadingStreamController.stream;
  
  /// Get current buffer as list
  List<NostrProfile> get currentProfiles => _profileBuffer.toList();
  
  /// Check if initial loading is in progress
  bool get isLoadingInitial => _isInitialLoading;
  
  /// Check if buffer has been initialized
  bool get hasLoadedProfiles => _hasInitialized && _profileBuffer.isNotEmpty;
  
  /// Get/set last viewed index
  int get lastViewedIndex => _lastViewedIndex;
  set lastViewedIndex(int index) => _lastViewedIndex = index;
  
  /// Get next profile from buffer
  NostrProfile? getNextProfile() {
    // Trigger background fetch if buffer is running low
    if (_profileBuffer.length < REFILL_THRESHOLD && !_isFetching) {
      _fetchNextBatch();
    }
    
    if (_profileBuffer.isEmpty) {
      return null;
    }
    
    final profile = _profileBuffer.removeFirst();
    _notifyListeners();
    return profile;
  }
  
  /// Peek at next profile without removing it
  NostrProfile? peekNextProfile() {
    return _profileBuffer.isEmpty ? null : _profileBuffer.first;
  }
  
  /// Load initial profiles
  Future<void> _loadInitialProfiles() async {
    if (_isInitialLoading) return;
    
    _isInitialLoading = true;
    _loadingStreamController.add(true);
    
    final startTime = DateTime.now();
    if (kDebugMode) {
      print('[ProfileBuffer] Starting initial profile load...');
    }
    
    try {
      // Fetch initial batch from indexer
      await _fetchNextBatch(isInitial: true);
      
      // Wait a bit for buffer to fill with at least some profiles
      int waitCount = 0;
      while (_profileBuffer.length < INITIAL_LOAD_SIZE && waitCount < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        waitCount++;
      }
      
      _hasInitialized = true;
      
      final loadTime = DateTime.now().difference(startTime).inMilliseconds;
      if (kDebugMode) {
        print('[ProfileBuffer] Initial load complete: ${_profileBuffer.length} profiles in ${loadTime}ms');
      }
      
      // Continue loading more profiles in background
      _ensureBuffer();
      
    } catch (e) {
      if (kDebugMode) {
        print('[ProfileBuffer] Error during initial load: $e');
      }
    } finally {
      _isInitialLoading = false;
      _loadingStreamController.add(false);
      _notifyListeners();
    }
  }
  
  /// Ensure buffer has enough profiles
  Future<void> _ensureBuffer() async {
    if (_profileBuffer.length < REFILL_THRESHOLD && !_isFetching) {
      await _fetchNextBatch();
    }
  }
  
  /// Fetch next batch of profiles
  Future<void> _fetchNextBatch({bool isInitial = false}) async {
    if (_isFetching) return;
    
    _isFetching = true;
    
    try {
      // Get profile references from indexer API
      final profileRefs = await IndexerApiService.getProfileBatch(
        count: isInitial ? INITIAL_LOAD_SIZE * 2 : BUFFER_SIZE,
        excludeIds: _seenProfileIds.toList(),
      );
      
      if (profileRefs.isEmpty) {
        if (kDebugMode) {
          print('[ProfileBuffer] No more profiles available from indexer');
        }
        _retryCount = 0;
        return;
      }
      
      if (kDebugMode) {
        print('[ProfileBuffer] Got ${profileRefs.length} profile references from indexer');
      }
      
      // Mark these profiles as requested
      for (final ref in profileRefs) {
        _requestedProfileIds.add(ref.pubkey);
      }
      
      // Fetch full profiles from relays in parallel
      await _fetchProfilesFromRelays(profileRefs);
      
      // Reset retry count on success
      _retryCount = 0;
      
      // Continue fetching if buffer still needs more
      if (_profileBuffer.length < REFILL_THRESHOLD) {
        // Small delay to avoid hammering the API
        await Future.delayed(const Duration(seconds: 1));
        _fetchNextBatch();
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('[ProfileBuffer] Error fetching batch: $e');
      }
      
      // Implement retry logic
      _retryCount++;
      if (_retryCount < MAX_RETRIES) {
        if (kDebugMode) {
          print('[ProfileBuffer] Retrying (${_retryCount}/$MAX_RETRIES)...');
        }
        await Future.delayed(Duration(seconds: _retryCount * 2));
        _fetchNextBatch(isInitial: isInitial);
      } else {
        if (kDebugMode) {
          print('[ProfileBuffer] Max retries reached. Falling back to direct relay fetch.');
        }
        // Fallback to direct relay fetching
        await _fallbackToDirectRelayFetch();
        _retryCount = 0;
      }
    } finally {
      _isFetching = false;
    }
  }
  
  /// Fetch profiles from relays based on references
  Future<void> _fetchProfilesFromRelays(List<ProfileReference> profileRefs) async {
    if (kDebugMode) {
      print('[ProfileBuffer] Fetching ${profileRefs.length} profiles from relays...');
    }
    
    // Process in smaller batches for better performance
    const batchSize = 5;
    
    for (int i = 0; i < profileRefs.length; i += batchSize) {
      final end = (i + batchSize < profileRefs.length) ? i + batchSize : profileRefs.length;
      final batch = profileRefs.sublist(i, end);
      
      // Fetch profiles in parallel
      final futures = batch.map((ref) async {
        try {
          // Check if already seen or discarded
          if (_seenProfileIds.contains(ref.pubkey)) {
            return null;
          }
          
          if (_discardedService != null && _discardedService.isDiscarded(ref.pubkey)) {
            _seenProfileIds.add(ref.pubkey);
            return null;
          }
          
          // Fetch profile from relays (with relay hints from indexer)
          final profile = await _profileService.fetchProfile(ref.pubkey).timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          );
          
          if (profile == null) {
            return null;
          }
          
          // Validate profile
          if (!_isValidProfile(profile)) {
            if (kDebugMode) {
              print('[ProfileBuffer] Invalid profile ${profile.pubkey}: picture=${profile.picture}, name=${profile.name}, displayName=${profile.displayName}, about=${profile.about?.substring(0, 50) ?? "null"}');
              // Special check for the problematic profile
              if (profile.pubkey == '515b9246a72a47188ac60b7c4203f127accf210af53cc5db668c9ec6d2005497') {
                print('[ProfileBuffer] SPECIAL CHECK - Profile 129aefr... has picture URL: ${profile.picture}');
              }
            }
            return null;
          }
          
          // Check if profile is followed
          if (_profileService.isProfileFollowed(profile.pubkey)) {
            _seenProfileIds.add(profile.pubkey);
            return null;
          }
          
          // Check for failed images
          if (_failedImagesService != null && 
              profile.picture != null &&
              _failedImagesService.hasImageFailed(profile.picture!)) {
            _seenProfileIds.add(profile.pubkey);
            return null;
          }
          
          return profile;
        } catch (e) {
          if (kDebugMode) {
            print('[ProfileBuffer] Failed to fetch profile ${ref.pubkey}: $e');
          }
          return null;
        }
      });
      
      final results = await Future.wait(futures);
      final validProfiles = results.where((p) => p != null).cast<NostrProfile>().toList();
      
      if (validProfiles.isNotEmpty) {
        // Preload images for valid profiles before adding to buffer
        final preloadedProfiles = <NostrProfile>[];
        
        for (final profile in validProfiles) {
          // Try to preload the image
          bool imageReady = false;
          if (profile.picture != null) {
            imageReady = await _readinessService.preloadProfileImage(profile);
            
            if (!imageReady && kDebugMode) {
              print('[ProfileBuffer] Failed to preload image for ${profile.displayNameOrName}, skipping profile');
            }
          }
          
          // Only add profiles with successfully preloaded images
          if (imageReady) {
            preloadedProfiles.add(profile);
            _seenProfileIds.add(profile.pubkey);
          } else {
            // Mark as seen so we don't try again
            _seenProfileIds.add(profile.pubkey);
            
            // Also mark the image as failed if it exists
            if (profile.picture != null && _failedImagesService != null) {
              await _failedImagesService.markImageAsFailed(profile.picture!);
            }
          }
        }
        
        // Add preloaded profiles to buffer
        if (preloadedProfiles.isNotEmpty) {
          for (final profile in preloadedProfiles) {
            _profileBuffer.add(profile);
          }
          
          if (kDebugMode) {
            print('[ProfileBuffer] Added ${preloadedProfiles.length} profiles (out of ${validProfiles.length}) to buffer. Total: ${_profileBuffer.length}');
          }
          
          _notifyListeners();
        }
      }
      
      // Small delay between batches
      if (i + batchSize < profileRefs.length) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
  }
  
  /// Fallback to direct relay fetching when indexer is unavailable
  Future<void> _fallbackToDirectRelayFetch() async {
    if (kDebugMode) {
      print('[ProfileBuffer] Falling back to direct relay fetch...');
    }
    
    try {
      // Use the existing discover profiles method
      final profiles = await _profileService.discoverProfiles(limit: 20);
      
      for (final profile in profiles) {
        if (!_seenProfileIds.contains(profile.pubkey) &&
            !_profileService.isProfileFollowed(profile.pubkey) &&
            (_discardedService == null || !_discardedService.isDiscarded(profile.pubkey))) {
          
          // Preload image before adding to buffer
          bool imageReady = false;
          if (profile.picture != null) {
            imageReady = await _readinessService.preloadProfileImage(profile);
          }
          
          if (imageReady) {
            _profileBuffer.add(profile);
            _seenProfileIds.add(profile.pubkey);
          } else {
            _seenProfileIds.add(profile.pubkey);
            if (profile.picture != null && _failedImagesService != null) {
              await _failedImagesService.markImageAsFailed(profile.picture!);
            }
          }
        }
      }
      
      if (profiles.isNotEmpty) {
        _notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ProfileBuffer] Fallback fetch failed: $e');
      }
    }
  }
  
  /// Validate profile has required information
  bool _isValidProfile(NostrProfile profile) {
    // Must have a picture
    if (profile.picture == null || profile.picture!.isEmpty) {
      return false;
    }
    
    // Must have a name (not starting with npub)
    final hasValidName = (profile.name != null && 
                         profile.name!.trim().isNotEmpty && 
                         !profile.name!.startsWith('npub')) ||
                        (profile.displayName != null && 
                         profile.displayName!.trim().isNotEmpty && 
                         !profile.displayName!.startsWith('npub'));
    
    if (!hasValidName) {
      return false;
    }
    
    // Must have a bio
    if (profile.about == null || profile.about!.trim().isEmpty) {
      return false;
    }
    
    return true;
  }
  
  /// Report user interaction to indexer
  void reportInteraction(String pubkey, String action) {
    // Fire and forget - don't await
    IndexerApiService.reportInteraction(
      pubkey: pubkey,
      action: action,
    );
  }
  
  /// Refresh buffer with new profiles
  Future<void> refreshBuffer() async {
    if (kDebugMode) {
      print('[ProfileBuffer] Refreshing buffer...');
    }
    
    // Clear current buffer but keep seen IDs
    _profileBuffer.clear();
    _notifyListeners();
    
    // Fetch new profiles
    await _fetchNextBatch();
  }
  
  /// Notify listeners of buffer changes
  void _notifyListeners() {
    _bufferStreamController.add(currentProfiles);
  }
  
  /// Dispose resources
  void dispose() {
    _bufferStreamController.close();
    _loadingStreamController.close();
  }
}