import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/nostr_relay_service.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/services/note_cache_service.dart';
import 'package:nostrface/core/services/image_validation_service.dart';
import 'package:nostrface/core/services/failed_images_service.dart';
import 'package:nostrface/core/services/profile_readiness_service.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:nostr/nostr.dart' as nostr;
import 'package:nostrface/core/models/relay_publish_result.dart';

/// Service for managing Nostr profile data
class ProfileService {
  final List<String> _relayUrls;
  final List<NostrRelayService> _relayServices = [];
  final Map<String, NostrProfile> _profiles = {};
  final StreamController<NostrProfile> _profileStreamController = StreamController<NostrProfile>.broadcast();
  final Set<String> _followedProfiles = {};
  final StreamController<Set<String>> _followedProfilesStreamController = StreamController<Set<String>>.broadcast(
    onListen: () => print('[Stream] First listener subscribed to followedProfilesStream'),
    onCancel: () => print('[Stream] Last listener unsubscribed from followedProfilesStream'),
  );
  
  // Cache service for notes
  final NoteCacheService _noteCacheService = NoteCacheService();
  
  // Image validation service
  final ImageValidationService _imageValidationService = ImageValidationService();
  
  
  ProfileService(this._relayUrls) {
    _initializeRelays();
    _loadFollowedProfiles();
    _preOpenFollowedBox(); // Pre-open the box to avoid delays
  }
  
  /// Pre-open the followed profiles box to avoid delays on first follow
  Future<void> _preOpenFollowedBox() async {
    try {
      print('[ProfileService] Pre-opening followed_profiles box...');
      final box = await Hive.openBox<String>('followed_profiles');
      print('[ProfileService] Followed profiles box pre-opened successfully');
      // Keep the box open for faster access
    } catch (e) {
      print('[ProfileService] Error pre-opening followed profiles box: $e');
    }
  }
  
  
  Stream<NostrProfile> get profileStream => _profileStreamController.stream;
  Set<String> get followedProfiles => _followedProfiles;
  Stream<Set<String>> get followedProfilesStream => _followedProfilesStreamController.stream;
  
