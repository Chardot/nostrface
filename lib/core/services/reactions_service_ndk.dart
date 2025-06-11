import 'dart:async';
import 'package:logging/logging.dart';
import 'package:ndk/ndk.dart';
import 'package:nostrface/core/services/ndk_service.dart';
import 'package:nostrface/core/services/ndk_event_signer.dart';

/// Service for handling reactions (NIP-25)
class ReactionsServiceNdk {
  final NdkService _ndkService;
  final NdkEventSigner _signer;
  final _logger = Logger('ReactionsServiceNdk');
  
  // Cache for reactions
  final Map<String, List<Reaction>> _reactionsCache = {};
  
  // Stream controller for reaction updates
  final _reactionUpdatesController = StreamController<ReactionUpdate>.broadcast();
  Stream<ReactionUpdate> get reactionUpdates => _reactionUpdatesController.stream;

  ReactionsServiceNdk({
    required NdkService ndkService,
    required NdkEventSigner signer,
  }) : _ndkService = ndkService,
       _signer = signer;

  /// Add a reaction to an event
  Future<void> addReaction({
    required String eventId,
    required String reaction,
  }) async {
    try {
      final userPubkey = await _signer.getPublicKey();
      
      // Create reaction event (kind 7)
      final event = Nip01Event(
        pubkey: userPubkey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 7, // Reaction kind
        tags: [
          ['e', eventId],
        ],
        content: reaction,
      );

      // Sign and publish
      final signedEvent = await _signer.sign(event);
      await _ndkService.publishEvent(signedEvent);

      // Update cache
      final reactionObj = Reaction(
        id: signedEvent.id,
        pubkey: userPubkey,
        eventId: eventId,
        reaction: reaction,
        createdAt: signedEvent.createdAt,
      );
      
      _addToCache(eventId, reactionObj);
      _reactionUpdatesController.add(ReactionUpdate(
        eventId: eventId,
        reaction: reactionObj,
        isAdded: true,
      ));

      _logger.info('Added reaction "$reaction" to event $eventId');
    } catch (e) {
      _logger.severe('Failed to add reaction', e);
      rethrow;
    }
  }

  /// Remove a reaction from an event
  Future<void> removeReaction({
    required String reactionEventId,
  }) async {
    try {
      final userPubkey = await _signer.getPublicKey();
      
      // Create deletion event (kind 5)
      final event = Nip01Event(
        pubkey: userPubkey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 5, // Deletion kind
        tags: [
          ['e', reactionEventId],
        ],
        content: 'Removed reaction',
      );

      // Sign and publish
      final signedEvent = await _signer.sign(event);
      await _ndkService.publishEvent(signedEvent);

      _logger.info('Removed reaction $reactionEventId');
    } catch (e) {
      _logger.severe('Failed to remove reaction', e);
      rethrow;
    }
  }

  /// Get reactions for an event
  Future<List<Reaction>> getReactions(String eventId) async {
    // Check cache first
    if (_reactionsCache.containsKey(eventId)) {
      return _reactionsCache[eventId]!;
    }

    try {
      final filter = Filter(
        kinds: [7], // Reaction kind
        tags: {'e': [eventId]},
        limit: 100,
      );

      final reactions = <Reaction>[];
      await for (final event in _ndkService.queryEvents([filter])) {
        final reaction = Reaction(
          id: event.id,
          pubkey: event.pubkey,
          eventId: eventId,
          reaction: event.content,
          createdAt: event.createdAt,
        );
        reactions.add(reaction);
      }

      // Cache results
      _reactionsCache[eventId] = reactions;
      return reactions;
    } catch (e) {
      _logger.severe('Failed to get reactions for $eventId', e);
      rethrow;
    }
  }

  /// Subscribe to reactions for an event
  Stream<Reaction> subscribeToReactions(String eventId) {
    final filter = Filter(
      kinds: [7], // Reaction kind
      tags: {'e': [eventId]},
    );

    return _ndkService.subscribeToEvents([filter]).map((event) {
      final reaction = Reaction(
        id: event.id,
        pubkey: event.pubkey,
        eventId: eventId,
        reaction: event.content,
        createdAt: event.createdAt,
      );
      
      _addToCache(eventId, reaction);
      _reactionUpdatesController.add(ReactionUpdate(
        eventId: eventId,
        reaction: reaction,
        isAdded: true,
      ));
      
      return reaction;
    });
  }

  /// Get reaction summary for an event
  Future<ReactionSummary> getReactionSummary(String eventId) async {
    final reactions = await getReactions(eventId);
    final summary = <String, int>{};
    
    for (final reaction in reactions) {
      summary[reaction.reaction] = (summary[reaction.reaction] ?? 0) + 1;
    }
    
    return ReactionSummary(
      eventId: eventId,
      totalCount: reactions.length,
      reactions: summary,
    );
  }

  void _addToCache(String eventId, Reaction reaction) {
    if (!_reactionsCache.containsKey(eventId)) {
      _reactionsCache[eventId] = [];
    }
    
    // Avoid duplicates
    final existing = _reactionsCache[eventId]!;
    if (!existing.any((r) => r.id == reaction.id)) {
      existing.add(reaction);
    }
  }

  /// Clear cache
  void clearCache() {
    _reactionsCache.clear();
  }

  /// Dispose resources
  void dispose() {
    _reactionUpdatesController.close();
  }
}

/// Reaction model
class Reaction {
  final String id;
  final String pubkey;
  final String eventId;
  final String reaction;
  final int createdAt;

  Reaction({
    required this.id,
    required this.pubkey,
    required this.eventId,
    required this.reaction,
    required this.createdAt,
  });

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
}

/// Reaction update event
class ReactionUpdate {
  final String eventId;
  final Reaction reaction;
  final bool isAdded;

  ReactionUpdate({
    required this.eventId,
    required this.reaction,
    required this.isAdded,
  });
}

/// Reaction summary
class ReactionSummary {
  final String eventId;
  final int totalCount;
  final Map<String, int> reactions;

  ReactionSummary({
    required this.eventId,
    required this.totalCount,
    required this.reactions,
  });
}