import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    ProviderScope(
      child: ContactListTestApp(),
    ),
  );
}

class ContactListTestApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Contact List Test')),
        body: ContactListTestScreen(),
      ),
    );
  }
}

class ContactListTestScreen extends ConsumerStatefulWidget {
  @override
  _ContactListTestScreenState createState() => _ContactListTestScreenState();
}

class _ContactListTestScreenState extends ConsumerState<ContactListTestScreen> {
  final List<String> _logs = [];
  bool _isRunning = false;
  
  void _log(String message) {
    setState(() {
      _logs.add(message);
    });
  }
  
  Future<void> _runTest() async {
    setState(() {
      _isRunning = true;
      _logs.clear();
    });
    
    _log('=== CONTACT LIST EVENT TEST ===\n');
    
    try {
      // Get services
      final keyService = ref.read(keyManagementServiceProvider);
      final relayService = ref.read(nostrRelayServiceProvider);
      
      // Get current public key
      final publicKey = keyService.getPublicKey();
      if (publicKey == null) {
        _log('ERROR: No private key loaded. Please login first.');
        return;
      }
      _log('Public Key: ${publicKey.substring(0, 16)}...');
      
      // Test contact
      const testContactPubkey = 'npub1gcxzte5zlkncx26j68ez60fzkvtkm9e0vrwdcvsjakxf9mu9qewqlfnj5z';
      final contacts = {testContactPubkey};
      
      // Create contact list event
      final contactListEvent = NostrEvent(
        kind: 3,
        pubkey: publicKey,
        createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        tags: contacts.map((pubkey) => ['p', pubkey]).toList(),
        content: '',
      );
      
      // Sign the event
      final signedEvent = await keyService.signEvent(contactListEvent);
      
      // Log the event JSON
      _log('\n=== EVENT JSON ===');
      _log(JsonEncoder.withIndent('  ').convert(signedEvent.toJson()));
      
      // Track relay responses
      final relayResponses = <String, String>{};
      final expectedRelays = relayService.getConnectedRelays();
      _log('\n=== CONNECTED RELAYS ===');
      for (final relay in expectedRelays) {
        _log('- $relay');
      }
      
      // Listen for OK responses
      final subscription = relayService.stream.listen((data) {
        if (data['relay'] != null) {
          final relay = data['relay'] as String;
          
          if (data['type'] == 'OK') {
            final eventId = data['eventId'];
            final success = data['success'] == true;
            final message = data['message'] ?? '';
            
            if (eventId == signedEvent.id) {
              relayResponses[relay] = success ? '✅ ACCEPTED' : '❌ REJECTED: $message';
              _log('\nRelay Response from $relay:');
              _log('  Event ID: $eventId');
              _log('  Status: ${relayResponses[relay]}');
            }
          }
        }
      });
      
      // Publish event
      _log('\n=== PUBLISHING EVENT ===');
      relayService.publishContactList(contacts);
      
      // Wait for responses
      _log('\nWaiting for relay responses...');
      await Future.delayed(Duration(seconds: 5));
      
      // Summary
      _log('\n=== SUMMARY ===');
      for (final relay in expectedRelays) {
        final response = relayResponses[relay] ?? '⏳ NO RESPONSE';
        _log('$relay: $response');
      }
      
      // Cleanup
      subscription.cancel();
      
    } catch (e) {
      _log('\nERROR: $e');
    } finally {
      setState(() {
        _isRunning = false;
      });
      _log('\n=== TEST COMPLETE ===');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _isRunning ? null : _runTest,
            child: Text(_isRunning ? 'Running Test...' : 'Run Contact List Test'),
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.black,
            padding: EdgeInsets.all(8),
            child: ListView.builder(
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                return Text(
                  _logs[index],
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.green,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}