  /// Get the relay URLs for connecting to Nostr network
  List<String> get relayUrls => List.unmodifiable(_relayUrls);
  
  
  /// Initialize relay connections from a list of URLs
  Future<void> _initializeRelaysFromUrls(List<String> urls) async {
    
    // In web, we'll try to connect to all relays, but use a timeout to avoid waiting too long
    final connectFutures = urls.map((relayUrl) async {
      try {
        
        final relay = NostrRelayService(relayUrl);
        final connected = await relay.connect().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            if (kDebugMode) {
              print('Connection timeout for relay: $relayUrl');
            }
            return false;
          },
        );
        
        if (connected) {
          
          _relayServices.add(relay);
          
          // Subscribe to profile updates
          relay.eventStream.listen((event) {
            if (event.kind == NostrEvent.metadataKind) {
              _handleProfileMetadata(event);
            }
          });
          
          return true;
        }
        
        return false;
      } catch (e) {
        if (kDebugMode) {
          print('Failed to connect to relay $relayUrl: $e');
        }
        return false;
      }
    }).toList();
    
    // Wait for all connection attempts to complete, but with overall timeout
    final results = await Future.wait(
      connectFutures,
      eagerError: false,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        if (kDebugMode) {
          print('Relay initialization timeout reached, proceeding with available connections');
        }
        return List<bool>.filled(connectFutures.length, false);
      },
    );
    
    final connectedCount = results.where((result) => result).length;
    if (kDebugMode && connectedCount < urls.length) {
      print('[ProfileService] Connected to $connectedCount/${urls.length} relays');
    }
  }
  
  /// Initialize connections to relays
  Future<void> _initializeRelays() async {
    await _initializeRelaysFromUrls(_relayUrls);
  }
  
  /// Handle a profile metadata event (Kind 0)
  void _handleProfileMetadata(NostrEvent event) {
    try {
      // Try to sanitize the content if needed
      String content = event.content;
      
      try {
        // Check if the content is valid JSON
        final contentMap = jsonDecode(content);
        
        // Sanitize profile data
        bool needsSanitizing = false;
        
        // Check if name contains invalid UTF-8
        if (contentMap['name'] is String) {
          final name = contentMap['name'] as String;
          if (name.contains('\u{FFFD}')) {
            contentMap['name'] = _sanitizeString(name);
            needsSanitizing = true;
          }
        }
        
        // Check if about contains invalid UTF-8
        if (contentMap['about'] is String) {
          final about = contentMap['about'] as String;
          if (about.contains('\u{FFFD}')) {
            contentMap['about'] = _sanitizeString(about);
            needsSanitizing = true;
          }
        }
        
        // Re-encode the sanitized content if needed
        if (needsSanitizing) {
          content = jsonEncode(contentMap);
        }
      } catch (e) {
        // If it's not valid JSON or has other issues, continue with original content
        if (kDebugMode) {
          print('Error sanitizing profile content: $e');
        }
      }
      
      // Create profile
      final profile = NostrProfile.fromMetadataEvent(event.pubkey, content);
      _profiles[event.pubkey] = profile;
      _profileStreamController.add(profile);
    } catch (e) {
      if (kDebugMode) {
        print('Error handling profile metadata: $e');
      }
    }
  }
  
  /// Sanitize a string by removing invalid UTF-8 characters
  String _sanitizeString(String input) {
    // Replace the Unicode replacement character with empty string
    String sanitized = input.replaceAll('\u{FFFD}', '');
    
    // Replace any other problematic characters
    sanitized = sanitized.replaceAll(RegExp(r'[\u{D800}-\u{DFFF}]'), '');
    
    // Remove any zero-width characters
    sanitized = sanitized.replaceAll(RegExp(r'[\u{200B}-\u{200D}\u{FEFF}]'), '');
    
    return sanitized;
  }
  
  /// Get a profile by public key
  Future<NostrProfile?> getProfile(String pubkey) async {
    // Check if we already have this profile cached
    if (_profiles.containsKey(pubkey)) {
      return _profiles[pubkey];
    }
    
    // Check local storage first
    try {
      final profileBox = await Hive.openBox<String>('profiles');
      final profileJson = profileBox.get(pubkey);
      
      if (profileJson != null) {
        final Map<String, dynamic> data = jsonDecode(profileJson);
        final NostrProfile profile = NostrProfile.fromJson(data);
        _profiles[pubkey] = profile;
        return profile;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading profile from storage: $e');
      }
    }
    
    // Not found locally, fetch from relays
    return await fetchProfile(pubkey);
  }
  
  /// Fetch a profile from relays by public key
  Future<NostrProfile?> fetchProfile(String pubkey) async {
    NostrProfile? latestProfile;
    
    // Build a filter for Kind 0 events from this user
    final filter = {
      'authors': [pubkey],
      'kinds': [NostrEvent.metadataKind],
      'limit': 1,
    };
    
    // Query multiple relays in parallel
    List<Future<List<NostrEvent>>> queries = [];
    for (final relay in _relayServices) {
      if (relay.isConnected) {
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 5)));
      }
    }
    
    final results = await Future.wait(queries);
    
    // Process the results
    for (final events in results) {
      for (final event in events) {
        if (event.kind == NostrEvent.metadataKind) {
          try {
            final profile = NostrProfile.fromMetadataEvent(event.pubkey, event.content);
            
            if (latestProfile == null) {
              latestProfile = profile;
            } else {
              // In a real app, you would compare timestamps and take the most recent
              latestProfile = latestProfile.merge(profile);
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error parsing profile: $e');
            }
          }
        }
      }
    }
    
    if (latestProfile != null) {
      // Save to cache and storage
      _profiles[pubkey] = latestProfile;
      
      try {
        final profileBox = await Hive.openBox<String>('profiles');
        await profileBox.put(pubkey, jsonEncode(latestProfile.toJson()));
      } catch (e) {
        if (kDebugMode) {
          print('Error saving profile to storage: $e');
        }
      }
      
      _profileStreamController.add(latestProfile);
    }
    
    return latestProfile;
  }
  
  /// Fetch multiple profiles by public keys
  Future<List<NostrProfile>> fetchProfiles(List<String> pubkeys) async {
    List<NostrProfile> results = [];
    
    // Fetch profiles in parallel batches
    final batch = 10;
    for (int i = 0; i < pubkeys.length; i += batch) {
      final end = (i + batch < pubkeys.length) ? i + batch : pubkeys.length;
      final batchKeys = pubkeys.sublist(i, end);
      
      await Future.wait(
        batchKeys.map((pubkey) async {
          final profile = await getProfile(pubkey);
          if (profile != null) {
            results.add(profile);
          }
        }),
      );
    }
    
    return results;
  }
  
  /// Discover random profiles from the relays
  Future<List<NostrProfile>> discoverProfiles({int limit = 10, DiscardedProfilesService? discardedService, FailedImagesService? failedImagesService, bool checkPosts = false}) async {
    // Increase the initial limit to account for filtering
    final initialLimit = limit * 3;
    
    List<NostrProfile> candidateProfiles = [];
    Set<String> seenPubkeys = {};
    
    // If we have no active relay connections, attempt to reconnect
    if (_relayServices.isEmpty) {
      await _initializeRelays();
      
      // If still no relays, try to use cached profiles
      if (_relayServices.isEmpty) {
        if (kDebugMode) {
          print('No relay connections available, using cached profiles if available');
        }
        
        try {
          final profileBox = await Hive.openBox<String>('profiles');
          if (profileBox.isNotEmpty) {
            // Get random cached profiles
            final cachedKeys = profileBox.keys.toList()..shuffle();
            final keysToUse = cachedKeys.take(initialLimit).toList();
            
            for (final key in keysToUse) {
              final profileJson = profileBox.get(key.toString());
              if (profileJson != null) {
                try {
                  final profile = NostrProfile.fromJson(jsonDecode(profileJson));
                  
                  // Only consider profiles with valid pictures, name/display name, and bio
                  if (_isValidProfilePicture(profile.picture) && _hasRequiredProfileInfo(profile)) {
                    // Check if profile is followed
                    if (!_followedProfiles.contains(profile.pubkey)) {
                      // Check if profile is discarded
                      if (discardedService == null || !discardedService.isDiscarded(profile.pubkey)) {
                        // Check if image has failed before
                        if (failedImagesService == null || !failedImagesService.hasImageFailed(profile.picture!)) {
                          candidateProfiles.add(profile);
                        }
                      }
                    }
                  }
                } catch (e) {
                  if (kDebugMode) {
                    print('Error parsing cached profile: $e');
                  }
                }
              }
            }
            
            // Return cached profiles without trust filtering
            if (candidateProfiles.isNotEmpty) {
              if (kDebugMode) {
                print('Returning ${candidateProfiles.length} cached profiles');
              }
              return candidateProfiles.take(limit).toList();
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error accessing profile cache: $e');
          }
        }
      }
    }
    
    // Build a filter for Kind 0 (metadata) events
    final filter = {
      'kinds': [NostrEvent.metadataKind],
      'limit': initialLimit, // Ask for more than we need for filtering
    };
    
    // Query multiple relays in parallel with increased timeout
    List<Future<List<NostrEvent>>> queries = [];
    for (final relay in _relayServices) {
      if (relay.isConnected) {
        // Don't log each relay query - too noisy
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 15)));
      }
    }
    
    // Handle empty queries case
    if (queries.isEmpty) {
      return [];
    }
    
    // Use Future.wait with a timeout so one slow relay doesn't block everything
    List<List<NostrEvent>> results = [];
    try {
      results = await Future.wait(
        queries,
        eagerError: false, // Continue even if some futures fail
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          if (kDebugMode) {
            print('Query timeout reached, processing available results');
          }
          // Just return an empty list on timeout
          return <List<NostrEvent>>[];
        },
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching profiles: $e');
      }
      // Return empty results on error
      results = <List<NostrEvent>>[];
    }
    
    if (kDebugMode) {
      print('Got results from ${results.length} relays');
    }
    
    // Process the results to build candidate profiles
    for (final events in results) {
      for (final event in events) {
        if (event.kind == NostrEvent.metadataKind && !seenPubkeys.contains(event.pubkey)) {
          try {
            // Try to sanitize the content before parsing
            String content = event.content;
            
            try {
              // Check if the content contains invalid UTF-8
              if (content.contains('\u{FFFD}')) {
                final contentMap = jsonDecode(content);
                bool needsSanitizing = false;
                
                // Sanitize name
                if (contentMap['name'] is String) {
                  final name = contentMap['name'] as String;
                  if (name.contains('\u{FFFD}')) {
                    contentMap['name'] = _sanitizeString(name);
                    needsSanitizing = true;
                  }
                }
                
                // Sanitize about
                if (contentMap['about'] is String) {
                  final about = contentMap['about'] as String;
                  if (about.contains('\u{FFFD}')) {
                    contentMap['about'] = _sanitizeString(about);
                    needsSanitizing = true;
                  }
                }
                
                if (needsSanitizing) {
                  content = jsonEncode(contentMap);
                }
              }
            } catch (e) {
              // If sanitization fails, continue with original content
              if (kDebugMode) {
                print('Error sanitizing profile content during discovery: $e');
              }
            }
            
            final profile = NostrProfile.fromMetadataEvent(event.pubkey, content);
            
            // Debug specific profile
            if (profile.pubkey == 'f68e1aafc674201c8482f5081285e289252389e5f24a9f0f8c2c4965ee25e87a3') {
              if (kDebugMode) {
                print('Kevin Beaumont profile found:');
                print('  Raw content: $content');
                print('  Picture URL: ${profile.picture}');
                print('  Name: ${profile.name}');
                print('  DisplayName: ${profile.displayName}');
                print('  About: ${profile.about}');
                print('  Valid picture: ${_isValidProfilePicture(profile.picture)}');
                print('  Has required info: ${_hasRequiredProfileInfo(profile)}');
              }
            }
            
            // Only add profiles with valid pictures, name/display name, and bio
            final validPicture = _isValidProfilePicture(profile.picture);
            final hasRequiredInfo = _hasRequiredProfileInfo(profile);
            
            if (validPicture && hasRequiredInfo) {
              // Check if profile is followed
              if (!_followedProfiles.contains(profile.pubkey)) {
                // Check if profile is discarded
                if (discardedService == null || !discardedService.isDiscarded(profile.pubkey)) {
                  // Check if image has failed before
                  if (failedImagesService == null || !failedImagesService.hasImageFailed(profile.picture!)) {
                    candidateProfiles.add(profile);
                    seenPubkeys.add(profile.pubkey);
                    
                    // Cache the profile
                    _profiles[profile.pubkey] = profile;
                    
                      // Save to storage asynchronously
                    _saveProfileToStorage(profile).catchError((e) {
                      if (kDebugMode) {
                        print('Error saving profile to storage: $e');
                      }
                    });
                    
                    // We need to get enough candidates for filtering
                    if (candidateProfiles.length >= initialLimit) {
                      break;
                    }
                  }
                }
              }
            } else {
              if (kDebugMode) {
                if (!validPicture) {
                  print('Filtered out profile ${profile.pubkey.substring(0, 8)} with invalid picture URL: ${profile.picture}');
                  
                  // Check if this is one of the problematic URLs the user mentioned
                  final problematicUrls = [
                    'https://media.misskeyusercontent.com/io/fbecabe1-d5e5-4c23-af51-74bce7197807.jpg',
                    'https://poliverso.org/photo/profile/eventilinux.gif?ts=1665132509',
                    'https://s3.solarcom.ch/headeravatarfederati/accounts/avatars/000/000/005/original/75f890c814bfb687.jpg',
                  ];
                  
                  if (profile.picture != null && problematicUrls.contains(profile.picture)) {
                    print('  ⚠️  This is one of the problematic URLs reported by user!');
                  }
                } else if (!hasRequiredInfo) {
                  final hasName = (profile.name != null && profile.name!.trim().isNotEmpty && !profile.name!.startsWith('npub')) ||
                                 (profile.displayName != null && profile.displayName!.trim().isNotEmpty && !profile.displayName!.startsWith('npub'));
                  final hasBio = profile.about != null && profile.about!.trim().isNotEmpty;
                  print('Filtered out profile ${profile.pubkey.substring(0, 8)} - Has name: $hasName, Has bio: $hasBio');
                }
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error parsing profile: $e');
            }
          }
        }
      }
      
      if (candidateProfiles.length >= initialLimit) {
        break;
      }
    }
    
    if (candidateProfiles.isEmpty) {
      if (kDebugMode) {
        print('No candidate profiles found');
      }
      return [];
    }
    
    if (kDebugMode) {
      print('Found ${candidateProfiles.length} candidate profiles');
    }
    
    // If checkPosts is enabled, filter profiles with posts in parallel
    if (checkPosts && candidateProfiles.isNotEmpty) {
      if (kDebugMode) {
        print('Checking which profiles have posts...');
      }
      
      // Check posts for candidates in batches
      final profilesWithPosts = <NostrProfile>[];
      const batchSize = 5;
      
      for (int i = 0; i < candidateProfiles.length && profilesWithPosts.length < limit; i += batchSize) {
        final end = (i + batchSize < candidateProfiles.length) ? i + batchSize : candidateProfiles.length;
        final batch = candidateProfiles.sublist(i, end);
        
        final results = await Future.wait(
          batch.map((profile) async {
            try {
              final notes = await getUserNotes(profile.pubkey, limit: 1);
              return (profile, notes.isNotEmpty);
            } catch (e) {
              return (profile, false);
            }
          }),
        );
        
        for (final (profile, hasPosts) in results) {
          if (hasPosts) {
            profilesWithPosts.add(profile);
            if (profilesWithPosts.length >= limit) break;
          } else if (kDebugMode) {
            print('Filtered out ${profile.displayNameOrName} - no posts');
          }
        }
      }
      
      return profilesWithPosts;
    }
    
    // Return profiles without post filtering
    return candidateProfiles.take(limit).toList();
  }
  
  /// Save a profile to storage asynchronously
  Future<void> _saveProfileToStorage(NostrProfile profile) async {
    try {
      final profileBox = await Hive.openBox<String>('profiles');
      await profileBox.put(profile.pubkey, jsonEncode(profile.toJson()));
    } catch (e) {
      if (kDebugMode) {
        print('Error saving profile to storage: $e');
      }
      rethrow;
    }
  }
  
  /// Fetch recent text notes from a specific user with optimizations
  Future<List<NostrEvent>> getUserNotes(String pubkey, {int limit = 10}) async {
    if (kDebugMode) {
      print('Fetching notes for user: $pubkey, limit: $limit');
    }
    
    // Check cache first
    final cachedNotes = await _noteCacheService.getCachedNotes(pubkey);
    if (cachedNotes != null && cachedNotes.length >= limit) {
      if (kDebugMode) {
        print('Returning ${cachedNotes.length} cached notes for user: $pubkey');
      }
      return cachedNotes.take(limit).toList();
    }
    
    // Get only connected relays (don't wait for initialization)
    final connectedRelays = _relayServices.where((relay) => relay.isConnected).toList();
    
    // If no relays connected, try to use cache even if incomplete
    if (connectedRelays.isEmpty) {
      if (kDebugMode) {
        print('No connected relays, using cached notes if available');
      }
      
      // Try to connect to relays asynchronously for next time
      _initializeRelays();
      
      return cachedNotes ?? [];
    }
    
    // Build a filter for Kind 1 (text notes) events from this user
    final filter = {
      'authors': [pubkey],
      'kinds': [NostrEvent.textNoteKind],
      'limit': limit * 2, // Request more to ensure we get enough after deduplication
    };
    
    // Use a completer for early return when we have enough notes
    final completer = Completer<List<NostrEvent>>();
    final Map<String, NostrEvent> uniqueEvents = {};
    int completedQueries = 0;
    
    // Create a timer for maximum wait time (1.5 seconds instead of 5)
    final maxWaitTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!completer.isCompleted) {
        final sortedEvents = _sortAndLimitEvents(uniqueEvents, limit);
        completer.complete(sortedEvents);
      }
    });
    
    // Query relays with shorter timeout and early return logic
    for (final relay in connectedRelays) {
      relay.subscribe(filter, timeout: const Duration(milliseconds: 1000)).then((events) {
        if (!completer.isCompleted) {
          // Add events to unique collection
          for (final event in events) {
            if (!uniqueEvents.containsKey(event.id) || 
                uniqueEvents[event.id]!.created_at < event.created_at) {
              uniqueEvents[event.id] = event;
            }
          }
          
          completedQueries++;
          
          // Check if we have enough notes or all queries completed
          if (uniqueEvents.length >= limit || completedQueries >= connectedRelays.length) {
            maxWaitTimer.cancel();
            if (!completer.isCompleted) {
              final sortedEvents = _sortAndLimitEvents(uniqueEvents, limit);
              completer.complete(sortedEvents);
            }
          }
        }
      }).catchError((error) {
        if (kDebugMode) {
          print('Error fetching notes from relay: $error');
        }
        completedQueries++;
        
        // Check if all queries completed
        if (completedQueries >= connectedRelays.length && !completer.isCompleted) {
          maxWaitTimer.cancel();
          final sortedEvents = _sortAndLimitEvents(uniqueEvents, limit);
          completer.complete(sortedEvents);
        }
      });
    }
    
    // Wait for the result
    final notes = await completer.future;
    
    // Cache the results
    if (notes.isNotEmpty) {
      await _noteCacheService.cacheNotes(pubkey, notes);
    }
    
    if (kDebugMode) {
      print('Found ${notes.length} notes for user: $pubkey');
    }
    
    return notes;
  }
  
  /// Helper method to sort and limit events
  List<NostrEvent> _sortAndLimitEvents(Map<String, NostrEvent> events, int limit) {
    final sortedEvents = events.values.toList()
      ..sort((a, b) => b.created_at.compareTo(a.created_at));
    return sortedEvents.take(limit).toList();
  }
  
  /// Check if a profile picture URL is valid
  bool _isValidProfilePicture(String? pictureUrl) {
    if (pictureUrl == null || pictureUrl.isEmpty) {
      return false;
    }
    
    // Check if it's a valid URL
    try {
      final uri = Uri.parse(pictureUrl);
      
      // Must be http or https
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return false;
      }
      
      // Must have a host
      if (!uri.hasAuthority || uri.host.isEmpty) {
        return false;
      }
      
      // Use image validation service to check if the image can be loaded
      return _imageValidationService.isValidImageUrl(pictureUrl);
      
    } catch (e) {
      // Invalid URL
      return false;
    }
  }
  
  /// Check if profile has required information (name/display_name and bio)
  bool _hasRequiredProfileInfo(NostrProfile profile) {
    // Must have either name or display_name (not just npub)
    final hasName = profile.name != null && 
                   profile.name!.trim().isNotEmpty && 
                   !profile.name!.startsWith('npub');
    
    final hasDisplayName = profile.displayName != null && 
                          profile.displayName!.trim().isNotEmpty &&
                          !profile.displayName!.startsWith('npub');
    
    // Must have at least one name
    if (!hasName && !hasDisplayName) {
      return false;
    }
    
    // Must have a bio/about
    final hasBio = profile.about != null && profile.about!.trim().isNotEmpty;
    
    return hasBio;
  }
  
  /// Load the list of followed profiles from local storage
  Future<void> _loadFollowedProfiles() async {
    try {
      final followedBox = await Hive.openBox<String>('followed_profiles');
      final followed = followedBox.get('followed_list');
      
      if (followed != null) {
        final List<dynamic> followedList = jsonDecode(followed);
        _followedProfiles.addAll(followedList.cast<String>());
        
        // Emit the initial set through the stream
        _followedProfilesStreamController.add(Set<String>.from(_followedProfiles));
        
        if (kDebugMode) {
          print('Loaded ${_followedProfiles.length} followed profiles from local storage');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading followed profiles: $e');
      }
    }
  }
  
  /// Load contact list from relays for a specific user
  Future<void> loadContactListFromRelays(String userPubkey) async {
    if (kDebugMode) {
      print('Loading contact list from relays for user: $userPubkey');
    }
    
    // Build a filter for contact list events (kind 3) from this user
    final filter = {
      'authors': [userPubkey],
      'kinds': [NostrEvent.contactsKind],
      'limit': 1, // Get only the most recent contact list
    };
    
    // Query multiple relays in parallel
    List<Future<List<NostrEvent>>> queries = [];
    for (final relay in _relayServices) {
      if (relay.isConnected) {
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 5)));
      }
    }
    
    if (queries.isEmpty) {
      return;
    }
    
    final results = await Future.wait(queries, eagerError: false);
    
    // Find the most recent contact list event
    NostrEvent? latestContactList;
    for (final events in results) {
      for (final event in events) {
        if (event.kind == NostrEvent.contactsKind && event.pubkey == userPubkey) {
          if (latestContactList == null || event.created_at > latestContactList.created_at) {
            latestContactList = event;
          }
        }
      }
    }
    
    if (latestContactList != null) {
      // Clear existing followed profiles
      _followedProfiles.clear();
      
      // Extract pubkeys from the 'p' tags
      for (final tag in latestContactList.tags) {
        if (tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
          _followedProfiles.add(tag[1]);
        }
      }
      
      // Save to local storage
      await _saveFollowedProfiles();
      
      // Emit the updated set through the stream
      _followedProfilesStreamController.add(Set<String>.from(_followedProfiles));
      
      if (kDebugMode) {
        print('Loaded ${_followedProfiles.length} followed profiles from relays');
        print('Contact list created at: ${DateTime.fromMillisecondsSinceEpoch(latestContactList.created_at * 1000)}');
      }
    } else {
      if (kDebugMode) {
        print('No contact list found on relays for user: $userPubkey');
      }
    }
  }
  
  /// Save the list of followed profiles to local storage
  Future<void> _saveFollowedProfiles() async {
    try {
      final followedBox = await Hive.openBox<String>('followed_profiles');
      await followedBox.put('followed_list', jsonEncode(_followedProfiles.toList()));
    } catch (e) {
      if (kDebugMode) {
        print('Error saving followed profiles: $e');
      }
    }
  }
  
  /// Check if a profile is followed by the current user
  bool isProfileFollowed(String pubkey) {
    return _followedProfiles.contains(pubkey);
  }
  
  /// Optimistically follow a profile (update local state immediately)
  void optimisticallyFollow(String pubkey) {
    final stopwatch = Stopwatch()..start();
    print('[ProfileService.optimisticallyFollow] Starting for $pubkey');
    
    if (!_followedProfiles.contains(pubkey)) {
      print('[${stopwatch.elapsedMilliseconds}ms] Adding to followed set');
      _followedProfiles.add(pubkey);
      
      // Emit the updated set through the stream IMMEDIATELY before saving
      if (kDebugMode) {
        print('[${stopwatch.elapsedMilliseconds}ms] Emitting updated followed set with ${_followedProfiles.length} profiles');
        print('Stream has ${_followedProfilesStreamController.hasListener ? "listeners" : "no listeners"}');
      }
      
      print('[${stopwatch.elapsedMilliseconds}ms] Adding to stream controller...');
      _followedProfilesStreamController.add(Set<String>.from(_followedProfiles));
      print('[${stopwatch.elapsedMilliseconds}ms] Stream emission complete');
      
      // Save to storage in the background - don't await to avoid blocking UI
      print('[${stopwatch.elapsedMilliseconds}ms] Saving to storage in background...');
      _saveFollowedProfiles().catchError((e) {
        print('[Background] Error saving followed profiles: $e');
      });
      
      if (kDebugMode) {
        print('[${stopwatch.elapsedMilliseconds}ms] Optimistically followed: $pubkey');
      }
    } else {
      print('[${stopwatch.elapsedMilliseconds}ms] Already following $pubkey');
    }
  }
  
  /// Optimistically unfollow a profile (update local state immediately)
  void optimisticallyUnfollow(String pubkey) {
    final stopwatch = Stopwatch()..start();
    print('[ProfileService.optimisticallyUnfollow] Starting for $pubkey');
    
    if (_followedProfiles.contains(pubkey)) {
      print('[${stopwatch.elapsedMilliseconds}ms] Removing from followed set');
      _followedProfiles.remove(pubkey);
      
      // Emit the updated set through the stream IMMEDIATELY before saving
      if (kDebugMode) {
        print('[${stopwatch.elapsedMilliseconds}ms] Emitting updated followed set with ${_followedProfiles.length} profiles after unfollow');
        print('Stream has ${_followedProfilesStreamController.hasListener ? "listeners" : "no listeners"}');
      }
      
      print('[${stopwatch.elapsedMilliseconds}ms] Adding to stream controller...');
      _followedProfilesStreamController.add(Set<String>.from(_followedProfiles));
      print('[${stopwatch.elapsedMilliseconds}ms] Stream emission complete');
      
      // Save to storage in the background - don't await to avoid blocking UI
      print('[${stopwatch.elapsedMilliseconds}ms] Saving to storage in background...');
      _saveFollowedProfiles().catchError((e) {
        print('[Background] Error saving followed profiles: $e');
      });
      
      if (kDebugMode) {
        print('[${stopwatch.elapsedMilliseconds}ms] Optimistically unfollowed: $pubkey');
      }
    } else {
      print('[${stopwatch.elapsedMilliseconds}ms] Not following $pubkey');
    }
  }
  
  /// Publish follow event to relays in the background
  Future<RelayPublishResult> publishFollowEvent(KeyManagementService keyService) async {
    print('\n=== PUBLISH FOLLOW EVENT ===');
    
    // Check if user is logged in
    final String? currentUserPubkey = await keyService.getPublicKey();
    if (currentUserPubkey == null) {
      print('ERROR: Cannot publish follow event: User not logged in');
      return RelayPublishResult(
        eventId: '',
        relayResults: {},
      );
    }
    
    try {
      // Get the user's keychain for signing
      final keychain = await keyService.getKeychain();
      if (keychain == null) {
        print('ERROR: Cannot create contact list: No keychain available');
        return RelayPublishResult(
          eventId: '',
          relayResults: {},
        );
      }
      
      // Create tags for each followed profile
      final List<List<String>> tags = _followedProfiles
          .map((followedPubkey) => ['p', followedPubkey])
          .toList();
      
      // Create the event using dart-nostr
      final nostrEvent = nostr.Event.from(
        kind: 3, // Contact list kind
        tags: tags,
        content: '', // Contact list events typically have empty content
        privkey: keychain.private,
      );
      
      // Convert dart-nostr Event to our NostrEvent model for publishing
      final eventData = {
        'id': nostrEvent.id,
        'pubkey': nostrEvent.pubkey,
        'created_at': nostrEvent.createdAt,
        'kind': nostrEvent.kind,
        'tags': nostrEvent.tags,
        'content': nostrEvent.content,
        'sig': nostrEvent.sig,
      };
      
      final event = NostrEvent.fromJson(eventData);
      
      // Publish to all connected relays
      final Map<String, bool> relayResults = {};
      
      // If no relays are connected, try to initialize them
      if (_relayServices.isEmpty || _relayServices.where((r) => r.isConnected).isEmpty) {
        print('⚠️  No connected relays available, attempting to reconnect...');
        await _initializeRelays();
        await Future.delayed(const Duration(seconds: 2));
      }
      
      for (final relay in _relayServices) {
        if (relay.isConnected) {
          final published = await relay.publishEvent(event);
          relayResults[relay.relayUrl] = published;
          
          if (!published) {
            print('  ❌ Failed to publish to relay: ${relay.relayUrl}');
          }
        } else {
          relayResults[relay.relayUrl] = false;
        }
      }
      
      final result = RelayPublishResult(
        eventId: event.id,
        relayResults: relayResults,
      );
      
      // Log concisely
      if (!result.isSuccess && kDebugMode) {
        print('[Follow] Failed to publish: ${result.successCount}/${result.totalRelays} relays');
      }
      
      return result;
    } catch (e) {
      print('ERROR: Failed to publish follow event: $e');
      return RelayPublishResult(
        eventId: '',
        relayResults: {},
      );
    }
  }
  
  /// Clean up resources
  void dispose() {
    if (!_profileStreamController.isClosed) {
      _profileStreamController.close();
    }
    if (!_followedProfilesStreamController.isClosed) {
      _followedProfilesStreamController.close();
    }
    // Close all relay connections
    for (final relay in _relayServices) {
      relay.disconnect();
    }
  }
  
  /// Follow or unfollow a profile
  Future<RelayPublishResult> toggleFollowProfile(String pubkey, KeyManagementService keyService) async {
    print('\n=== TOGGLE FOLLOW PROFILE ===');
    print('Target pubkey: $pubkey');
    
    final bool isCurrentlyFollowed = _followedProfiles.contains(pubkey);
    print('Currently followed: $isCurrentlyFollowed');
    print('Total followed profiles: ${_followedProfiles.length}');
    
    // Check if user is logged in
    print('Getting current user public key...');
    final String? currentUserPubkey = await keyService.getPublicKey();
    print('Current user pubkey: ${currentUserPubkey ?? "NULL"}');
    
    if (currentUserPubkey == null) {
      print('ERROR: Cannot follow/unfollow: User not logged in');
      return RelayPublishResult(
        eventId: '',
        relayResults: {},
      );
    }
    
    // Toggle the follow status
    if (isCurrentlyFollowed) {
      _followedProfiles.remove(pubkey);
    } else {
      _followedProfiles.add(pubkey);
    }
    
    // Save to local storage
    await _saveFollowedProfiles();
    
    // Emit the updated set through the stream
    _followedProfilesStreamController.add(Set<String>.from(_followedProfiles));
    
    // Create and publish a contact list event
    try {
      // Get the user's keychain for signing
      print('Getting keychain for signing...');
      final keychain = await keyService.getKeychain();
      if (keychain == null) {
        print('ERROR: Cannot create contact list: No keychain available');
        return RelayPublishResult(
          eventId: '',
          relayResults: {},
        );
      }
      print('Keychain obtained successfully');
      print('Public key from keychain: ${keychain.public}');
      
      // Create tags for each followed profile
      final List<List<String>> tags = _followedProfiles
          .map((followedPubkey) => ['p', followedPubkey])
          .toList();
      
      // Create the event using dart-nostr
      print('Creating contact list event...');
      print('  Kind: 3 (contact list)');
      print('  Tags: ${tags.length} profiles');
      print('  First few tags: ${tags.take(3).toList()}');
      
      final nostrEvent = nostr.Event.from(
        kind: 3, // Contact list kind
        tags: tags,
        content: '', // Contact list events typically have empty content
        privkey: keychain.private,
      );
      
      print('Event created successfully:');
      print('  Event ID: ${nostrEvent.id}');
      print('  Public key: ${nostrEvent.pubkey}');
      print('  Created at: ${nostrEvent.createdAt}');
      print('  Signature: ${nostrEvent.sig.substring(0, 20)}...');
      
      // Convert dart-nostr Event to our NostrEvent model for publishing
      final eventData = {
        'id': nostrEvent.id,
        'pubkey': nostrEvent.pubkey,
        'created_at': nostrEvent.createdAt,
        'kind': nostrEvent.kind,
        'tags': nostrEvent.tags,
        'content': nostrEvent.content,
        'sig': nostrEvent.sig,
      };
      
      final event = NostrEvent.fromJson(eventData);
      
      // Publish to all connected relays
      final Map<String, bool> relayResults = {};
      
      // DEBUG: Show the event being published
      if (kDebugMode) {
        print('\n=== PUBLISHING CONTACT LIST EVENT ===');
        print('Event JSON: ${jsonEncode(eventData)}');
        print('Event ID: ${event.id}');
        print('Signature: ${event.sig}');
        print('Connected relays: ${_relayServices.where((r) => r.isConnected).length}/${_relayServices.length}');
      }
      
      // If no relays are connected, try to initialize them
      if (_relayServices.isEmpty || _relayServices.where((r) => r.isConnected).isEmpty) {
        print('⚠️  No connected relays available, attempting to reconnect...');
        await _initializeRelays();
        
        // Give connections time to establish
        await Future.delayed(const Duration(seconds: 2));
      }
      
      for (final relay in _relayServices) {
        if (relay.isConnected) {
          if (kDebugMode) {
            print('\nPublishing to ${relay.relayUrl}...');
          }
          
          final published = await relay.publishEvent(event);
          relayResults[relay.relayUrl] = published;
          
          if (published) {
            if (kDebugMode) {
              print('  ✅ Published to relay: ${relay.relayUrl}');
            }
          } else {
            // Always log failures, not just in debug mode
            print('  ❌ Failed to publish to relay: ${relay.relayUrl}');
          }
        } else {
          relayResults[relay.relayUrl] = false;
          if (kDebugMode) {
            print('  ⚠️  Relay not connected: ${relay.relayUrl}');
          }
        }
      }
      
      final result = RelayPublishResult(
        eventId: event.id,
        relayResults: relayResults,
      );
      
      // Log the specific line requested by the user
      if (kDebugMode) {
        final successfulRelays = relayResults.entries
            .where((entry) => entry.value)
            .map((entry) => entry.key)
            .toList();
        print('### Event ID: ${event.id} published to relays: ${successfulRelays.join(", ")}');
      }
      
      if (kDebugMode) {
        print('\n=== CONTACT LIST PUBLISH SUMMARY ===');
        print('Successfully published to ${result.successCount}/${result.totalRelays} relays');
        print('${isCurrentlyFollowed ? 'Unfollowed' : 'Followed'} profile: $pubkey');
        print('Success rate: ${(result.successRate * 100).toStringAsFixed(1)}%');
        print('====================================\n');
      }
      
      return result;
    } catch (e, stackTrace) {
      print('ERROR: Failed to publish follow event');
      print('  Exception: $e');
      print('  Stack trace: $stackTrace');
      return RelayPublishResult(
        eventId: '',
        relayResults: {},
      );
    }
  }
  
}

