import 'package:flutter/foundation.dart';
import 'package:nostrface/core/utils/nostr_legacy_support.dart' as nostr;
import 'package:nostrface/core/services/nostr_relay_service_improved.dart';

/// Debug utility to test follow event publishing
class FollowDebugger {
  static Future<Map<String, bool>> testFollowEvent({
    required String privateKey,
    required Set<String> followedPubkeys,
    required List<String> relayUrls,
  }) async {
    final results = <String, bool>{};
    
    try {
      // Create the contact list event
      final tags = followedPubkeys
          .map((pubkey) => ['p', pubkey])
          .toList();
      
      final event = nostr.Event.from(
        kind: 3, // Contact list
        tags: tags,
        content: '',
        privkey: privateKey,
      );
      
      print('\n=== FOLLOW EVENT DEBUG ===');
      print('Event ID: ${event.id}');
      print('Public Key: ${event.pubkey}');
      print('Created At: ${DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000)}');
      print('Following ${tags.length} profiles');
      print('\nFull Event JSON:');
      print(event.serialize());
      print('\n=== PUBLISHING TO RELAYS ===\n');
      
      // Try to publish to each relay
      for (final relayUrl in relayUrls) {
        print('Publishing to $relayUrl...');
        
        final relay = NostrRelayServiceImproved(relayUrl);
        
        try {
          // Connect to relay
          final connected = await relay.connect();
          if (!connected) {
            print('  ❌ Failed to connect');
            results[relayUrl] = false;
            continue;
          }
          
          // Publish event
          final published = await relay.publishEvent(event);
          results[relayUrl] = published;
          
          if (published) {
            print('  ✅ Event accepted');
          } else {
            print('  ❌ Event rejected');
          }
          
          // Disconnect
          relay.disconnect();
          
        } catch (e) {
          print('  ❌ Error: $e');
          results[relayUrl] = false;
        }
      }
      
      print('\n=== SUMMARY ===');
      final successCount = results.values.where((v) => v).length;
      print('Successfully published to $successCount/${relayUrls.length} relays');
      
      print('\nDetailed results:');
      results.forEach((relay, success) {
        print('  ${success ? '✅' : '❌'} $relay');
      });
      
    } catch (e) {
      print('Error creating follow event: $e');
    }
    
    return results;
  }
  
  /// Test with current user's follows
  static Future<void> testCurrentUserFollows({
    required String privateKey,
    required Set<String> currentFollows,
  }) async {
    final defaultRelays = [
      'wss://relay.damus.io',
      'wss://relay.nostr.band',
      'wss://nos.lol',
      'wss://nostr.wine',
      'wss://relay.snort.social',
      'wss://relay.nostr.bg',
      'wss://purplepag.es',
      'wss://relay.nostr.com.au',
      'wss://nostr-pub.wellorder.net',
      'wss://nostr.mutinywallet.com',
    ];
    
    await testFollowEvent(
      privateKey: privateKey,
      followedPubkeys: currentFollows,
      relayUrls: defaultRelays,
    );
  }
}