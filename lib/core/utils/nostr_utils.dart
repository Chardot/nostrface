import 'package:nostr/nostr.dart' as nostr;
import 'package:bech32/bech32.dart';
import 'dart:convert';
import 'dart:typed_data';

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
      // Decode using bech32 package
      final decoded = bech32.decode(nprofile);
      
      if (decoded.hrp != 'nprofile') {
        return null;
      }
      
      // Convert from 5-bit to 8-bit encoding
      final data = _convertBits(decoded.data, 5, 8, false);
      if (data == null) return null;
      
      // Parse TLV entries
      int i = 0;
      while (i < data.length) {
        if (i + 2 > data.length) break;
        
        final type = data[i];
        final length = data[i + 1];
        
        if (i + 2 + length > data.length) break;
        
        // Type 0 is the special key (public key for nprofile)
        if (type == 0 && length == 32) {
          final pubkeyBytes = data.sublist(i + 2, i + 2 + length);
          return _bytesToHex(Uint8List.fromList(pubkeyBytes));
        }
        
        i += 2 + length;
      }
      
      return null;
    } catch (e) {
      print('Error decoding nprofile: $e');
      return null;
    }
  }
  
  /// Convert between different bit sizes (from bech32 5-bit to 8-bit)
  static List<int>? _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final ret = <int>[];
    final maxv = (1 << toBits) - 1;
    
    for (final value in data) {
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        ret.add((acc >> bits) & maxv);
      }
    }
    
    if (pad) {
      if (bits > 0) {
        ret.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      return null;
    }
    
    return ret;
  }
  
  /// Convert hex string to bytes
  static Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
  
  /// Convert bytes to hex string
  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
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