/// Provider for the profile service 
final profileServiceProvider = Provider<ProfileService>((ref) {
  // Use the hardcoded relay URLs
  final relays = ref.watch(relayUrlsProvider);
  return ProfileService(relays);
});


final profileProvider = FutureProvider.family<NostrProfile?, String>((ref, pubkey) async {
  final profileService = ref.watch(profileServiceProvider);
  return await profileService.getProfile(pubkey);
});

final profileDiscoveryProvider = FutureProvider<List<NostrProfile>>((ref) async {
  final profileService = ref.watch(profileServiceProvider);
  return await profileService.discoverProfiles();
});

final isProfileFollowedProvider = StreamProvider.family<bool, String>((ref, pubkey) {
  print('[Provider Creation] isProfileFollowedProvider being created for ${pubkey.substring(0, 8)}...');
  final profileService = ref.watch(profileServiceProvider);
  
  // Create a stream that immediately emits the current state
  // then continues to emit updates from the followed profiles stream
  return Stream<bool>.multi((controller) {
    final providerStopwatch = Stopwatch()..start();
    print('[${providerStopwatch.elapsedMilliseconds}ms] Stream.multi callback started for ${pubkey.substring(0, 8)}...');
    
    // Emit the current state immediately
    final initialState = profileService.isProfileFollowed(pubkey);
    if (kDebugMode) {
      print('[${providerStopwatch.elapsedMilliseconds}ms] isProfileFollowedProvider(${pubkey.substring(0, 8)}...): Initial state = $initialState');
    }
    controller.add(initialState);
    print('[${providerStopwatch.elapsedMilliseconds}ms] Initial state emitted');
    
    // Listen to the stream for updates
    print('[${providerStopwatch.elapsedMilliseconds}ms] Creating stream subscription...');
    final subscription = profileService.followedProfilesStream.listen((followedSet) {
      final newState = followedSet.contains(pubkey);
      if (kDebugMode) {
        print('[StreamProvider] isProfileFollowedProvider(${pubkey.substring(0, 8)}...): Stream update received = $newState (set size: ${followedSet.length})');
      }
      controller.add(newState);
    });
    print('[${providerStopwatch.elapsedMilliseconds}ms] Stream subscription created');
    
    // Clean up the subscription when the stream is closed
    controller.onCancel = () {
      subscription.cancel();
    };
  });
});

