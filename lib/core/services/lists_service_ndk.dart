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
    return await _getList(Nip51List.kMuteListKind);
  }

  /// Get user's bookmark list
  Future<Nip51List?> getBookmarkList() async {
    return await _getList(Nip51List.kPublicBookmarksListKind);
  }

  /// Get user's pin list
  Future<Nip51List?> getPinList() async {
    return await _getList(Nip51List.kPinListKind);
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

      final event = await _ndkService.queryEvents([filter]).firstOrNull;
      if (event != null) {
        final list = Nip51List.fromNip01Event(event);
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
      kind: Nip51List.kMuteListKind,
      tag: ['p', pubkey],
    );
  }

  /// Remove item from mute list
  Future<void> unmuteUser(String pubkey) async {
    await _removeFromList(
      kind: Nip51List.kMuteListKind,
      tag: ['p', pubkey],
    );
  }

  /// Add event to bookmark list
  Future<void> bookmarkEvent(String eventId) async {
    await _addToList(
      kind: Nip51List.kPublicBookmarksListKind,
      tag: ['e', eventId],
    );
  }

  /// Remove event from bookmark list
  Future<void> unbookmarkEvent(String eventId) async {
    await _removeFromList(
      kind: Nip51List.kPublicBookmarksListKind,
      tag: ['e', eventId],
    );
  }

  /// Add event to pin list
  Future<void> pinEvent(String eventId) async {
    await _addToList(
      kind: Nip51List.kPinListKind,
      tag: ['e', eventId],
    );
  }

  /// Remove event from pin list
  Future<void> unpinEvent(String eventId) async {
    await _removeFromList(
      kind: Nip51List.kPinListKind,
      tag: ['e', eventId],
    );
  }

  /// Add item to a list
  Future<void> _addToList({
    required int kind,
    required List<String> tag,
  }) async {
    try {
      final userPubkey = await _signer.getPublicKeyAsync();
      
      // Get existing list or create new one
      var list = await _getList(kind) ?? Nip51List(
        pubKey: userPubkey,
        tags: [],
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: kind,
      );

      // Check if already in list
      if (list.tags.any((t) => _tagsEqual(t, tag))) {
        _logger.info('Item already in list');
        return;
      }

      // Add to list
      final updatedTags = List<List<String>>.from(list.tags)..add(tag);
      
      // Create updated event
      final event = Nip01Event(
        pubKey: userPubkey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: kind,
        tags: updatedTags,
        content: '',
      );

      // Sign and publish
      final signedEvent = await _signer.sign(event);
      await _ndkService.publishEvent(signedEvent);

      // Update cache
      final updatedList = Nip51List.fromNip01Event(signedEvent);
      final cacheKey = '${userPubkey}_$kind';
      _listsCache[cacheKey] = updatedList;
      _listUpdatesController.add(updatedList);

      _logger.info('Added item to list kind $kind');
    } catch (e) {
      _logger.severe('Failed to add to list', e);
      rethrow;
    }
  }

  /// Remove item from a list
  Future<void> _removeFromList({
    required int kind,
    required List<String> tag,
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
      final updatedTags = List<List<String>>.from(list.tags)
        ..removeWhere((t) => _tagsEqual(t, tag));
      
      // Create updated event
      final event = Nip01Event(
        pubKey: userPubkey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: kind,
        tags: updatedTags,
        content: '',
      );

      // Sign and publish
      final signedEvent = await _signer.sign(event);
      await _ndkService.publishEvent(signedEvent);

      // Update cache
      final updatedList = Nip51List.fromNip01Event(signedEvent);
      final cacheKey = '${userPubkey}_$kind';
      _listsCache[cacheKey] = updatedList;
      _listUpdatesController.add(updatedList);

      _logger.info('Removed item from list kind $kind');
    } catch (e) {
      _logger.severe('Failed to remove from list', e);
      rethrow;
    }
  }

  /// Check if two tags are equal
  bool _tagsEqual(List<String> tag1, List<String> tag2) {
    if (tag1.length != tag2.length) return false;
    for (int i = 0; i < tag1.length; i++) {
      if (tag1[i] != tag2[i]) return false;
    }
    return true;
  }

  /// Check if user is muted
  Future<bool> isUserMuted(String pubkey) async {
    final muteList = await getMuteList();
    if (muteList == null) return false;
    
    return muteList.tags.any((tag) => 
      tag.length >= 2 && tag[0] == 'p' && tag[1] == pubkey
    );
  }

  /// Check if event is bookmarked
  Future<bool> isEventBookmarked(String eventId) async {
    final bookmarkList = await getBookmarkList();
    if (bookmarkList == null) return false;
    
    return bookmarkList.tags.any((tag) => 
      tag.length >= 2 && tag[0] == 'e' && tag[1] == eventId
    );
  }

  /// Get all muted users
  Future<List<String>> getMutedUsers() async {
    final muteList = await getMuteList();
    if (muteList == null) return [];
    
    return muteList.tags
        .where((tag) => tag.length >= 2 && tag[0] == 'p')
        .map((tag) => tag[1])
        .toList();
  }

  /// Get all bookmarked events
  Future<List<String>> getBookmarkedEvents() async {
    final bookmarkList = await getBookmarkList();
    if (bookmarkList == null) return [];
    
    return bookmarkList.tags
        .where((tag) => tag.length >= 2 && tag[0] == 'e')
        .map((tag) => tag[1])
        .toList();
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