import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:nostrface/core/utils/nostr_legacy_support.dart' as nostr;
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/nostr_relay_service_v2.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:hive/hive.dart';

/// Service for managing Nostr profile data using dart-nostr
class ProfileServiceV2 {
  final List<String> _relayUrls;
  final List<NostrRelayServiceV2> _relayServices = [];
  final Map<String, NostrProfile> _profiles = {};
  final StreamController<NostrProfile> _profileStreamController = StreamController<NostrProfile>.broadcast();
  final Set<String> _followedProfiles = {};
  final Map<String, bool> _trustedProfilesCache = {};
  
  
  ProfileServiceV2(this._relayUrls) {
    _initializeRelays();
    _loadFollowedProfiles();
  }
  
  
  Stream<NostrProfile> get profileStream => _profileStreamController.stream;
  Set<String> get followedProfiles => _followedProfiles;
  List<String> get relayUrls => List.unmodifiable(_relayUrls);
  
  /// Check if a profile is trusted according to the trust API
  Future<bool> isProfileTrusted(String pubkey) async {
    if (_trustedProfilesCache.containsKey(pubkey)) {
      return _trustedProfilesCache[pubkey]!;
    }
    
    try {
      final url = 'https://followers.nos.social/api/v1/trusted/$pubkey';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 5),
        onTimeout: () => http.Response('{"error": "timeout"}', 408),
      );
      
