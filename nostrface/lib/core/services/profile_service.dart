import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:nostrface/core/models/nostr_event.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/nostr_relay_service.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// Service for managing Nostr profile data
class ProfileService {
  final List<String> _relayUrls;
  final List<NostrRelayService> _relayServices = [];
  final Map<String, NostrProfile> _profiles = {};
  final StreamController<NostrProfile> _profileStreamController = StreamController<NostrProfile>.broadcast();
  final Set<String> _followedProfiles = {};
  final Map<String, bool> _trustedProfilesCache = {};
  
  ProfileService(this._relayUrls) {
    _initializeRelays();
    _loadFollowedProfiles();
  }
  
  Stream<NostrProfile> get profileStream => _profileStreamController.stream;
  Set<String> get followedProfiles => _followedProfiles;
  
  /// Get the relay URLs for connecting to Nostr network
  List<String> get relayUrls => List.unmodifiable(_relayUrls);
  
  /// Check if a profile is trusted according to the trust API
  Future<bool> isProfileTrusted(String pubkey) async {
    // Check cache first
    if (_trustedProfilesCache.containsKey(pubkey)) {
      return _trustedProfilesCache[pubkey]!;
    }
    
    try {
      final url = 'https://followers.nos.social/api/v1/trusted/$pubkey';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          return http.Response('{"error": "timeout"}', 408);
        },
      );
      
      if (response.statusCode == 200) {
        // API returns true or false directly
        final isTrusted = response.body.toLowerCase().trim() == 'true';
        
        // Cache the result
        _trustedProfilesCache[pubkey] = isTrusted;
        
        return isTrusted;
      } else {
        if (kDebugMode) {
          print('Error checking if profile is trusted: ${response.statusCode} - ${response.body}');
        }
        
        // Assume not trusted on error
        _trustedProfilesCache[pubkey] = false;
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Exception checking if profile is trusted: $e');
      }
      
