import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/utils/nostr_legacy_support.dart' as nostr;
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/message_encryption_service.dart';
import 'package:nostrface/core/services/nostr_relay_service_v2.dart';
import 'package:nostrface/core/providers/app_providers.dart';

/// Service for handling direct messages using dart-nostr
class DirectMessageServiceV2 {
  final KeyManagementService _keyManagementService;
  final MessageEncryptionService _encryptionService;
  final List<String> _relayUrls;

  DirectMessageServiceV2({
    required KeyManagementService keyManagementService,
    required MessageEncryptionService encryptionService,
    required List<String> relayUrls,
  })  : _keyManagementService = keyManagementService,
        _encryptionService = encryptionService,
        _relayUrls = relayUrls;

  /// Send a direct message to another user
  Future<bool> sendMessage({
    required String content,
    required NostrProfile recipient,
  }) async {
    try {
      // Get the user's keychain
      final keychain = await _keyManagementService.getKeychain();
      if (keychain == null) {
        throw Exception('User not logged in');
      }

      // Encrypt the message using NIP-44
      final encryptedContent = await _encryptionService.encryptMessage(
        content,
        recipient.pubkey,
      );

      // Create tags for the direct message
      final List<List<String>> tags = [
        ['p', recipient.pubkey],
      ];

      // Create the event using dart-nostr
      final event = nostr.Event.from(
        kind: 4, // Kind 4 is for encrypted direct messages
        tags: tags,
        content: encryptedContent,
        privkey: keychain.private,
      );

      if (kDebugMode) {
        print('Sending encrypted message:');
        print('  Event ID: ${event.id}');
        print('  To: ${recipient.displayNameOrName} (${recipient.pubkey.substring(0, 8)}...)');
      }

      // Publish to relays
      bool success = false;
      for (final relayUrl in _relayUrls) {
        try {
          final relayService = NostrRelayServiceV2(relayUrl);
          final connected = await relayService.connect();
          
          if (connected) {
            final published = await relayService.publishEvent(event);
            
            if (published) {
              success = true;
              if (kDebugMode) {
                print('  Message published to relay: $relayUrl');
              }
            }
            
            // Clean up connection
            relayService.disconnect();
          }
        } catch (e) {
          if (kDebugMode) {
            print('  Error publishing to relay $relayUrl: $e');
          }
        }
      }

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('Error sending message: $e');
      }
      return false;
    }
  }

  /// Fetch direct messages between the current user and another user
  Future<List<DirectMessage>> fetchMessages({
    required String otherUserPubkey,
    int limit = 50,
  }) async {
    try {
      // Get current user's public key
      final currentUserPubkey = await _keyManagementService.getPublicKey();
      if (currentUserPubkey == null) {
        throw Exception('User not logged in');
      }

      // Create filters for messages in both directions
      final sentFilter = nostr.Filter(
        authors: [currentUserPubkey],
        kinds: [4], // Direct messages
        limit: limit,
      );

      final receivedFilter = nostr.Filter(
        authors: [otherUserPubkey],
        kinds: [4], // Direct messages
        limit: limit,
      );

      List<nostr.Event> allMessages = [];

      // Query relays
      for (final relayUrl in _relayUrls) {
        try {
          final relay = NostrRelayServiceV2(relayUrl);
          final connected = await relay.connect();
          
          if (connected) {
            // Get sent messages
            final sentMessages = await relay.subscribe(
              sentFilter, 
              timeout: const Duration(seconds: 5),
            );
            
            // Get received messages
            final receivedMessages = await relay.subscribe(
              receivedFilter,
              timeout: const Duration(seconds: 5),
            );
            
            allMessages.addAll(sentMessages);
            allMessages.addAll(receivedMessages);
            
            relay.disconnect();
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error fetching from relay $relayUrl: $e');
          }
        }
      }

      // Filter and decrypt messages
      List<DirectMessage> directMessages = [];
      
      for (final event in allMessages) {
        // Check if message involves the other user
        bool involvesOtherUser = false;
        
        for (final tag in event.tags) {
          if (tag.length >= 2 && tag[0] == 'p' && tag[1] == otherUserPubkey) {
            involvesOtherUser = true;
            break;
          }
        }
        
        if (!involvesOtherUser && event.pubkey != otherUserPubkey) {
          continue;
        }

        try {
          // Decrypt the message
          final decryptedContent = await _encryptionService.decryptMessage(
            event.content,
            event.pubkey == currentUserPubkey ? otherUserPubkey : event.pubkey,
          );

          directMessages.add(DirectMessage(
            id: event.id,
            senderPubkey: event.pubkey,
            recipientPubkey: event.pubkey == currentUserPubkey ? otherUserPubkey : currentUserPubkey,
            content: decryptedContent,
            timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
            isOutgoing: event.pubkey == currentUserPubkey,
          ));
        } catch (e) {
          if (kDebugMode) {
            print('Error decrypting message: $e');
          }
        }
      }

      // Sort by timestamp (newest first)
      directMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return directMessages;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching messages: $e');
      }
      return [];
    }
  }

  /// Subscribe to real-time direct messages
  Stream<DirectMessage> subscribeToMessages() async* {
    final currentUserPubkey = await _keyManagementService.getPublicKey();
    if (currentUserPubkey == null) {
      throw Exception('User not logged in');
    }

    // Create filter for incoming messages
    // Note: The nostr package Filter doesn't support tag filtering directly
    // We'll filter by kind and handle tag filtering manually
    final filter = nostr.Filter(
      kinds: [4], // Direct messages
    );

    // Connect to relays and subscribe
    for (final relayUrl in _relayUrls) {
      try {
        final relay = NostrRelayServiceV2(relayUrl);
        final connected = await relay.connect();
        
        if (connected) {
          final stream = relay.subscribeToStream(filter);
          
          await for (final event in stream) {
            // Find the sender in the 'p' tags
            String? recipientPubkey;
            for (final tag in event.tags) {
              if (tag.length >= 2 && tag[0] == 'p') {
                recipientPubkey = tag[1];
                break;
              }
            }
            
            if (recipientPubkey != null) {
              try {
                // Decrypt the message
                final decryptedContent = await _encryptionService.decryptMessage(
                  event.content,
                  event.pubkey,
                );

                yield DirectMessage(
                  id: event.id,
                  senderPubkey: event.pubkey,
                  recipientPubkey: currentUserPubkey,
                  content: decryptedContent,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
                  isOutgoing: false,
                );
              } catch (e) {
                if (kDebugMode) {
                  print('Error decrypting real-time message: $e');
                }
              }
            }
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error subscribing to relay $relayUrl: $e');
        }
      }
    }
  }
}

/// Model for a direct message
class DirectMessage {
  final String id;
  final String senderPubkey;
  final String recipientPubkey;
  final String content;
  final DateTime timestamp;
  final bool isOutgoing;

  DirectMessage({
    required this.id,
    required this.senderPubkey,
    required this.recipientPubkey,
    required this.content,
    required this.timestamp,
    required this.isOutgoing,
  });
}

/// Provider for the direct message service using dart-nostr
final directMessageServiceV2Provider = Provider<DirectMessageServiceV2>((ref) {
  final keyService = ref.watch(keyManagementServiceProvider);
  final encryptionService = ref.watch(messageEncryptionServiceProvider);
  final relayUrls = ref.watch(defaultRelaysProvider);
  
  return DirectMessageServiceV2(
    keyManagementService: keyService,
    encryptionService: encryptionService,
    relayUrls: relayUrls,
  );
});