final followProfileProvider = FutureProvider.family<RelayPublishResult, String>((ref, pubkey) async {
  final profileService = ref.watch(profileServiceProvider);
  final keyService = ref.watch(keyManagementServiceProvider);
  return await profileService.toggleFollowProfile(pubkey, keyService);
});

/// Provider for publishing follow events in the background (after optimistic updates)
final publishFollowEventProvider = FutureProvider<RelayPublishResult>((ref) async {
  final profileService = ref.watch(profileServiceProvider);
  final keyService = ref.watch(keyManagementServiceProvider);
  return await profileService.publishFollowEvent(keyService);
});

// Stream provider for the followed profiles set
final followedProfilesStreamProvider = StreamProvider<Set<String>>((ref) {
  final profileService = ref.watch(profileServiceProvider);
  return profileService.followedProfilesStream;
});

// Simple provider that returns current follow state by watching the stream
final isProfileFollowedSimpleProvider = Provider.family<bool, String>((ref, pubkey) {
  final profileService = ref.watch(profileServiceProvider);
  
  // Watch the stream to rebuild when it changes
  final followedSetAsync = ref.watch(followedProfilesStreamProvider);
  final followedSet = followedSetAsync.valueOrNull ?? profileService.followedProfiles;
  
  return followedSet.contains(pubkey);
});

