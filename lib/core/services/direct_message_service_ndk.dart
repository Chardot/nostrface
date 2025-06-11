import 'dart:async';
import 'package:logging/logging.dart';
import 'package:ndk/ndk.dart';
import 'package:nostrface/core/services/ndk_service.dart';
import 'package:nostrface/core/services/ndk_event_signer.dart';
import 'package:nostr/nostr.dart' as old_nostr;

/// Direct message service using NDK
class DirectMessageServiceNdk {
  final NdkService _ndkService;
  final NdkEventSigner _signer;
  final _logger = Logger('DirectMessageServiceNdk');
  
  // Message stream controller
  final _messageController = StreamController<DirectMessage>.broadcast();
  Stream<DirectMessage> get messageStream => _messageController.stream;
  
  // Active subscriptions
  final Map<String, StreamSubscription> _subscriptions = {};

  DirectMessageServiceNdk({
    required NdkService ndkService,
    required NdkEventSigner signer,
  }) : _ndkService = ndkService,
       _signer = signer;

  /// Send a direct message
  Future<void> sendMessage({
    required String recipientPubkey,
    required String content,
  }) async {
    try {
      final senderPubkey = await _signer.getPublicKey();
      final senderPrivkey = await _getPrivateKey();
      
      // Use NIP-04 encryption for now (NIP-44 support coming)
      final encrypted = await _encryptMessage(
        content,
        recipientPubkey,
        senderPrivkey,
      );

      // Create DM event
      final event = Nip01Event(
        pubkey: senderPubkey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        kind: 4, // Encrypted DM kind
        tags: [['p', recipientPubkey]],
        content: encrypted,
      );

      // Sign and publish
      final signedEvent = await _signer.sign(event);
      await _ndkService.publishEvent(signedEvent);

      // Add to stream
      _messageController.add(DirectMessage(
        id: signedEvent.id,
        senderPubkey: senderPubkey,
        recipientPubkey: recipientPubkey,
        content: content,
        encryptedContent: encrypted,
        createdAt: signedEvent.createdAt,
        isOutgoing: true,
      ));

      _logger.info('Sent DM to $recipientPubkey');
    } catch (e) {
      _logger.severe('Failed to send message', e);
      rethrow;
    }
  }

  /// Subscribe to direct messages
  Future<void> subscribeToMessages() async {
    try {
      final userPubkey = await _signer.getPublicKey();
      
      // Subscribe to incoming DMs
      final incomingFilter = Filter(
        kinds: [4], // Encrypted DM kind
        tags: {'p': [userPubkey]}, // Messages sent to us
        since: DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
      );

      // Subscribe to outgoing DMs
      final outgoingFilter = Filter(
        kinds: [4],
        authors: [userPubkey], // Messages sent by us
        since: DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
      );

      // Cancel existing subscriptions
      await _cancelSubscriptions();

      // Create new subscriptions
      _subscriptions['incoming'] = _ndkService
          .subscribeToEvents([incomingFilter])
          .listen((event) => _handleIncomingMessage(event, false));

      _subscriptions['outgoing'] = _ndkService
          .subscribeToEvents([outgoingFilter])
          .listen((event) => _handleIncomingMessage(event, true));

      _logger.info('Subscribed to direct messages');
    } catch (e) {
      _logger.severe('Failed to subscribe to messages', e);
      rethrow;
    }
  }

