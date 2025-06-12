import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart' as logging;
import 'package:ndk/ndk.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/models/ndk_adapters.dart';
import 'package:nostrface/core/services/ndk_service.dart';
import 'package:nostrface/core/services/ndk_event_signer.dart';

/// Profile service using NDK for all Nostr operations
class ProfileServiceNdk {
  final NdkService _ndkService;
  final NdkEventSigner _signer;
  final _logger = logging.Logger('ProfileServiceNdk');
  
  // Local cache using Hive
  late Box<Map> _profileBox;
  late Box<List> _followingBox;
  
  // In-memory caches
  final Map<String, NostrProfile> _profileCache = {};
  final Map<String, ContactList> _contactListCache = {};
  
  // Stream controllers
  final _profileUpdatesController = StreamController<NostrProfile>.broadcast();
  final _followingController = StreamController<Set<String>>.broadcast();
  
  Stream<NostrProfile> get profileUpdates => _profileUpdatesController.stream;
  Stream<Set<String>> get followingUpdates => _followingController.stream;

  ProfileServiceNdk({
    required NdkService ndkService,
    required NdkEventSigner signer,
  }) : _ndkService = ndkService,
       _signer = signer;

  /// Initialize the service
  Future<void> initialize() async {
    try {
      // Initialize Hive boxes
      _profileBox = await Hive.openBox<Map>('ndk_profiles');
      _followingBox = await Hive.openBox<List>('ndk_following');
      
      // Load cached data
      await _loadCachedProfiles();
      await _loadCachedFollowing();
      
      _logger.info('ProfileServiceNdk initialized');
    } catch (e) {
      _logger.severe('Failed to initialize ProfileServiceNdk', e);
      rethrow;
    }
  }

  /// Load cached profiles from Hive
  Future<void> _loadCachedProfiles() async {
    try {
      for (final key in _profileBox.keys) {
        final data = _profileBox.get(key);
        if (data != null) {
          final profile = NostrProfile.fromJson(Map<String, dynamic>.from(data));
          _profileCache[profile.pubkey] = profile;
        }
      }
      _logger.info('Loaded ${_profileCache.length} profiles from cache');
    } catch (e) {
      _logger.severe('Failed to load cached profiles', e);
    }
  }

  /// Load cached following list
  Future<void> _loadCachedFollowing() async {
    try {
      final userPubkey = await _signer.getPublicKeyAsync();
      final followingData = _followingBox.get(userPubkey);
      if (followingData != null) {
        final following = Set<String>.from(followingData);
        _followingController.add(following);
      }
    } catch (e) {
      _logger.severe('Failed to load cached following', e);
    }
  }

  /// Get profile by pubkey
  Future<NostrProfile?> getProfile(String pubkey) async {
    // Check cache first
    if (_profileCache.containsKey(pubkey)) {
      return _profileCache[pubkey];
    }

    try {
      // Fetch from NDK
      final metadata = await _ndkService.getMetadata(pubkey);
      if (metadata != null) {
        final profile = NostrProfileAdapter.fromMetadata(metadata);
        await _cacheProfile(profile);
        return profile;
      }
    } catch (e) {
      _logger.severe('Failed to fetch profile for $pubkey', e);
    }

    return null;
  }

  /// Get multiple profiles
  Future<List<NostrProfile>> getProfiles(List<String> pubkeys) async {
    final profiles = <NostrProfile>[];
    final uncachedPubkeys = <String>[];

    // Get cached profiles
    for (final pubkey in pubkeys) {
      if (_profileCache.containsKey(pubkey)) {
        profiles.add(_profileCache[pubkey]!);
      } else {
        uncachedPubkeys.add(pubkey);
      }
    }

    // Fetch uncached profiles
    if (uncachedPubkeys.isNotEmpty) {
      try {
        final metadataMap = await _ndkService.getMetadataMultiple(uncachedPubkeys);
        
        for (final entry in metadataMap.entries) {
          final profile = NostrProfileAdapter.fromMetadata(entry.value);
          profiles.add(profile);
          await _cacheProfile(profile);
        }
      } catch (e) {
        _logger.severe('Failed to fetch profiles', e);
      }
    }

    return profiles;
  }