/// Service for managing a buffer of profiles
class ProfileBufferService {
  final ProfileService _profileService;
  final DiscardedProfilesService? _discardedService;
  final FailedImagesService? _failedImagesService;
  final ProfileReadinessService _readinessService = ProfileReadinessService();
  
  // Configuration for progressive loading
  static const int _initialLoadCount = 5;
  static const int _batchLoadCount = 10;
  static const int _prefetchThreshold = 3; // Start loading more when 3 profiles remain
  
  // This list will persist in memory as long as the app is running
  final List<NostrProfile> _profileBuffer = [];
  
  // Staging area for profiles being prepared
  final List<NostrProfile> _stagingBuffer = [];
  
  bool _isFetching = false;
  bool _isLoadingInitial = false;
  bool _isPreparingProfiles = false;
  
  // Track the last viewed index to restore position
  int _lastViewedIndex = 0;
  
  // Persist the buffer state
  bool _hasInitializedBuffer = false;
  
  final StreamController<List<NostrProfile>> _bufferStreamController = 
      StreamController<List<NostrProfile>>.broadcast();
  
  ProfileBufferService(this._profileService, [this._discardedService, this._failedImagesService]) {
    // Initialize the buffer with initial profiles - but only once
    if (!_hasInitializedBuffer) {
      _loadInitialProfiles();
    }
  }
  
