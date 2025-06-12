import 'dart:convert';
import 'package:ndk/ndk.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bip340/bip340.dart' as bip340;
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

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

    // Generate event ID if not present
    String eventId = event.id;
    if (eventId.isEmpty) {
      // Serialize event for ID generation
      final serialized = [
        0,
        event.pubKey,
        event.createdAt,
        event.kind,
        event.tags,
        event.content,
      ];
      final serializedStr = json.encode(serialized);
      final bytes = utf8.encode(serializedStr);
      final digest = sha256.convert(bytes);
      eventId = hex.encode(digest.bytes);
    }
    
    // Create canonical serialization for signing
    final canonical = [
      0,
      event.pubKey,
      event.createdAt,
      event.kind,
      event.tags,
      event.content,
    ];
    final message = json.encode(canonical);
    final messageBytes = utf8.encode(message);
    final messageHash = sha256.convert(messageBytes).bytes;
    
    // Sign with bip340
    final signature = bip340.sign(privateKey, hex.encode(messageHash));

    // Return signed event
    return Nip01Event(
      id: eventId,
      pubKey: event.pubKey,
      createdAt: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      sig: signature,
    );
  }

  @override
  String getPublicKey() {
    // This needs to be synchronous for NDK
    // For now, throw an error - the service should use getPublicKeyAsync
    throw UnimplementedError('Use getPublicKeyAsync instead - synchronous access not supported');
  }
  
  Future<String> getPublicKeyAsync() async {
    final pubkey = await _keyService.getPublicKey();
    if (pubkey == null) {
      throw Exception('No public key available');
    }
    return pubkey;
  }

  @override
  bool canSign() {
    // We can sign if we have a private key
    // For now, return true and handle errors in sign()
    return true;
  }

  @override
  Future<String?> encrypt(String msg, String destPubKey, {String? id}) async {
    // TODO: Implement NIP-04 encryption using bip340/crypto libraries
    // For now, return null to indicate encryption not supported
    return null;
  }

  @override
  Future<String?> decrypt(String msg, String destPubKey, {String? id}) async {
    // TODO: Implement NIP-04 decryption using bip340/crypto libraries
    // For now, return null to indicate decryption not supported
    return null;
  }

  @override
  Future<String?> encryptNip44({
    required String msg,
    required String destPubKey,
    String? id,
  }) async {
    // NIP-44 not implemented in old library
    // Fall back to NIP-04 for now
    return encrypt(msg, destPubKey, id: id);
  }

  @override
  Future<String?> decryptNip44({
    required String msg,
    required String destPubKey,
    String? id,
  }) async {
    // NIP-44 not implemented in old library
    // Fall back to NIP-04 for now
    return decrypt(msg, destPubKey, id: id);
  }

  @override
  Future<void> free() async {
    // Nothing to free in this implementation
  }
  
  /// Get private key from KeyManagementService
  /// This is needed for encryption/decryption operations
  Future<String?> getPrivateKeyAsync() async {
    return await _keyService.getPrivateKey();
  }
}

/// Provider for the custom event signer
final ndkEventSignerProvider = Provider<NdkEventSigner>((ref) {
  final keyService = ref.watch(keyManagementServiceProvider);
  return NdkEventSigner(keyService);
});