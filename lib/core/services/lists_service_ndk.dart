import 'dart:async';
import 'package:logging/logging.dart' as logging;
import 'package:ndk/ndk.dart';
import 'package:nostrface/core/services/ndk_service.dart';
import 'package:nostrface/core/services/ndk_event_signer.dart';

/// Service for handling NIP-51 lists (bookmarks, mute lists, etc.)
class ListsServiceNdk {
  final NdkService _ndkService;
  final NdkEventSigner _signer;
  final _logger = logging.Logger('ListsServiceNdk');
  
  // Cache for lists
  final Map<String, Nip51List> _listsCache = {};
  
  // Stream controllers
  final _listUpdatesController = StreamController<Nip51List>.broadcast();
  Stream<Nip51List> get listUpdates => _listUpdatesController.stream;

  ListsServiceNdk({
    required NdkService ndkService,
    required NdkEventSigner signer,
  }) : _ndkService = ndkService,
       _signer = signer;

  /// Get user's mute list
  Future<Nip51List?> getMuteList() async {
    return await _getList(Nip51List.kMute);
  }

  /// Get user's bookmark list
  Future<Nip51List?> getBookmarkList() async {
    return await _getList(Nip51List.kBookmarks);
  }

  /// Get user's pin list
  Future<Nip51List?> getPinList() async {
    return await _getList(Nip51List.kPin);
  }

  /// Get a specific list by kind
  Future<Nip51List?> _getList(int kind) async {
    try {
      final userPubkey = await _signer.getPublicKeyAsync();
      final cacheKey = '${userPubkey}_$kind';
      
      // Check cache
      if (_listsCache.containsKey(cacheKey)) {
        return _listsCache[cacheKey];
      }

      final filter = Filter(
        authors: [userPubkey],
        kinds: [kind],
        limit: 1,
      );

      final events = await _ndkService.queryEvents([filter]).toList();
      final event = events.isNotEmpty ? events.first : null;
      if (event != null) {
        final list = await Nip51List.fromEvent(event, _signer);
        _listsCache[cacheKey] = list;
        return list;
      }
      
      return null;
    } catch (e) {
      _logger.severe('Failed to get list kind $kind', e);
      return null;
    }
  }

  /// Add item to mute list
  Future<void> muteUser(String pubkey) async {
    await _addToList(
      kind: Nip51List.kMute,
      tagType: Nip51List.kPubkey,
      value: pubkey,
    );
  }

  /// Remove item from mute list
  Future<void> unmuteUser(String pubkey) async {
    await _removeFromList(
      kind: Nip51List.kMute,
      tagType: Nip51List.kPubkey,
      value: pubkey,
    );
  }

  /// Add event to bookmark list
  Future<void> bookmarkEvent(String eventId) async {
    await _addToList(
      kind: Nip51List.kBookmarks,
      tagType: Nip51List.kThread,
      value: eventId,
    );
  }

  /// Remove event from bookmark list
  Future<void> unbookmarkEvent(String eventId) async {
    await _removeFromList(
      kind: Nip51List.kBookmarks,
      tagType: Nip51List.kThread,
      value: eventId,
    );
  }

  /// Add event to pin list
  Future<void> pinEvent(String eventId) async {
    await _addToList(
      kind: Nip51List.kPin,
      tagType: Nip51List.kThread,
      value: eventId,
    );
  }

  /// Remove event from pin list
  Future<void> unpinEvent(String eventId) async {
    await _removeFromList(
      kind: Nip51List.kPin,
      tagType: Nip51List.kThread,
      value: eventId,
    );
  }

  /// Add item to a list
  Future<void> _addToList({
    required int kind,
    required String tagType,
    required String value,
  }) async {
    try {
      final userPubkey = await _signer.getPublicKeyAsync();
      
      // Get existing list or create new one
      var list = await _getList(kind) ?? Nip51List(
        pubKey: userPubkey,
        elements: [],
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: kind,
      );

      // Check if already in list
      if (list.elements.any((e) => e.tag == tagType && e.value == value)) {
        _logger.info('Item already in list');
        return;
      }

      // Add to list
      list.elements.add(Nip51ListElement(
        tag: tagType,
        value: value,
        private: false,
      ));
      
      // Create event from list
      final event = await _createEventFromList(list);

      // Sign and publish
      await _signer.sign(event);
      await _ndkService.publishEvent(event);

      // Update cache
      final cacheKey = '${userPubkey}_$kind';
      _listsCache[cacheKey] = list;
      _listUpdatesController.add(list);

      _logger.info('Added item to list kind $kind');
    } catch (e) {
      _logger.severe('Failed to add to list', e);
      rethrow;
    }
  }

  /// Remove item from a list
  Future<void> _removeFromList({
    required int kind,
    required String tagType,
    required String value,
  }) async {
    try {
      final userPubkey = await _signer.getPublicKeyAsync();
      
      // Get existing list
      final list = await _getList(kind);
      if (list == null) {
        _logger.info('List not found');
        return;
      }

      // Remove from list
      list.elements.removeWhere((e) => e.tag == tagType && e.value == value);
      
      // Create event from list
      final event = await _createEventFromList(list);

      // Sign and publish
      await _signer.sign(event);
      await _ndkService.publishEvent(event);

      // Update cache
      final cacheKey = '${userPubkey}_$kind';
      _listsCache[cacheKey] = list;
      _listUpdatesController.add(list);

      _logger.info('Removed item from list kind $kind');
    } catch (e) {
      _logger.severe('Failed to remove from list', e);
      rethrow;
    }
  }

  /// Create Nip01Event from Nip51List
  Future<Nip01Event> _createEventFromList(Nip51List list) async {
    // Build tags from elements
    final tags = list.elements
        .where((e) => !e.private)
        .map((e) => [e.tag, e.value])
        .toList();

    return Nip01Event(
      pubKey: list.pubKey,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      kind: list.kind,
      tags: tags,
      content: '', // TODO: Handle private elements with encryption
    );
  }

  /// Check if user is muted
  Future<bool> isUserMuted(String pubkey) async {
    final muteList = await getMuteList();
    if (muteList == null) return false;
    
    return muteList.pubKeys.any((element) => element.value == pubkey);
  }

  /// Check if event is bookmarked
  Future<bool> isEventBookmarked(String eventId) async {
    final bookmarkList = await getBookmarkList();
    if (bookmarkList == null) return false;
    
    return bookmarkList.threads.any((element) => element.value == eventId);
  }

  /// Get all muted users
  Future<List<String>> getMutedUsers() async {
    final muteList = await getMuteList();
    if (muteList == null) return [];
    
    return muteList.pubKeys.map((e) => e.value).toList();
  }

  /// Get all bookmarked events
  Future<List<String>> getBookmarkedEvents() async {
    final bookmarkList = await getBookmarkList();
    if (bookmarkList == null) return [];
    
    return bookmarkList.threads.map((e) => e.value).toList();
  }

  /// Clear cache
  void clearCache() {
    _listsCache.clear();
  }

  /// Dispose resources
  void dispose() {
    _listUpdatesController.close();
  }
}