  /// Get the stream of buffered profiles
  Stream<List<NostrProfile>> get profilesStream => _bufferStreamController.stream;
  
  /// Get the current buffered profiles
  List<NostrProfile> get currentProfiles => List.unmodifiable(_profileBuffer);
  
  /// Check if profiles are currently being fetched
  bool get isFetching => _isFetching;
  
  /// Get the last viewed index
  int get lastViewedIndex => _lastViewedIndex;
  
  /// Set the last viewed index
  set lastViewedIndex(int index) {
    _lastViewedIndex = index;
  }
  
  /// Check if buffer has been initialized
  bool get hasLoadedProfiles => _hasInitializedBuffer && _profileBuffer.isNotEmpty;
  
  /// Check if initial profiles are being loaded
  bool get isLoadingInitial => _isLoadingInitial;
  
  /// Load initial 5 profiles immediately
  Future<void> _loadInitialProfiles() async {
    if (_isFetching || _isLoadingInitial) return;
    
    _isLoadingInitial = true;
    _notifyListeners();
    
    try {
      
      // Fetch initial profiles
      final candidateProfiles = await _profileService.discoverProfiles(
        limit: _initialLoadCount * 3, // Fetch more to account for filtering
        discardedService: _discardedService,
        failedImagesService: _failedImagesService,
      );
      
      if (candidateProfiles.isNotEmpty) {
        // Add to staging buffer
        _stagingBuffer.addAll(candidateProfiles);
        
        // Prepare profiles for presentation
        await _prepareProfilesForPresentation();
        
        _hasInitializedBuffer = true;
        
        if (kDebugMode) {
          print('Initial profiles ready: ${_profileBuffer.length}');
        }
        
        // Start background loading of more profiles
        _loadMoreProfiles();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading initial profiles: $e');
      }
    } finally {
      _isLoadingInitial = false;
      _notifyListeners();
    }
  }
  