      if (response.statusCode == 200) {
        final isTrusted = response.body.toLowerCase().trim() == 'true';
        _trustedProfilesCache[pubkey] = isTrusted;
        return isTrusted;
      } else {
        _trustedProfilesCache[pubkey] = false;
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Exception checking if profile is trusted: $e');
      }
      _trustedProfilesCache[pubkey] = false;
      return false;
    }
  }
  
  
  /// Initialize relay connections from a list of URLs
  Future<void> _initializeRelaysFromUrls(List<String> urls) async {
    if (kDebugMode) {
      print('Initializing connections to ${urls.length} relays');
    }
    
    final connectFutures = urls.map((relayUrl) async {
      try {
        final relay = NostrRelayServiceV2(relayUrl);
        final connected = await relay.connect().timeout(
          const Duration(seconds: 5),
          onTimeout: () => false,
        );
        
        if (connected) {
          _relayServices.add(relay);
          
          // Subscribe to metadata events
          relay.eventStream.listen((event) {
            if (event.kind == 0) { // Metadata event
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
    
    final results = await Future.wait(connectFutures, eagerError: false);
    final connectedCount = results.where((result) => result).length;
    
    if (kDebugMode) {
      print('Connected to $connectedCount out of ${urls.length} relays');
    }
  }
  
  /// Initialize connections to relays
  Future<void> _initializeRelays() async {
    await _initializeRelaysFromUrls(_relayUrls);
  }
  
  /// Handle a profile metadata event (Kind 0)
  void _handleProfileMetadata(nostr.Event event) {
    try {
      final profile = NostrProfile.fromMetadataEvent(event.pubkey, event.content);
      _profiles[event.pubkey] = profile;
      _profileStreamController.add(profile);
    } catch (e) {
      if (kDebugMode) {
        print('Error handling profile metadata: $e');
      }
    }
  }
  
  /// Get a profile by public key
  Future<NostrProfile?> getProfile(String pubkey) async {
    // Check cache first
    if (_profiles.containsKey(pubkey)) {
      return _profiles[pubkey];
    }
    
    // Check local storage
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
    
    // Fetch from relays
    return await fetchProfile(pubkey);
  }
  
  /// Fetch a profile from relays by public key
  Future<NostrProfile?> fetchProfile(String pubkey) async {
    // Create filter for metadata events from this user
    final filter = nostr.Filter(
      authors: [pubkey],
      kinds: [0], // Metadata kind
      limit: 1,
    );
    
    // Query multiple relays in parallel
    List<Future<List<nostr.Event>>> queries = [];
    for (final relay in _relayServices) {
      if (relay.isConnected) {
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 5)));
      }
    }
    
    if (queries.isEmpty) return null;
    
    final results = await Future.wait(queries);
    
    // Find the most recent metadata event
    nostr.Event? latestEvent;
    for (final events in results) {
      for (final event in events) {
        if (event.kind == 0) {
          if (latestEvent == null || event.createdAt > latestEvent.createdAt) {
            latestEvent = event;
          }
        }
      }
    }
    
    if (latestEvent != null) {
      try {
        final profile = NostrProfile.fromMetadataEvent(latestEvent.pubkey, latestEvent.content);
        
        // Debug logging for specific profile
        if (pubkey == '515b9246a72a47188ac60b7c4203f127accf210af53cc5db668c9ec6d2005497') {
          if (kDebugMode) {
            print('[ProfileServiceV2] Fetched profile 129aefr...:');
            print('  Raw content: ${latestEvent.content}');
            print('  Parsed picture: ${profile.picture}');
            print('  Parsed name: ${profile.name}');
            print('  Parsed displayName: ${profile.displayName}');
          }
        }
        
        // Save to cache and storage
        _profiles[pubkey] = profile;
        
        final profileBox = await Hive.openBox<String>('profiles');
        await profileBox.put(pubkey, jsonEncode(profile.toJson()));
        
        _profileStreamController.add(profile);
        return profile;
      } catch (e) {
        if (kDebugMode) {
          print('Error parsing profile: $e');
        }
      }
    }
    
    return null;
  }
  
  /// Fetch multiple profiles by public keys
  Future<List<NostrProfile>> fetchProfiles(List<String> pubkeys) async {
    List<NostrProfile> results = [];
    
    // Fetch profiles in parallel batches
    const batch = 10;
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
    final initialLimit = limit * 3;
    List<NostrProfile> candidateProfiles = [];
    List<NostrProfile> trustedProfiles = [];
    Set<String> seenPubkeys = {};
    
    // Create filter for metadata events
    final filter = nostr.Filter(
      kinds: [0], // Metadata kind
      limit: initialLimit,
    );
    
    // Query multiple relays in parallel
    List<Future<List<nostr.Event>>> queries = [];
    for (final relay in _relayServices) {
      if (relay.isConnected) {
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 15)));
      }
    }
    
    if (queries.isEmpty) return [];
    
    final results = await Future.wait(queries, eagerError: false);
    
    // Process results
    for (final events in results) {
      for (final event in events) {
        if (event.kind == 0 && !seenPubkeys.contains(event.pubkey)) {
          try {
            final profile = NostrProfile.fromMetadataEvent(event.pubkey, event.content);
            
            // Only add profiles with pictures
            if (profile.picture != null && profile.picture!.isNotEmpty) {
              candidateProfiles.add(profile);
              seenPubkeys.add(profile.pubkey);
              
              // Cache the profile
              _profiles[profile.pubkey] = profile;
              _saveProfileToStorage(profile);
              
              if (candidateProfiles.length >= initialLimit) break;
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error parsing profile: $e');
            }
          }
        }
      }
      if (candidateProfiles.length >= initialLimit) break;
    }
    
    // Filter by trust API
    await Future.wait(
      candidateProfiles.map((profile) async {
        if (await isProfileTrusted(profile.pubkey)) {
          trustedProfiles.add(profile);
        }
      })
    );
    
    if (kDebugMode) {
      print('Found ${trustedProfiles.length} trusted profiles out of ${candidateProfiles.length}');
    }
    
    return trustedProfiles.take(limit).toList();
  }
  
  /// Fetch recent text notes from a specific user
  Future<List<nostr.Event>> getUserNotes(String pubkey, {int limit = 10}) async {
    final filter = nostr.Filter(
      authors: [pubkey],
      kinds: [1], // Text note kind
      limit: limit,
    );
    
    List<Future<List<nostr.Event>>> queries = [];
    for (final relay in _relayServices) {
      if (relay.isConnected) {
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 5)));
      }
    }
    
    if (queries.isEmpty) return [];
    
    final results = await Future.wait(queries, eagerError: false);
    
    // Combine and deduplicate results
    final Map<String, nostr.Event> uniqueEvents = {};
    for (final events in results) {
      for (final event in events) {
        if (!uniqueEvents.containsKey(event.id) || 
            uniqueEvents[event.id]!.createdAt < event.createdAt) {
          uniqueEvents[event.id] = event;
        }
      }
    }
    
    // Sort by creation time (newest first)
    final sortedEvents = uniqueEvents.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    
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
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading followed profiles: $e');
      }
    }
  }
  
  /// Load contact list from relays for a specific user
  Future<void> loadContactListFromRelays(String userPubkey) async {
    final filter = nostr.Filter(
      authors: [userPubkey],
      kinds: [3], // Contact list kind
      limit: 1,
    );
    
    List<Future<List<nostr.Event>>> queries = [];
    for (final relay in _relayServices) {
      if (relay.isConnected) {
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 5)));
      }
    }
    
    if (queries.isEmpty) return;
    
    final results = await Future.wait(queries, eagerError: false);
    
    // Find the most recent contact list
    nostr.Event? latestContactList;
    for (final events in results) {
      for (final event in events) {
        if (event.kind == 3 && event.pubkey == userPubkey) {
          if (latestContactList == null || event.createdAt > latestContactList.createdAt) {
            latestContactList = event;
          }
        }
      }
    }
    
    if (latestContactList != null) {
      _followedProfiles.clear();
      
      // Extract pubkeys from 'p' tags
      for (final tag in latestContactList.tags) {
        if (tag.isNotEmpty && tag[0] == 'p' && tag.length >= 2) {
          _followedProfiles.add(tag[1]);
        }
      }
      
      await _saveFollowedProfiles();
      
      if (kDebugMode) {
        print('Loaded ${_followedProfiles.length} followed profiles from relays');
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
  
  /// Save a profile to storage
  Future<void> _saveProfileToStorage(NostrProfile profile) async {
    try {
      final profileBox = await Hive.openBox<String>('profiles');
      await profileBox.put(profile.pubkey, jsonEncode(profile.toJson()));
    } catch (e) {
      if (kDebugMode) {
        print('Error saving profile to storage: $e');
      }
    }
  }
  
  /// Check if a profile is followed
  bool isProfileFollowed(String pubkey) {
    return _followedProfiles.contains(pubkey);
  }
  
  /// Follow or unfollow a profile
  Future<bool> toggleFollowProfile(String pubkey, KeyManagementService keyService) async {
    final bool isCurrentlyFollowed = _followedProfiles.contains(pubkey);
    
    // Get the user's keychain
    final keychain = await keyService.getKeychain();
    if (keychain == null) {
      if (kDebugMode) {
        print('Cannot follow/unfollow: User not logged in');
      }
      return false;
    }
    
    // Toggle follow status
    if (isCurrentlyFollowed) {
      _followedProfiles.remove(pubkey);
    } else {
      _followedProfiles.add(pubkey);
    }
    
    await _saveFollowedProfiles();
    
    // Create contact list event
    try {
      // Create tags for followed profiles
      final List<List<String>> tags = _followedProfiles
          .map((followedPubkey) => ['p', followedPubkey])
          .toList();
      
      // Create the event using dart-nostr
      final event = nostr.Event.from(
        kind: 3, // Contact list kind
        tags: tags,
        content: '', // Contact lists typically have empty content
        privkey: keychain.private,
      );
      
      if (kDebugMode) {
        print('Publishing contact list event:');
        print('  Event ID: ${event.id}');
        print('  Following ${_followedProfiles.length} profiles');
      }
      
      // Publish to all connected relays
      int successCount = 0;
      for (final relay in _relayServices) {
        if (relay.isConnected) {
          final published = await relay.publishEvent(event);
          if (published) {
            successCount++;
            if (kDebugMode) {
              print('  Published to relay: ${relay.relayUrl}');
            }
          }
        }
      }
      
      if (kDebugMode) {
        print('Successfully published to $successCount/${_relayServices.length} relays');
      }
      
      return successCount > 0;
    } catch (e) {
      if (kDebugMode) {
        print('Error publishing follow event: $e');
      }
      return false;
    }
  }
  
  /// Dispose of resources
  void dispose() {
    for (final relay in _relayServices) {
      relay.dispose();
    }
    _relayServices.clear();
    _profileStreamController.close();
  }
}