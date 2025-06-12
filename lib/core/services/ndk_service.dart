import 'package:flutter/foundation.dart';
import 'package:ndk/ndk.dart';
import 'package:logging/logging.dart' as logging;

/// Centralized service for managing NDK instance
class NdkService {
  late final Ndk ndk;
  final _logger = logging.Logger('NdkService');
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// Initialize NDK with configuration
  Future<void> initialize() async {
    if (_isInitialized) {
      _logger.warning('NDK already initialized');
      return;
    }

    try {
      _logger.info('Initializing NDK...');
      
      ndk = Ndk(
        NdkConfig(
          // Use BIP340 verifier for now, can switch to Rust verifier later
          eventVerifier: Bip340EventVerifier(),
          
          // Start with in-memory cache
          cache: MemCacheManager(),
          
          // Configure bootstrap relays
          bootstrapRelays: [
            'wss://relay.damus.io',
            'wss://relay.nostr.band',
            'wss://nostr.wine',
            'wss://nos.lol',
            'wss://relay.primal.net',
          ],
        ),
      );

      _isInitialized = true;
      _logger.info('NDK initialized successfully');
    } catch (e, stackTrace) {
      _logger.severe('Failed to initialize NDK', e, stackTrace);
      rethrow;
    }
  }

  /// Dispose NDK resources
  void dispose() {
    if (_isInitialized) {
      // NDK doesn't have a dispose method, just mark as not initialized
      _isInitialized = false;
      _logger.info('NDK marked as disposed');
    }
  }

  /// Get metadata for a specific pubkey
  Future<Metadata?> getMetadata(String pubkey) async {
    if (!_isInitialized) {
      throw StateError('NDK not initialized');
    }
    
    return ndk.metadata.loadMetadata(pubkey);
  }

  /// Get metadata for multiple pubkeys
  Future<Map<String, Metadata>> getMetadataMultiple(List<String> pubkeys) async {
    if (!_isInitialized) {
      throw StateError('NDK not initialized');
    }
    
    final metadataMap = <String, Metadata>{};
    for (final pubkey in pubkeys) {
      final metadata = await ndk.metadata.loadMetadata(pubkey);
      if (metadata != null) {
        metadataMap[pubkey] = metadata;
      }
    }
    return metadataMap;
  }

  /// Query events with filters
  Stream<Nip01Event> queryEvents(List<Filter> filters) {
    if (!_isInitialized) {
      throw StateError('NDK not initialized');
    }
    
    final request = ndk.requests.query(filters: filters);
    return request.stream;
  }

  /// Subscribe to events with filters
  Stream<Nip01Event> subscribeToEvents(List<Filter> filters) {
    if (!_isInitialized) {
      throw StateError('NDK not initialized');
    }
    
    final subscription = ndk.requests.subscription(filters: filters);
    return subscription.stream;
  }

  /// Publish an event
  Future<void> publishEvent(Nip01Event event) async {
    if (!_isInitialized) {
      throw StateError('NDK not initialized');
    }
    
    // Use broadcast instance from ndk
    ndk.broadcast.broadcast(nostrEvent: event);
  }

  /// Get contact list for a pubkey
  Future<ContactList?> getContactList(String pubkey) async {
    if (!_isInitialized) {
      throw StateError('NDK not initialized');
    }
    
    try {
      final response = await ndk.requests.query(
        filters: [
          Filter(
            authors: [pubkey],
            kinds: [3], // Contact list kind
            limit: 1,
          ),
        ],
      ).stream.first;

      if (response != null) {
        return ContactList.fromEvent(response);
      }
      return null;
    } catch (e) {
      _logger.severe('Failed to fetch contact list', e);
      return null;
    }
  }

  /// Check if a pubkey is followed by another pubkey
  Future<bool> isFollowing(String followerPubkey, String followeePubkey) async {
    final contactList = await getContactList(followerPubkey);
    if (contactList == null) return false;
    
    return contactList.contacts.contains(followeePubkey);
  }
}