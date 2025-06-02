import 'package:nostr/nostr.dart' as nostr;

/// Utility functions for Nostr protocol
class NostrUtils {
  /// Decode a bech32-encoded string (npub, nprofile, etc.) to get the public key
  static String? decodeBech32PublicKey(String bech32String) {
    try {
      // Handle npub format
      if (bech32String.startsWith('npub')) {
        final keyData = nostr.Nip19.decodePubkey(bech32String);
        return keyData;
      }
      
      // Handle nprofile format (contains additional metadata)
      if (bech32String.startsWith('nprofile')) {
        // For nprofile, we need to extract just the public key
        // The nostr package should provide a way to decode this
        // For now, we'll try to extract it manually
        try {
          // This is a workaround - ideally the nostr package would handle this
          // nprofile contains TLV-encoded data with the pubkey
          final decoded = _decodeNprofile(bech32String);
          return decoded;
        } catch (e) {
          print('Error decoding nprofile: $e');
          return null;
        }
      }
      
      // If it's neither npub nor nprofile, it might be a hex pubkey
      if (bech32String.length == 64 && _isHex(bech32String)) {
        return bech32String;
      }
      
      return null;
    } catch (e) {
      print('Error decoding bech32: $e');
      return null;
    }
  }
  
  /// Helper to check if a string is valid hex
  static bool _isHex(String str) {
    final hexRegex = RegExp(r'^[0-9a-fA-F]+$');
    return hexRegex.hasMatch(str);
  }
  
  /// Decode nprofile format
  /// nprofile contains TLV data where type 0 is the public key
  static String? _decodeNprofile(String nprofile) {
    try {
      // For now, we'll use a simple approach
      // In a full implementation, we'd properly parse the TLV structure
      // The nostr package might have utilities for this
      
      // Try to use the nostr package's decoding if available
      // Otherwise fall back to manual parsing
      
      // This is a placeholder - the actual implementation would
      // properly decode the bech32 and parse the TLV data
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// Convert hex public key to npub format
  static String hexToNpub(String hexPubkey) {
    try {
      return nostr.Nip19.encodePubkey(hexPubkey);
    } catch (e) {
      return 'npub${hexPubkey.substring(0, 8)}...';
    }
  }
}