  /// Stream profiles for discovery
  Stream<NostrProfile> streamProfiles({
    int limit = 100,
    Duration? since,
  }) async* {
    final filter = Filter(
      kinds: [0], // Metadata events
      limit: limit,
      since: since?.inSeconds ?? DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000,
    );

    await for (final event in _ndkService.queryEvents([filter])) {
      try {
        final profile = NostrProfileAdapter.fromMetadataEvent(event);
        // Only yield if has picture
        if (profile.picture != null && profile.picture!.isNotEmpty) {
          await _cacheProfile(profile);
          yield profile;
        }
      } catch (e) {
        // Skip invalid profiles
        if (kDebugMode) {
          print('Failed to parse profile: $e');
        }
      }
    }
  }

  /// Get contact list for current user
  Future<ContactList?> getContactList() async {
    try {
      final userPubkey = await _signer.getPublicKeyAsync();
      return await _ndkService.getContactList(userPubkey);
    } catch (e) {
      _logger.severe('Failed to get contact list', e);
      return null;
    }
  }

  /// Get following list for current user
  Future<Set<String>> getFollowing() async {
    final contactList = await getContactList();
    if (contactList != null) {
      final following = contactList.followedPubkeys.toSet();
      _followingController.add(following);
      
      // Cache following list
      final userPubkey = await _signer.getPublicKeyAsync();
      await _followingBox.put(userPubkey, following.toList());
      
      return following;
    }
    return {};
  }

  /// Check if current user is following a pubkey
  Future<bool> isFollowing(String pubkey) async {
    final following = await getFollowing();
    return following.contains(pubkey);
  }

  /// Toggle follow status
  Future<void> toggleFollowProfile(String pubkey) async {
    try {
      final userPubkey = await _signer.getPublicKeyAsync();
      var contactList = await getContactList() ?? ContactList(
        pubKey: userPubkey,
        contacts: [],
      );

      // Toggle follow status
      if (contactList.isFollowing(pubkey)) {
        contactList = contactList.removeContact(pubkey);
        _logger.info('Unfollowing $pubkey');
      } else {
        contactList = contactList.addContact(pubkey);
        _logger.info('Following $pubkey');
      }

      // Create and publish the event
      final event = contactList.toEvent(_signer);
      await _signer.sign(event);
      await _ndkService.publishEvent(event);

      // Update local cache
      _contactListCache[userPubkey] = contactList;
      final following = contactList.followedPubkeys.toSet();
      _followingController.add(following);
      await _followingBox.put(userPubkey, following.toList());

    } catch (e) {
      _logger.severe('Failed to toggle follow for $pubkey', e);
      rethrow;
    }
  }

  /// Update user profile
  Future<void> updateProfile(NostrProfile profile) async {
    try {
      final userPubkey = await _signer.getPublicKeyAsync();
      if (profile.pubkey != userPubkey) {
        throw Exception('Can only update own profile');
      }

      // Create metadata event
      final metadata = NostrProfileAdapter.toMetadata(profile);
      final event = metadata.toEvent();
      
      // Sign and publish
      await _signer.sign(event);
      await _ndkService.publishEvent(event);

      // Update cache
      await _cacheProfile(profile);
      _profileUpdatesController.add(profile);

    } catch (e) {
      _logger.severe('Failed to update profile', e);
      rethrow;
    }
  }

  /// Cache profile
  Future<void> _cacheProfile(NostrProfile profile) async {
    _profileCache[profile.pubkey] = profile;
    await _profileBox.put(profile.pubkey, profile.toJson());
    _profileUpdatesController.add(profile);
  }

  /// Clear all caches
  Future<void> clearCache() async {
    _profileCache.clear();
    _contactListCache.clear();
    await _profileBox.clear();
    await _followingBox.clear();
  }

  /// Dispose resources
  void dispose() {
    _profileUpdatesController.close();
    _followingController.close();
  }
}