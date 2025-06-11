import 'package:ndk/ndk.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostr/nostr.dart' as old_nostr;

/// Custom event signer that integrates with existing KeyManagementService
class NdkEventSigner implements EventSigner {
  final KeyManagementService _keyService;

  NdkEventSigner(this._keyService);

  @override
  Future<Nip01Event> sign(Nip01Event event) async {
    final privateKey = await _keyService.getPrivateKey();
    if (privateKey == null) {
      throw Exception('No private key available for signing');
    }

    // Use the old nostr library for signing (temporary until full migration)
    final keychain = old_nostr.Keychain(privateKey);
    
    // Convert NDK event to old format for signing
    final oldEvent = old_nostr.Event(
      id: event.id,
      pubkey: event.pubkey,
      createdAt: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      sig: event.sig,
    );

    // Sign the event
    final signedOldEvent = oldEvent.sign(keychain);

    // Convert back to NDK format
    return Nip01Event(
      id: signedOldEvent.id,
      pubkey: signedOldEvent.pubkey,
      createdAt: signedOldEvent.createdAt,
      kind: signedOldEvent.kind,
      tags: signedOldEvent.tags,
      content: signedOldEvent.content,
      sig: signedOldEvent.sig,
    );
  }

  @override
  Future<String> getPublicKey() async {
    final pubkey = await _keyService.getPublicKey();
    if (pubkey == null) {
      throw Exception('No public key available');
    }
    return pubkey;
  }

  @override
  Future<void> free() async {
    // Nothing to free in this implementation
  }
}

/// Provider for the custom event signer
final ndkEventSignerProvider = Provider<NdkEventSigner>((ref) {
  final keyService = ref.watch(keyManagementServiceProvider);
  return NdkEventSigner(keyService);
});