  /// Load more profiles in batches of 10
  Future<void> _loadMoreProfiles() async {
    if (_isFetching) return;
    
    _isFetching = true;
    
    try {
      if (kDebugMode) {
        print('Loading more profiles in background...');
      }
      
      // Fetch new profiles
      final newProfiles = await _profileService.discoverProfiles(
        limit: _batchLoadCount * 2, // Fetch more to account for preparation filtering
        discardedService: _discardedService,
        failedImagesService: _failedImagesService,
      );
      
      // Filter out profiles that are already in buffers or are followed
      final existingPubkeys = {..._profileBuffer.map((p) => p.pubkey), ..._stagingBuffer.map((p) => p.pubkey)};
      final uniqueNewProfiles = newProfiles
          .where((profile) => !existingPubkeys.contains(profile.pubkey))
          .where((profile) => !_profileService.isProfileFollowed(profile.pubkey))
          .toList();
        
      if (uniqueNewProfiles.isNotEmpty) {
        // Add to staging buffer
        _stagingBuffer.addAll(uniqueNewProfiles);
        
        if (kDebugMode) {
          print('Added ${uniqueNewProfiles.length} profiles to staging. Staging: ${_stagingBuffer.length}');
        }
        
        // Prepare profiles if not already preparing
        if (!_isPreparingProfiles) {
          _prepareProfilesForPresentation();
        }
        
        // Continue loading more profiles in background
        // Short delay to avoid overloading relays
        await Future.delayed(const Duration(seconds: 2));
        _loadMoreProfiles(); // Recursive call to continue loading
      } else {
        if (kDebugMode) {
          print('No more unique profiles available');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading more profiles: $e');
      }
    } finally {
      _isFetching = false;
    }
  }
  
  /// Prepare profiles from staging buffer for presentation
  Future<void> _prepareProfilesForPresentation() async {
    if (_isPreparingProfiles || _stagingBuffer.isEmpty) return;
    
    _isPreparingProfiles = true;
    
    try {
      if (kDebugMode) {
        print('Preparing ${_stagingBuffer.length} profiles for presentation...');
      }
      
      final readyProfiles = <NostrProfile>[];
      final failedProfiles = <NostrProfile>[];
      
      // Process profiles in small batches to avoid blocking
      const batchSize = 3;
      
      while (_stagingBuffer.isNotEmpty && readyProfiles.length < _batchLoadCount) {
        // Take a batch from staging
        final batch = _stagingBuffer.take(batchSize).toList();
        _stagingBuffer.removeRange(0, batch.length.clamp(0, _stagingBuffer.length));
        
        // Filter out any followed profiles that might have slipped through
        final filteredBatch = batch.where((profile) => !_profileService.isProfileFollowed(profile.pubkey)).toList();
        
        // Check each profile in parallel
        final results = await Future.wait(
          filteredBatch.map((profile) async {
            // First, get user's post count
            int postCount = 0;
            try {
              final notes = await _profileService.getUserNotes(profile.pubkey, limit: 1);
              postCount = notes.isNotEmpty ? 1 : 0; // We just need to know if they have any posts
              
              // If we found at least one, assume they have posts
              if (postCount > 0) {
                _readinessService.updatePostCount(profile.pubkey, postCount);
              }
            } catch (e) {
              if (kDebugMode) {
                print('Failed to fetch posts for ${profile.displayNameOrName}: $e');
              }
            }
            
            // Check if profile is ready (including post count check)
            final isReady = await _readinessService.isProfileReady(profile, postCount: postCount);
            
            if (!isReady && profile.picture != null && postCount > 0) {
              // Try to preload the image only if they have posts
              final preloaded = await _readinessService.preloadProfileImage(profile);
              return (profile, preloaded);
            }
            
            return (profile, isReady);
          }),
        );
        
        // Separate ready and failed profiles
        for (final (profile, isReady) in results) {
          if (isReady) {
            readyProfiles.add(profile);
          } else {
            failedProfiles.add(profile);
            
            // Mark the image as failed if it couldn't be preloaded
            if (profile.picture != null && _failedImagesService != null) {
              await _failedImagesService!.markImageAsFailed(profile.picture!);
            }
          }
        }
        
        // Add ready profiles to main buffer immediately
        if (readyProfiles.isNotEmpty) {
          _profileBuffer.addAll(readyProfiles);
          // Delay notification to avoid lifecycle issues
          Future.microtask(() => _notifyListeners());
          readyProfiles.clear();
        }
        
        // Small delay between batches
        if (_stagingBuffer.isNotEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      
      if (kDebugMode) {
        print('Preparation complete. Ready: ${_profileBuffer.length}, Failed: ${failedProfiles.length}, Staging: ${_stagingBuffer.length}');
      }
      
      // If buffer is running low, trigger more loading
      if (_profileBuffer.length < _prefetchThreshold * 2 && !_isFetching) {
        _loadMoreProfiles();
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('Error preparing profiles: $e');
      }
    } finally {
      _isPreparingProfiles = false;
      
      // Continue preparing if there are more profiles in staging
      if (_stagingBuffer.isNotEmpty) {
        Future.delayed(const Duration(seconds: 1), () {
          _prepareProfilesForPresentation();
        });
      }
    }
  }
  
  /// Check if we need to prefetch more profiles
  void checkBufferState(int currentIndex) {
    // Update last viewed index
    _lastViewedIndex = currentIndex;
    
    // If we're approaching the end of the buffer, fetch more profiles
    if (!_isFetching && 
        _profileBuffer.isNotEmpty && 
        currentIndex >= _profileBuffer.length - _prefetchThreshold) {
      if (kDebugMode) {
        print('User at index $currentIndex (${_profileBuffer.length} ready, ${_stagingBuffer.length} staging), loading more...');
      }
      _loadMoreProfiles();
    }
    
    // Also trigger preparation if staging buffer has profiles
    if (!_isPreparingProfiles && _stagingBuffer.isNotEmpty) {
      _prepareProfilesForPresentation();
    }
  }
  
  /// Helper to notify listeners
  void _notifyListeners() {
    // Use Future.microtask to avoid calling during build
    Future.microtask(() {
      if (!_bufferStreamController.isClosed) {
        _bufferStreamController.add(List.unmodifiable(_profileBuffer));
      }
    });
  }
  
  /// Remove a profile from the buffer (e.g., when user skips)
  void removeProfile(String pubkey) {
    _profileBuffer.removeWhere((profile) => profile.pubkey == pubkey);
    _stagingBuffer.removeWhere((profile) => profile.pubkey == pubkey);
    _notifyListeners();
    
    // Check if we need to load more profiles
    if (_profileBuffer.length < _prefetchThreshold * 2) {
      _loadMoreProfiles();
    }
    
    // Trigger preparation if needed
    if (!_isPreparingProfiles && _stagingBuffer.isNotEmpty) {
      _prepareProfilesForPresentation();
    }
  }
  
  /// Refresh the entire buffer (e.g., when user pulls to refresh)
  Future<void> refreshBuffer() async {
    // Clear both buffers
    _profileBuffer.clear();
    _stagingBuffer.clear();
    _notifyListeners();
    
    // Force re-fetching of profiles by temporarily resetting the initialized flag
    _hasInitializedBuffer = false;
    _isFetching = false;
    _isLoadingInitial = false;
    _isPreparingProfiles = false;
    
    // Clear readiness cache to force fresh checks
    _readinessService.clearCache();
    
    // Start fresh with initial load
    await _loadInitialProfiles();
    
    // Reset the last viewed index
    _lastViewedIndex = 0;
  }
  
  /// Clean up resources
  void dispose() {
    if (!_bufferStreamController.isClosed) {
      _bufferStreamController.close();
    }
  }
}

/// We'll use a singleton for the buffer service to ensure it persists across widget rebuilds
/// and doesn't get recreated with state changes
class ProfileBufferServiceSingleton {
  static ProfileBufferService? _instance;
  
  static ProfileBufferService getInstance(ProfileService profileService, DiscardedProfilesService? discardedService, FailedImagesService? failedImagesService) {
    _instance ??= ProfileBufferService(profileService, discardedService, failedImagesService);
    return _instance!;
  }
}

/// Provider for the profile buffer service
final profileBufferServiceProvider = Provider<ProfileBufferService>((ref) {
  final profileService = ref.watch(profileServiceProvider);
  final discardedService = ref.watch(discardedProfilesServiceProvider);
  final failedImagesService = ref.watch(failedImagesServiceProvider);
  // Use singleton pattern to ensure same instance persists
  return ProfileBufferServiceSingleton.getInstance(profileService, discardedService, failedImagesService);
});

/// Stream provider for buffered profiles with no auto-dispose
final bufferedProfilesProvider = StreamProvider<List<NostrProfile>>((ref) {
  final bufferService = ref.watch(profileBufferServiceProvider);
  return bufferService.profilesStream;
});

/// Provider to check if more profiles are being fetched
final isFetchingMoreProfilesProvider = Provider<bool>((ref) {
  final bufferService = ref.watch(profileBufferServiceProvider);
  return bufferService.isFetching;
});