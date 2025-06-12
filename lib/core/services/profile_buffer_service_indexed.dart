import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/profile_service_v2.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/services/failed_images_service.dart';
import 'package:nostrface/core/services/profile_readiness_service.dart';
import 'package:nostrface/core/services/nostr_band_api_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/providers/app_providers.dart';

/// Enhanced profile buffer service that uses the indexer API for faster profile discovery
class ProfileBufferServiceIndexed {
  final ProfileServiceV2 _profileService;
  final DiscardedProfilesService? _discardedService;
  final FailedImagesService? _failedImagesService;
  final ProfileReadinessService _readinessService = ProfileReadinessService();
  final Ref? _ref;
  
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
    [this._discardedService, this._failedImagesService, this._ref]
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
      // Fetch trending profiles from nostr.band
      final trendingProfiles = await NostrBandApiService.getTrendingProfiles(
        count: isInitial ? INITIAL_LOAD_SIZE * 2 : BUFFER_SIZE,
      );
      if (trendingProfiles.isEmpty) {
        if (kDebugMode) {
          print('[ProfileBuffer] No trending profiles available from nostr.band');
        }
        _retryCount = 0;
        return;
      }
      if (kDebugMode) {
        print('[ProfileBuffer] Got ${trendingProfiles.length} trending profiles from nostr.band');
      }
      // Filter out already seen, followed, or discarded profiles
      final newProfiles = trendingProfiles.where((profile) =>
        !_seenProfileIds.contains(profile.pubkey) &&
        !_profileService.isProfileFollowed(profile.pubkey) &&
        (_discardedService == null || !_discardedService.isDiscarded(profile.pubkey))
      ).toList();
      // Preload images and validate
      final preloadedProfiles = <NostrProfile>[];
      for (final profile in newProfiles) {
        bool imageReady = false;
        if (profile.picture != null) {
          imageReady = await _readinessService.preloadProfileImage(profile);
        }
        if (imageReady) {
          preloadedProfiles.add(profile);
          _seenProfileIds.add(profile.pubkey);
        } else {
          _seenProfileIds.add(profile.pubkey);
          if (profile.picture != null && _failedImagesService != null) {
            await _failedImagesService.markImageAsFailed(profile.picture!);
          }
        }
      }
      if (preloadedProfiles.isNotEmpty) {
        for (final profile in preloadedProfiles) {
          _profileBuffer.add(profile);
        }
        // Insert into trending profile cache if ref is available
        if (_ref != null) {
          final cache = Map<String, NostrProfile>.from(_ref!.read(trendingProfileCacheProvider));
          for (final profile in preloadedProfiles) {
            cache[profile.pubkey] = profile;
          }
          _ref!.read(trendingProfileCacheProvider.notifier).state = cache;
        }
        if (kDebugMode) {
          print('[ProfileBuffer] Added ${preloadedProfiles.length} trending profiles to buffer. Total: ${_profileBuffer.length}');
        }
        _notifyListeners();
      }
      _retryCount = 0;
      if (_profileBuffer.length < REFILL_THRESHOLD) {
        await Future.delayed(const Duration(seconds: 1));
        _fetchNextBatch();
      }
    } catch (e) {
      if (kDebugMode) {
        print('[ProfileBuffer] Error fetching trending profiles: $e');
      }
      _retryCount++;
      if (_retryCount < MAX_RETRIES) {
        if (kDebugMode) {
          print('[ProfileBuffer] Retrying trending fetch (${_retryCount}/$MAX_RETRIES)...');
        }
        await Future.delayed(Duration(seconds: _retryCount * 2));
        _fetchNextBatch(isInitial: isInitial);
      } else {
        if (kDebugMode) {
          print('[ProfileBuffer] Max retries reached. No more trending profiles.');
        }
        _retryCount = 0;
      }
    } finally {
      _isFetching = false;
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

  void reportInteraction(String pubkey, String action) {
    // No-op: nostr.band does not support reporting interactions
  }
}