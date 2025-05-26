import 'package:nostr/nostr.dart' as nostr;
import 'dart:convert';

void main() {
  // Test event creation
  print('Testing follow event creation...\n');
  
  // Example private key (DO NOT USE IN PRODUCTION)
  const testPrivKey = '5ee1c8000ab28edd64d74a7d951ac2dd559814887b1b9e1ac7c5f89e96125c12';
  
  try {
    // Create a test contact list
    final followedPubkeys = [
      '82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2', // jack
      '3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d', // fiatjaf
    ];
    
    final tags = followedPubkeys.map((p) => ['p', p]).toList();
    
    // Create the event
    final event = nostr.Event.from(
      kind: 3,
      tags: tags,
      content: '',
      privkey: testPrivKey,
    );
    
    print('Event created successfully!');
    print('Event ID: ${event.id}');
    print('Public key: ${event.pubkey}');
    print('Created at: ${DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000)}');
    print('Signature: ${event.sig}');
    
    print('\nFull event JSON:');
    final eventJson = {
      'id': event.id,
      'pubkey': event.pubkey,
      'created_at': event.createdAt,
      'kind': event.kind,
      'tags': event.tags,
      'content': event.content,
      'sig': event.sig,
    };
    print(const JsonEncoder.withIndent('  ').convert(eventJson));
    
    print('\nSerialized for relay:');
    print(event.serialize());
    
  } catch (e) {
    print('Error creating event: $e');
    print(e.runtimeType);
  }
}