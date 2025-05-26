import 'package:flutter_test/flutter_test.dart';
import 'package:nostrface/core/services/nostr_relay_service.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'dart:convert';

void main() {
  test('Contact List Event Test', () async {
    print('\n=== CONTACT LIST EVENT TEST ===\n');
    
    // Initialize services
    final keyService = KeyManagementService();
    final relayService = NostrRelayService(keyService);
    
    // Test data
    const testPrivateKey = 'YOUR_TEST_PRIVATE_KEY_HERE'; // Replace with actual test key
    const testContactPubkey = 'npub1gcxzte5zlkncx26j68ez60fzkvtkm9e0vrwdcvsjakxf9mu9qewqlfnj5z'; // Test contact
    
    // Load private key
    await keyService.setPrivateKey(testPrivateKey);
    final publicKey = keyService.getPublicKey();
    print('Test Public Key: $publicKey');
    
    // Connect to relays
    final relays = [
      'wss://relay.damus.io',
      'wss://nos.lol',
      'wss://relay.snort.social',
      'wss://relay.nostr.band'
    ];
    
    print('\nConnecting to relays...');
    for (final relay in relays) {
      await relayService.connectToRelay(relay);
      await Future.delayed(Duration(seconds: 1)); // Give time to connect
    }
    
    // Create contact list
    final contacts = {testContactPubkey};
    
    // Create contact list event
    final contactListEvent = NostrEvent(
      kind: 3,
      pubkey: publicKey!,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      tags: contacts.map((pubkey) => ['p', pubkey]).toList(),
      content: '',
    );
    
    // Sign the event
    final signedEvent = await keyService.signEvent(contactListEvent);
    
    // Log the event JSON
    print('\n=== EVENT JSON ===');
    print(JsonEncoder.withIndent('  ').convert(signedEvent.toJson()));
    
    // Track relay responses
    final relayResponses = <String, String>{};
    
    // Listen for OK responses
    relayService.stream.listen((data) {
      if (data['relay'] != null) {
        final relay = data['relay'] as String;
        
        if (data['type'] == 'OK') {
          final eventId = data['eventId'];
          final success = data['success'] == true;
          final message = data['message'] ?? '';
          
          if (eventId == signedEvent.id) {
            relayResponses[relay] = success ? '✅ ACCEPTED' : '❌ REJECTED: $message';
            print('\nRelay Response from $relay:');
            print('  Event ID: $eventId');
            print('  Status: ${relayResponses[relay]}');
          }
        }
      }
    });
    
    // Publish event to all relays
    print('\n=== PUBLISHING EVENT ===');
    relayService.publishContactList(contacts);
    
    // Wait for responses
    print('\nWaiting for relay responses...');
    await Future.delayed(Duration(seconds: 5));
    
    // Summary
    print('\n=== SUMMARY ===');
    for (final relay in relays) {
      final response = relayResponses[relay] ?? '⏳ NO RESPONSE';
      print('$relay: $response');
    }
    
    // Disconnect
    relayService.disconnect();
    
    print('\n=== TEST COMPLETE ===\n');
  });
}