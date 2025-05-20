import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/message_encryption_service.dart';
import 'package:nostrface/core/services/nostr_relay_service.dart';

/// Service for handling direct messages
class DirectMessageService {
  final KeyManagementService _keyManagementService;
  final MessageEncryptionService _encryptionService;
  final List<String> _relayUrls;

  DirectMessageService(
    this._keyManagementService,
    this._encryptionService,
    this._relayUrls,
  );

  /// Send a direct message to a recipient
  /// Uses NIP-44 encryption for secure, metadata-protected messaging
  Future<bool> sendDirectMessage(String content, NostrProfile recipient) async {
    try {
      // Check if user is logged in
      final hasPrivateKey = await _keyManagementService.hasPrivateKey();
      if (!hasPrivateKey) {
        throw Exception('You must be logged in to send messages');
      }

      // Get sender's public key
      final senderPubkey = await _keyManagementService.getPublicKey();
      if (senderPubkey == null) {
        throw Exception('Unable to get sender public key');
      }

      // Encrypt the message content using NIP-44
      final encryptedContent = await _encryptionService.encryptMessage(
        content,
        recipient.pubkey,
      );

      // Create tags for the direct message
      // For NIP-44, we use 'p' tags for both sender and recipient
      // This allows for better privacy as relays can't determine who the sender is
      final List<List<dynamic>> tags = [
        ['p', recipient.pubkey],
      ];

      // Create the event data without the signature
      final eventData = {
        'pubkey': senderPubkey,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'kind': 4, // Kind 4 is for encrypted direct messages
        'tags': tags,
        'content': encryptedContent,
      };

      // Sign the event
      final signature = await _keyManagementService.signEvent(eventData);
      
      // Add the signature to the event
      eventData['sig'] = signature;
      
      // Create a Nostr event
      final event = NostrEvent.fromJson(eventData);

      // Publish the event to relays
      bool success = false;
      for (final relayUrl in _relayUrls) {
        try {
          final relayService = NostrRelayService(relayUrl);
          final published = await relayService.publishEvent(event);
          
          if (published) {
            success = true;
            if (kDebugMode) {
              print('Message published to relay: $relayUrl');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Failed to publish to relay $relayUrl: $e');
          }
          // Continue trying other relays
        }
      }

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('Error sending direct message: $e');
      }
      throw Exception('Failed to send message: $e');
    }
  }

  /// Get direct messages for the current user
  Future<List<NostrEvent>> getDirectMessages() async {
    try {
      final pubkey = await _keyManagementService.getPublicKey();
      if (pubkey == null) {
        throw Exception('No public key available');
      }

      final List<NostrEvent> allMessages = [];
      
      // Query relays for direct messages
      for (final relayUrl in _relayUrls) {
        try {
          final relayService = NostrRelayService(relayUrl);
          
          // Create a filter for direct messages received by the user
          // For direct messages (kind 4), look for events with a 'p' tag containing our pubkey
          final filter = {
            'kinds': [4], // Kind 4 for direct messages
            '#p': [pubkey], // Looking for messages addressed to us
          };
          
          // Subscribe to get events matching the filter
          final messages = await relayService.subscribe(
            filter,
            timeout: const Duration(seconds: 5),
          );
          
          // Add messages to the list, avoiding duplicates
          for (final message in messages) {
            if (!allMessages.any((m) => m.id == message.id)) {
              allMessages.add(message);
            }
          }
        } catch (e) {
          if (kDebugMode) {
            print('Failed to fetch messages from relay $relayUrl: $e');
          }
          // Continue with other relays
        }
      }
      
      // Sort messages by timestamp, newest first
      allMessages.sort((a, b) => b.created_at.compareTo(a.created_at));
      
      return allMessages;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching direct messages: $e');
      }
      return [];
    }
  }

  /// Decrypt a direct message
  Future<String?> decryptMessage(NostrEvent message) async {
    try {
      // Determine the sender pubkey
      final sender = message.pubkey;
      
      // Decrypt the content using NIP-44
      final decryptedContent = await _encryptionService.decryptMessage(
        message.content,
        sender,
      );
      
      return decryptedContent;
    } catch (e) {
      if (kDebugMode) {
        print('Error decrypting message ${message.id}: $e');
      }
      return null;
    }
  }
}

/// Provider for the direct message service
final directMessageServiceProvider = Provider<DirectMessageService>((ref) {
  final keyManagementService = ref.watch(keyManagementServiceProvider);
  final encryptionService = ref.watch(messageEncryptionServiceProvider);
  final relayUrls = ref.watch(defaultRelaysProvider);
  
  return DirectMessageService(
    keyManagementService,
    encryptionService,
    relayUrls,
  );
});

/// Provider for sending a direct message
final sendDirectMessageProvider = FutureProvider.family<bool, SendMessageParams>((ref, params) async {
  final directMessageService = ref.watch(directMessageServiceProvider);
  return await directMessageService.sendDirectMessage(params.content, params.recipient);
});

/// Parameters for sending a direct message
class SendMessageParams {
  final String content;
  final NostrProfile recipient;

  SendMessageParams({required this.content, required this.recipient});
}