      // Assume not trusted on error
      _trustedProfilesCache[pubkey] = false;
      return false;
    }
  }
  
  /// Initialize connections to relays
  Future<void> _initializeRelays() async {
    if (kDebugMode) {
      print('Initializing connections to ${_relayUrls.length} relays');
    }
    
    // In web, we'll try to connect to all relays, but use a timeout to avoid waiting too long
    final connectFutures = _relayUrls.map((relayUrl) async {
      try {
        if (kDebugMode) {
          print('Attempting to connect to relay: $relayUrl');
        }
        
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
          if (kDebugMode) {
            print('Successfully connected to relay: $relayUrl');
          }
          
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
    if (kDebugMode) {
      print('Connected to $connectedCount out of ${_relayUrls.length} relays');
    }
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
  
  /// Discover random profiles from the relays and filter by trust API
  Future<List<NostrProfile>> discoverProfiles({int limit = 10}) async {
    // Increase the initial limit to account for filtering
    final initialLimit = limit * 3;
    
    List<NostrProfile> candidateProfiles = [];
    List<NostrProfile> trustedProfiles = [];
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
                  
                  // Only consider profiles with pictures
                  if (profile.picture != null && profile.picture!.isNotEmpty) {
                    candidateProfiles.add(profile);
                  }
                } catch (e) {
                  if (kDebugMode) {
                    print('Error parsing cached profile: $e');
                  }
                }
              }
            }
            
            // Filter cached profiles by trust API
            if (candidateProfiles.isNotEmpty) {
              // Check each profile against the trust API
              await Future.wait(
                candidateProfiles.map((profile) async {
                  if (await isProfileTrusted(profile.pubkey)) {
                    trustedProfiles.add(profile);
                  }
                })
              );
              
              if (trustedProfiles.isNotEmpty) {
                if (kDebugMode) {
                  print('Returning ${trustedProfiles.length} trusted cached profiles');
                }
                return trustedProfiles.take(limit).toList();
              } else {
                if (kDebugMode) {
                  print('No trusted cached profiles found, fetching from relays');
                }
              }
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
        if (kDebugMode) {
          print('Fetching profiles from ${relay.relayUrl}');
        }
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 15)));
      }
    }
    
    // Handle empty queries case
    if (queries.isEmpty) {
      if (kDebugMode) {
        print('No connected relays to query');
      }
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
            
            // Only add profiles with pictures for better UX
            if (profile.picture != null && profile.picture!.isNotEmpty) {
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
      print('Found ${candidateProfiles.length} candidate profiles, filtering by trust API');
    }
    
    // Filter profiles by trust API in parallel
    await Future.wait(
      candidateProfiles.map((profile) async {
        if (await isProfileTrusted(profile.pubkey)) {
          trustedProfiles.add(profile);
        }
      })
    );
    
    if (kDebugMode) {
      print('After filtering, found ${trustedProfiles.length} trusted profiles');
    }
    
    // Return only trusted profiles
    return trustedProfiles.take(limit).toList();
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
  
  /// Fetch recent text notes from a specific user
  Future<List<NostrEvent>> getUserNotes(String pubkey, {int limit = 10}) async {
    if (kDebugMode) {
      print('Fetching notes for user: $pubkey, limit: $limit');
    }
    
    // If we have no active relay connections, attempt to reconnect
    if (_relayServices.isEmpty) {
      await _initializeRelays();
      
      if (_relayServices.isEmpty) {
        if (kDebugMode) {
          print('No relay connections available for fetching notes');
        }
        return [];
      }
    }
    
    // Build a filter for Kind 1 (text notes) events from this user
    final filter = {
      'authors': [pubkey],
      'kinds': [NostrEvent.textNoteKind],
      'limit': limit,
    };
    
    // Query multiple relays in parallel
    List<Future<List<NostrEvent>>> queries = [];
    for (final relay in _relayServices) {
      if (relay.isConnected) {
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 5)));
      }
    }
    
    if (queries.isEmpty) {
      if (kDebugMode) {
        print('No connected relays to query for notes');
      }
      return [];
    }
    
    // Wait for all queries to complete
    final results = await Future.wait(queries, eagerError: false);
    
    // Combine all results and remove duplicates
    final Map<String, NostrEvent> uniqueEvents = {};
    
    for (final events in results) {
      for (final event in events) {
        // Keep the most recent event if we have duplicates
        if (!uniqueEvents.containsKey(event.id) || 
            uniqueEvents[event.id]!.created_at < event.created_at) {
          uniqueEvents[event.id] = event;
        }
      }
    }
    
    // Sort events by creation time (newest first)
    final sortedEvents = uniqueEvents.values.toList()
      ..sort((a, b) => b.created_at.compareTo(a.created_at));
    
    if (kDebugMode) {
      print('Found ${sortedEvents.length} notes for user: $pubkey');
    }
    
    return sortedEvents.take(limit).toList();
  }
  
  /// Load the list of followed profiles from local storage
  Future<void> _loadFollowedProfiles() async {
    try {
      final followedBox = await Hive.openBox<String>('followed_profiles');
      final followed = followedBox.get('followed_list');
      
      if (followed != null) {
        final List<dynamic> followedList = jsonDecode(followed);
        _followedProfiles.addAll(followedList.cast<String>());
        
        if (kDebugMode) {
          print('Loaded ${_followedProfiles.length} followed profiles');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading followed profiles: $e');
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
  
  /// Follow or unfollow a profile
  Future<bool> toggleFollowProfile(String pubkey, KeyManagementService keyService) async {
    final bool isCurrentlyFollowed = _followedProfiles.contains(pubkey);
    
    // Check if user is logged in
    final String? currentUserPubkey = await keyService.getPublicKey();
    if (currentUserPubkey == null) {
      if (kDebugMode) {
        print('Cannot follow/unfollow: User not logged in');
      }
      return false;
    }
    
    // Toggle the follow status
    if (isCurrentlyFollowed) {
      _followedProfiles.remove(pubkey);
    } else {
      _followedProfiles.add(pubkey);
    }
    
    // Save to local storage
    await _saveFollowedProfiles();
    
    // Create and publish a contact list event
    try {
      // Create tags for each followed profile
      final List<List<String>> tags = _followedProfiles
          .map((followedPubkey) => ['p', followedPubkey])
          .toList();
      
      // Create the event data
      final eventData = {
        'pubkey': currentUserPubkey,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': NostrEvent.contactsKind,
        'tags': tags,
        'content': '', // Contact list events typically have empty content
      };
      
      // Sign the event
      final String sig = await keyService.signEvent(eventData);
      
      // Add the signature and generate an event ID (in a real app)
      eventData['sig'] = sig;
      eventData['id'] = const Uuid().v4(); // In a real app, this would be a proper hash
      
      // Create the NostrEvent and publish to relays
      final event = NostrEvent.fromJson(eventData);
      
      // Publish to all connected relays
      for (final relay in _relayServices) {
        if (relay.isConnected) {
          await relay.publishEvent(event);
        }
      }
      
      if (kDebugMode) {
        print('Successfully ${isCurrentlyFollowed ? 'unfollowed' : 'followed'} profile: $pubkey');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error publishing follow event: $e');
      }
      return false;
    }
  }
}

final profileServiceProvider = Provider<ProfileService>((ref) {
  final relays = ref.watch(defaultRelaysProvider);
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

final isProfileFollowedProvider = Provider.family<bool, String>((ref, pubkey) {
  final profileService = ref.watch(profileServiceProvider);
  return profileService.isProfileFollowed(pubkey);
});

final followProfileProvider = FutureProvider.family<bool, String>((ref, pubkey) async {
  final profileService = ref.watch(profileServiceProvider);
  final keyService = ref.watch(keyManagementServiceProvider);
  return await profileService.toggleFollowProfile(pubkey, keyService);
});

final isProfileTrustedProvider = FutureProvider.family<bool, String>((ref, pubkey) async {
  final profileService = ref.watch(profileServiceProvider);
  return await profileService.isProfileTrusted(pubkey);
});

/// Service for managing a buffer of trusted profiles
class ProfileBufferService {
  final ProfileService _profileService;
  final int _bufferSize;
  final int _prefetchThreshold;
  
  // This list will persist in memory as long as the app is running
  final List<NostrProfile> _profileBuffer = [];
  bool _isFetching = false;
  
  // Track the last viewed index to restore position
  int _lastViewedIndex = 0;
  
  // Persist the buffer state
  bool _hasInitializedBuffer = false;
  
  final StreamController<List<NostrProfile>> _bufferStreamController = 
      StreamController<List<NostrProfile>>.broadcast();
  
  ProfileBufferService(this._profileService, {
    int bufferSize = 100,
    int prefetchThreshold = 10,
  }) : 
    _bufferSize = bufferSize,
    _prefetchThreshold = prefetchThreshold {
    // Initialize the buffer with initial profiles - but only once
    if (!_hasInitializedBuffer) {
      _fillBuffer();
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
  
  /// Fill the buffer with trusted profiles
  Future<void> _fillBuffer() async {
    if (_isFetching) return;
    
    _isFetching = true;
    _notifyListeners();
    
    try {
      // If we already have profiles and the buffer is marked as initialized,
      // we can just notify listeners and return
      if (_hasInitializedBuffer && _profileBuffer.isNotEmpty) {
        if (kDebugMode) {
          print('Using ${_profileBuffer.length} cached profiles from memory');
        }
        _isFetching = false;
        _notifyListeners();
        return;
      }
      
      // Calculate how many profiles we need to fetch
      final fetchCount = _bufferSize - _profileBuffer.length;
      
      if (fetchCount <= 0) {
        _hasInitializedBuffer = true;
        _isFetching = false;
        _notifyListeners();
        return;
      }
      
      // Fetch new profiles in batches to avoid overwhelming the network
      const batchSize = 20;
      int remaining = fetchCount;
      
      while (remaining > 0 && _profileBuffer.length < _bufferSize) {
        final fetchSize = remaining > batchSize ? batchSize : remaining;
        final newProfiles = await _profileService.discoverProfiles(limit: fetchSize);
        
        // Filter out profiles that are already in the buffer
        final existingPubkeys = _profileBuffer.map((p) => p.pubkey).toSet();
        final uniqueNewProfiles = newProfiles
            .where((profile) => !existingPubkeys.contains(profile.pubkey))
            .toList();
        
        if (uniqueNewProfiles.isEmpty) {
          // No more unique profiles available from the relays
          break;
        }
        
        // Add to buffer
        _profileBuffer.addAll(uniqueNewProfiles);
        remaining -= uniqueNewProfiles.length;
        
        // Notify listeners of the updated buffer
        _notifyListeners();
        
        // Short delay to avoid overloading relays
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Mark buffer as initialized if we have profiles
      if (_profileBuffer.isNotEmpty) {
        _hasInitializedBuffer = true;
        if (kDebugMode) {
          print('Profile buffer initialized with ${_profileBuffer.length} profiles');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error filling profile buffer: $e');
      }
    } finally {
      _isFetching = false;
      _notifyListeners();
    }
  }
  
  /// Check if we need to prefetch more profiles
  void checkBufferState(int currentIndex) {
    // If we're approaching the end of the buffer, fetch more profiles
    if (!_isFetching && 
        _profileBuffer.isNotEmpty && 
        currentIndex >= _profileBuffer.length - _prefetchThreshold) {
      _fillBuffer();
    }
  }
  
  /// Helper to notify listeners
  void _notifyListeners() {
    _bufferStreamController.add(List.unmodifiable(_profileBuffer));
  }
  
  /// Remove a profile from the buffer (e.g., when user skips)
  void removeProfile(String pubkey) {
    _profileBuffer.removeWhere((profile) => profile.pubkey == pubkey);
    _notifyListeners();
    
    // Check if we need to refill the buffer
    if (_profileBuffer.length < _bufferSize - _prefetchThreshold) {
      _fillBuffer();
    }
  }
  
  /// Refresh the entire buffer (e.g., when user pulls to refresh)
  Future<void> refreshBuffer() async {
    // Clear the buffer but keep track of initialization state
    _profileBuffer.clear();
    _notifyListeners();
    
    // Force re-fetching of profiles by temporarily resetting the initialized flag
    final wasInitialized = _hasInitializedBuffer;
    _hasInitializedBuffer = false;
    
    // Fill the buffer
    await _fillBuffer();
    
    // Restore initialization state if filling failed
    if (!_hasInitializedBuffer) {
      _hasInitializedBuffer = wasInitialized;
    }
    
    // Reset the last viewed index
    _lastViewedIndex = 0;
  }
  
  /// Clean up resources
  void dispose() {
    _bufferStreamController.close();
  }
}

/// Provider for the profile buffer service
final profileBufferServiceProvider = Provider<ProfileBufferService>((ref) {
  final profileService = ref.watch(profileServiceProvider);
  return ProfileBufferService(profileService);
});

/// Stream provider for buffered profiles
final bufferedProfilesProvider = StreamProvider<List<NostrProfile>>((ref) {
  final bufferService = ref.watch(profileBufferServiceProvider);
  return bufferService.profilesStream;
});

/// Provider to check if more profiles are being fetched
final isFetchingMoreProfilesProvider = Provider<bool>((ref) {
  final bufferService = ref.watch(profileBufferServiceProvider);
  return bufferService.isFetching;
});