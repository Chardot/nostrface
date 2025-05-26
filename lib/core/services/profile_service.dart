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
  
  // Cache service for notes
  final NoteCacheService _noteCacheService = NoteCacheService();
  
  
  ProfileService(this._relayUrls) {
    _initializeRelays();
    _loadFollowedProfiles();
  }
  
  
  Stream<NostrProfile> get profileStream => _profileStreamController.stream;
  Set<String> get followedProfiles => _followedProfiles;
  
  /// Get the relay URLs for connecting to Nostr network
  List<String> get relayUrls => List.unmodifiable(_relayUrls);
  
  
  /// Initialize relay connections from a list of URLs
  Future<void> _initializeRelaysFromUrls(List<String> urls) async {
    if (kDebugMode) {
      print('Initializing connections to ${urls.length} relays');
    }
    
    // In web, we'll try to connect to all relays, but use a timeout to avoid waiting too long
    final connectFutures = urls.map((relayUrl) async {
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
      print('Connected to $connectedCount out of ${urls.length} relays');
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
  Future<List<NostrProfile>> discoverProfiles({int limit = 10, DiscardedProfilesService? discardedService}) async {
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
                  
                  // Only consider profiles with pictures and not discarded
                  if (profile.picture != null && profile.picture!.isNotEmpty) {
                    // Check if profile is discarded
                    if (discardedService == null || !discardedService.isDiscarded(profile.pubkey)) {
                      candidateProfiles.add(profile);
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
            
            // Only add profiles with pictures for better UX and not discarded
            if (profile.picture != null && profile.picture!.isNotEmpty) {
              // Check if profile is discarded
              if (discardedService == null || !discardedService.isDiscarded(profile.pubkey)) {
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
    
    // Return profiles without trust filtering
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
  
  /// Load the list of followed profiles from local storage
  Future<void> _loadFollowedProfiles() async {
    try {
      final followedBox = await Hive.openBox<String>('followed_profiles');
      final followed = followedBox.get('followed_list');
      
      if (followed != null) {
        final List<dynamic> followedList = jsonDecode(followed);
        _followedProfiles.addAll(followedList.cast<String>());
        
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
      if (kDebugMode) {
        print('No connected relays to query for contact list');
      }
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
  
  /// Follow or unfollow a profile
  Future<RelayPublishResult> toggleFollowProfile(String pubkey, KeyManagementService keyService) async {
    final bool isCurrentlyFollowed = _followedProfiles.contains(pubkey);
    
    // Check if user is logged in
    final String? currentUserPubkey = await keyService.getPublicKey();
    if (currentUserPubkey == null) {
      if (kDebugMode) {
        print('Cannot follow/unfollow: User not logged in');
      }
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
    
    // Create and publish a contact list event
    try {
      // Get the user's keychain for signing
      final keychain = await keyService.getKeychain();
      if (keychain == null) {
        if (kDebugMode) {
          print('Cannot create contact list: No keychain available');
        }
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
      
      if (kDebugMode) {
        print('Publishing contact list event:');
        print('  Event ID: ${nostrEvent.id}');
        print('  Following ${_followedProfiles.length} profiles');
        print('  Tags: ${tags.length} profiles');
      }
      
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
            if (kDebugMode) {
              print('  ❌ Failed to publish to relay: ${relay.relayUrl}');
            }
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
    } catch (e) {
      if (kDebugMode) {
        print('Error publishing follow event: $e');
      }
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

final isProfileFollowedProvider = Provider.family<bool, String>((ref, pubkey) {
  final profileService = ref.watch(profileServiceProvider);
  return profileService.isProfileFollowed(pubkey);
});

final followProfileProvider = FutureProvider.family<RelayPublishResult, String>((ref, pubkey) async {
  final profileService = ref.watch(profileServiceProvider);
  final keyService = ref.watch(keyManagementServiceProvider);
  return await profileService.toggleFollowProfile(pubkey, keyService);
});

/// Service for managing a buffer of profiles
class ProfileBufferService {
  final ProfileService _profileService;
  final DiscardedProfilesService? _discardedService;
  
  // Configuration for progressive loading
  static const int _initialLoadCount = 5;
  static const int _batchLoadCount = 10;
  static const int _prefetchThreshold = 3; // Start loading more when 3 profiles remain
  
  // This list will persist in memory as long as the app is running
  final List<NostrProfile> _profileBuffer = [];
  bool _isFetching = false;
  bool _isLoadingInitial = false;
  
  // Track the last viewed index to restore position
  int _lastViewedIndex = 0;
  
  // Persist the buffer state
  bool _hasInitializedBuffer = false;
  
  final StreamController<List<NostrProfile>> _bufferStreamController = 
      StreamController<List<NostrProfile>>.broadcast();
  
  ProfileBufferService(this._profileService, [this._discardedService]) {
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
      if (kDebugMode) {
        print('Loading initial $_initialLoadCount profiles...');
      }
      
      // Fetch initial profiles
      final initialProfiles = await _profileService.discoverProfiles(
        limit: _initialLoadCount,
        discardedService: _discardedService,
      );
      
      if (initialProfiles.isNotEmpty) {
        _profileBuffer.addAll(initialProfiles);
        _hasInitializedBuffer = true;
        _notifyListeners();
        
        if (kDebugMode) {
          print('Loaded ${initialProfiles.length} initial profiles');
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
        print('Loading $_batchLoadCount more profiles in background...');
      }
      
      // Fetch new profiles
      final newProfiles = await _profileService.discoverProfiles(
        limit: _batchLoadCount,
        discardedService: _discardedService,
      );
      
      // Filter out profiles that are already in the buffer
      final existingPubkeys = _profileBuffer.map((p) => p.pubkey).toSet();
      final uniqueNewProfiles = newProfiles
          .where((profile) => !existingPubkeys.contains(profile.pubkey))
          .toList();
        
      if (uniqueNewProfiles.isNotEmpty) {
        // Add to buffer
        _profileBuffer.addAll(uniqueNewProfiles);
        _notifyListeners();
        
        if (kDebugMode) {
          print('Added ${uniqueNewProfiles.length} profiles to buffer. Total: ${_profileBuffer.length}');
        }
        
        // Continue loading more profiles in background
        // Short delay to avoid overloading relays
        await Future.delayed(const Duration(seconds: 1));
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
  
  /// Check if we need to prefetch more profiles
  void checkBufferState(int currentIndex) {
    // Update last viewed index
    _lastViewedIndex = currentIndex;
    
    // If we're approaching the end of the buffer, fetch more profiles
    if (!_isFetching && 
        _profileBuffer.isNotEmpty && 
        currentIndex >= _profileBuffer.length - _prefetchThreshold) {
      if (kDebugMode) {
        print('User at index $currentIndex, loading more profiles...');
      }
      _loadMoreProfiles();
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
    _notifyListeners();
    
    // Check if we need to load more profiles
    if (_profileBuffer.length < _prefetchThreshold * 2) {
      _loadMoreProfiles();
    }
  }
  
  /// Refresh the entire buffer (e.g., when user pulls to refresh)
  Future<void> refreshBuffer() async {
    // Clear the buffer but keep track of initialization state
    _profileBuffer.clear();
    _notifyListeners();
    
    // Force re-fetching of profiles by temporarily resetting the initialized flag
    _hasInitializedBuffer = false;
    _isFetching = false;
    _isLoadingInitial = false;
    
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
  
  static ProfileBufferService getInstance(ProfileService profileService, DiscardedProfilesService? discardedService) {
    _instance ??= ProfileBufferService(profileService, discardedService);
    return _instance!;
  }
}

/// Provider for the profile buffer service
final profileBufferServiceProvider = Provider<ProfileBufferService>((ref) {
  final profileService = ref.watch(profileServiceProvider);
  final discardedService = ref.watch(discardedProfilesServiceProvider);
  // Use singleton pattern to ensure same instance persists
  return ProfileBufferServiceSingleton.getInstance(profileService, discardedService);
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