  /// Handle incoming message event
  Future<void> _handleIncomingMessage(Nip01Event event, bool isOutgoing) async {
    try {
      final userPubkey = await _signer.getPublicKey();
      final userPrivkey = await _getPrivateKey();
      
      String senderPubkey;
      String recipientPubkey;
      String? decryptedContent;

      if (isOutgoing) {
        senderPubkey = userPubkey;
        // Get recipient from p tag
        final pTag = event.tags.firstWhere(
          (tag) => tag.isNotEmpty && tag[0] == 'p',
          orElse: () => [],
        );
        if (pTag.length < 2) return;
        recipientPubkey = pTag[1];
        
        // Decrypt using recipient's pubkey
        decryptedContent = await _decryptMessage(
          event.content,
          recipientPubkey,
          userPrivkey,
        );
      } else {
        senderPubkey = event.pubkey;
        recipientPubkey = userPubkey;
        
        // Decrypt using sender's pubkey
        decryptedContent = await _decryptMessage(
          event.content,
          senderPubkey,
          userPrivkey,
        );
      }

      if (decryptedContent != null) {
        final message = DirectMessage(
          id: event.id,
          senderPubkey: senderPubkey,
          recipientPubkey: recipientPubkey,
          content: decryptedContent,
          encryptedContent: event.content,
          createdAt: event.createdAt,
          isOutgoing: isOutgoing,
        );

        _messageController.add(message);
      }
    } catch (e) {
      _logger.warning('Failed to handle message: $e');
    }
  }

  /// Get message history with a specific pubkey
  Future<List<DirectMessage>> getMessageHistory(String pubkey) async {
    try {
      final userPubkey = await _signer.getPublicKey();
      final messages = <DirectMessage>[];

      // Get messages sent to the user from this pubkey
      final incomingFilter = Filter(
        kinds: [4],
        authors: [pubkey],
        tags: {'p': [userPubkey]},
        limit: 100,
      );

      // Get messages sent by the user to this pubkey
      final outgoingFilter = Filter(
        kinds: [4],
        authors: [userPubkey],
        tags: {'p': [pubkey]},
        limit: 100,
      );

      // Fetch messages
      final incomingEvents = await _ndkService.queryEvents([incomingFilter]).toList();
      final outgoingEvents = await _ndkService.queryEvents([outgoingFilter]).toList();

      // Process incoming messages
      for (final event in incomingEvents) {
        await _handleIncomingMessage(event, false);
      }

      // Process outgoing messages
      for (final event in outgoingEvents) {
        await _handleIncomingMessage(event, true);
      }

      // Sort by timestamp
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      return messages;
    } catch (e) {
      _logger.severe('Failed to get message history', e);
      rethrow;
    }
  }

  /// Encrypt message using NIP-04
  Future<String> _encryptMessage(
    String content,
    String recipientPubkey,
    String senderPrivkey,
  ) async {
    // Use old nostr library for NIP-04 encryption (temporary)
    final encrypted = old_nostr.Nip04.encrypt(
      senderPrivkey,
      recipientPubkey,
      content,
    );
    return encrypted;
  }

  /// Decrypt message using NIP-04
  Future<String?> _decryptMessage(
    String encryptedContent,
    String senderPubkey,
    String recipientPrivkey,
  ) async {
    try {
      // Use old nostr library for NIP-04 decryption (temporary)
      final decrypted = old_nostr.Nip04.decrypt(
        recipientPrivkey,
        senderPubkey,
        encryptedContent,
      );
      return decrypted;
    } catch (e) {
      _logger.warning('Failed to decrypt message: $e');
      return null;
    }
  }

  /// Get private key from signer
  Future<String> _getPrivateKey() async {
    // This is a temporary workaround - in production, use NDK's encryption
    // For now, we need to access the private key directly
    throw UnimplementedError('Need to implement private key access for encryption');
  }

  /// Cancel all subscriptions
  Future<void> _cancelSubscriptions() async {
    for (final subscription in _subscriptions.values) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }

  /// Dispose resources
  void dispose() {
    _cancelSubscriptions();
    _messageController.close();
  }
}

/// Direct message model
class DirectMessage {
  final String id;
  final String senderPubkey;
  final String recipientPubkey;
  final String content;
  final String encryptedContent;
  final int createdAt;
  final bool isOutgoing;

  DirectMessage({
    required this.id,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.content,
    required this.encryptedContent,
    required this.createdAt,
    required this.isOutgoing,
  });

  DateTime get timestamp => DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
}