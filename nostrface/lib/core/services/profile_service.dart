import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/nostr_relay_service.dart';
import 'package:hive/hive.dart';

/// Service for managing Nostr profile data
class ProfileService {
  final List<String> _relayUrls;
  final List<NostrRelayService> _relayServices = [];
  final Map<String, NostrProfile> _profiles = {};
  final StreamController<NostrProfile> _profileStreamController = StreamController<NostrProfile>.broadcast();
  
  ProfileService(this._relayUrls) {
    _initializeRelays();
  }
  
  Stream<NostrProfile> get profileStream => _profileStreamController.stream;
  
  /// Initialize connections to relays
  Future<void> _initializeRelays() async {
    for (final relayUrl in _relayUrls) {
      final relay = NostrRelayService(relayUrl);
      try {
        await relay.connect();
        _relayServices.add(relay);
        
        // Subscribe to profile updates
        relay.eventStream.listen((event) {
          if (event.kind == NostrEvent.metadataKind) {
            _handleProfileMetadata(event);
          }
        });
      } catch (e) {
        if (kDebugMode) {
          print('Failed to connect to relay $relayUrl: $e');
        }
      }
    }
  }
  
  /// Handle a profile metadata event (Kind 0)
  void _handleProfileMetadata(NostrEvent event) {
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
  Future<List<NostrProfile>> discoverProfiles({int limit = 10}) async {
    List<NostrProfile> discoveredProfiles = [];
    Set<String> seenPubkeys = {};
    
    // Build a filter for Kind 0 (metadata) events
    final filter = {
      'kinds': [NostrEvent.metadataKind],
      'limit': limit * 2, // Ask for more than we need in case some fail
    };
    
    // Query multiple relays in parallel
    List<Future<List<NostrEvent>>> queries = [];
    for (final relay in _relayServices) {
      if (relay.isConnected) {
        queries.add(relay.subscribe(filter, timeout: const Duration(seconds: 8)));
      }
    }
    
    final results = await Future.wait(queries);
    
    // Process the results
    for (final events in results) {
      for (final event in events) {
        if (event.kind == NostrEvent.metadataKind && !seenPubkeys.contains(event.pubkey)) {
          try {
            final profile = NostrProfile.fromMetadataEvent(event.pubkey, event.content);
            
            // Only add profiles with pictures for better UX
            if (profile.picture != null && profile.picture!.isNotEmpty) {
              discoveredProfiles.add(profile);
              seenPubkeys.add(profile.pubkey);
              
              // Cache the profile
              _profiles[profile.pubkey] = profile;
              
              // Save to storage
              try {
                final profileBox = await Hive.openBox<String>('profiles');
                await profileBox.put(profile.pubkey, jsonEncode(profile.toJson()));
              } catch (e) {
                if (kDebugMode) {
                  print('Error saving profile to storage: $e');
                }
              }
              
              if (discoveredProfiles.length >= limit) {
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
      
      if (discoveredProfiles.length >= limit) {
        break;
      }
    }
    
    return discoveredProfiles;
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