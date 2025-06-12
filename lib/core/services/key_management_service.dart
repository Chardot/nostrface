import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:nostrface/core/utils/nostr_legacy_support.dart' as nostr;

/// Service for managing Nostr keys
class KeyManagementService {
  static const String _privateKeyKey = 'nostr_private_key';
  static const String _publicKeyKey = 'nostr_public_key';
  static const String _webStorageBoxName = 'auth_storage';
  
  final FlutterSecureStorage _secureStorage;
  Box? _webStorageBox;
  
  KeyManagementService({FlutterSecureStorage? secureStorage}) 
    : _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    // Initialize web storage if needed
    if (kIsWeb) {
      _initWebStorage();
    }
  }
  
  /// Initialize web storage for persisting auth data on web platform
  Future<void> _initWebStorage() async {
    try {
      if (Hive.isBoxOpen(_webStorageBoxName)) {
        _webStorageBox = Hive.box(_webStorageBoxName);
      } else {
        _webStorageBox = await Hive.openBox(_webStorageBoxName);
      }
      if (kDebugMode) {
        print('Web storage initialized successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing web storage: $e');
      }
    }
  }
  
  /// Check if a private key is stored
  Future<bool> hasPrivateKey() async {
    try {
      String? privateKey;
      
      if (kIsWeb) {
        // For web, use Hive
        await _ensureWebStorage();
        privateKey = _webStorageBox?.get(_privateKeyKey);
      } else {
        // For native platforms, use secure storage
        privateKey = await _secureStorage.read(key: _privateKeyKey);
      }
      
      final exists = privateKey != null && privateKey.isNotEmpty;
      print('KeyManagementService.hasPrivateKey: $exists');
      if (exists) {
        print('  Private key length: ${privateKey!.length} chars');
      }
      return exists;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking for private key: $e');
      }
      return false;
    }
  }
  
  /// Get the stored public key
  Future<String?> getPublicKey() async {
    print('KeyManagementService.getPublicKey called');
    try {
      String? pubkey;
      if (kIsWeb) {
        // For web, use Hive
        await _ensureWebStorage();
        pubkey = _webStorageBox?.get(_publicKeyKey);
      } else {
        // For native platforms, use secure storage
        pubkey = await _secureStorage.read(key: _publicKeyKey);
      }
      return pubkey;
    } catch (e) {
      if (kDebugMode) {
        print('[KeyManagement] Error getting public key: $e');
      }
      return null;
    }
  }
  
  /// Ensure web storage is initialized
  Future<void> _ensureWebStorage() async {
    if (kIsWeb && _webStorageBox == null) {
      await _initWebStorage();
    }
  }
  
  /// Store a private key securely
  /// Handles both nsec and hex formats
  Future<void> storePrivateKey(String privateKey) async {
    try {
      String hexPrivateKey;
      
      // Check if it's an nsec key and decode it
      if (privateKey.trim().startsWith('nsec')) {
        hexPrivateKey = nostr.Nip19.decodePrivkey(privateKey.trim());
        if (hexPrivateKey.isEmpty) {
          throw Exception('Invalid nsec format');
        }
        
        if (kDebugMode) {
          print('Decoded nsec to hex: ${hexPrivateKey.substring(0, 8)}...');
        }
      } else {
        // Assume it's already hex
        hexPrivateKey = privateKey.trim();
      }
      
      // Create a Keychain from the hex private key
      final keychain = nostr.Keychain(hexPrivateKey);
      
      // Get the public key
      final String publicKey = keychain.public;
      
      if (kIsWeb) {
        // For web, use Hive
        await _ensureWebStorage();
        await _webStorageBox?.put(_privateKeyKey, hexPrivateKey);
        await _webStorageBox?.put(_publicKeyKey, publicKey);
        
        if (kDebugMode) {
          print('Stored keys in web storage');
          print('Private key stored: ${_webStorageBox?.get(_privateKeyKey) != null}');
          print('Public key stored: ${_webStorageBox?.get(_publicKeyKey) != null}');
          print('Public key: $publicKey');
        }
      } else {
        // For native platforms, use secure storage
        await _secureStorage.write(key: _privateKeyKey, value: hexPrivateKey);
        await _secureStorage.write(key: _publicKeyKey, value: publicKey);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error storing private key: $e');
      }
      throw Exception('Invalid private key format: ${e.toString()}');
    }
  }
  
  /// Validates and normalizes a private key
  /// Converts nsec to hex format if needed
  String _normalizePrivateKey(String privateKey) {
    privateKey = privateKey.trim();
    
    try {
      // Check if it's an nsec key and decode it
      if (privateKey.startsWith('nsec')) {
        final decoded = nostr.Nip19.decodePrivkey(privateKey);
        if (decoded.isEmpty) {
          throw Exception('Invalid nsec format');
        }
        return decoded;
      } else {
        // Assume it's already hex
        return privateKey;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error normalizing private key: $e');
      }
      throw Exception('Invalid private key format');
    }
  }
  
  /// Validate if a private key is in correct format (nsec or hex)
  bool isValidPrivateKey(String? privateKey) {
    if (privateKey == null || privateKey.trim().isEmpty) {
      return false;
    }
    
    privateKey = privateKey.trim();
    
    try {
      // Check if it's an nsec key
      if (privateKey.startsWith('nsec')) {
        final decoded = nostr.Nip19.decodePrivkey(privateKey);
        return decoded.isNotEmpty;
      } else {
        // Check if it's a valid hex key (64 characters)
        if (privateKey.length != 64) return false;
        // Try to create a Keychain with it
        nostr.Keychain(privateKey);
        return true;
      }
    } catch (e) {
      return false;
    }
  }
  
  /// Get the stored private key
  Future<String?> getPrivateKey() async {
    if (kIsWeb) {
      // For web, use Hive
      await _ensureWebStorage();
      return _webStorageBox?.get(_privateKeyKey);
    } else {
      // For native platforms, use secure storage
      return await _secureStorage.read(key: _privateKeyKey);
    }
  }
  
  /// Clear the stored keys
  Future<void> clearKeys() async {
    if (kIsWeb) {
      // For web, use Hive
      await _ensureWebStorage();
      await _webStorageBox?.delete(_privateKeyKey);
      await _webStorageBox?.delete(_publicKeyKey);
      if (kDebugMode) {
        print('Keys cleared from web storage');
      }
    } else {
      // For native platforms, use secure storage
      await _secureStorage.delete(key: _privateKeyKey);
      await _secureStorage.delete(key: _publicKeyKey);
    }
  }
  
  
  /// Generate a new key pair
  Future<void> generateKeyPair() async {
    // Generate a new random key pair using dart-nostr
    final keychain = nostr.Keychain.generate();
    
    // Store the hex private key
    await storePrivateKey(keychain.private);
  }
  
  
  /// Get the Keychain object for signing
  Future<nostr.Keychain?> getKeychain() async {
    final String? privateKey = await getPrivateKey();
    if (privateKey == null) {
      if (kDebugMode) {
        print('[KeyManagement] No private key found');
      }
      return null;
    }
    
    try {
      final keychain = nostr.Keychain(privateKey);
      return keychain;
    } catch (e) {
      if (kDebugMode) {
        print('[KeyManagement] Error creating keychain: $e');
      }
      return null;
    }
  }
}

/// Provider for the key management service
final keyManagementServiceProvider = Provider<KeyManagementService>((ref) {
  return KeyManagementService();
});

/// Provider for the current user's public key
final currentPublicKeyProvider = FutureProvider<String?>((ref) async {
  final keyService = ref.watch(keyManagementServiceProvider);
  return await keyService.getPublicKey();
});

/// Provider to check if the user is logged in (has a private key)
final isLoggedInProvider = FutureProvider<bool>((ref) async {
  final keyService = ref.watch(keyManagementServiceProvider);
  return await keyService.hasPrivateKey();
});