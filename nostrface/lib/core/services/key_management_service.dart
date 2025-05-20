import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

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
      
      if (kDebugMode) {
        print('Checking if private key exists: ${privateKey != null && privateKey.isNotEmpty}');
      }
      return privateKey != null && privateKey.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking for private key: $e');
      }
      return false;
    }
  }
  
  /// Get the stored public key
  Future<String?> getPublicKey() async {
    try {
      if (kIsWeb) {
        // For web, use Hive
        await _ensureWebStorage();
        return _webStorageBox?.get(_publicKeyKey);
      } else {
        // For native platforms, use secure storage
        return await _secureStorage.read(key: _publicKeyKey);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting public key: $e');
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
    // Normalize the private key (handle nsec format)
    final normalizedKey = _normalizePrivateKey(privateKey);
    
    // In a real app, you would derive the public key from the private key
    // This is a placeholder that simulates deriving a public key
    final String simulatedPublicKey = _simulateDerivePublicKey(normalizedKey);
    
    if (kIsWeb) {
      // For web, use Hive
      await _ensureWebStorage();
      await _webStorageBox?.put(_privateKeyKey, normalizedKey);
      await _webStorageBox?.put(_publicKeyKey, simulatedPublicKey);
      
      if (kDebugMode) {
        print('Stored keys in web storage');
        print('Private key stored: ${_webStorageBox?.get(_privateKeyKey) != null}');
        print('Public key stored: ${_webStorageBox?.get(_publicKeyKey) != null}');
      }
    } else {
      // For native platforms, use secure storage
      await _secureStorage.write(key: _privateKeyKey, value: normalizedKey);
      await _secureStorage.write(key: _publicKeyKey, value: simulatedPublicKey);
    }
  }
  
  /// Validates and normalizes a private key
  /// Converts nsec to hex format if needed
  String _normalizePrivateKey(String privateKey) {
    privateKey = privateKey.trim();
    
    // Check if it's an nsec key
    if (privateKey.startsWith('nsec1')) {
      try {
        // In a real implementation, you would use bech32 to decode the nsec to hex
        // This is a simplified placeholder
        if (kDebugMode) {
          debugPrint('Normalizing nsec key: ${privateKey.substring(0, 8)}...');
        }
        // For now, we'll just strip the nsec1 prefix for demonstration
        // In a real app, you would decode the bech32 string properly
        return privateKey.replaceFirst('nsec1', '');
      } catch (e) {
        debugPrint('Error normalizing nsec key: $e');
        throw Exception('Invalid nsec format');
      }
    }
    
    // If it's not nsec, assume it's already in hex format
    return privateKey;
  }
  
  /// Validate if a private key is in correct format (nsec or hex)
  bool isValidPrivateKey(String? privateKey) {
    if (privateKey == null || privateKey.trim().isEmpty) {
      return false;
    }
    
    privateKey = privateKey.trim();
    
    // Check if it's an nsec key
    if (privateKey.startsWith('nsec1')) {
      // Validate nsec format - in a real app you would check bech32 checksum
      return privateKey.length >= 5; // Very basic check
    }
    
    // Check if it's a hex key (should be 64 chars)
    // In a real app, you would do a more thorough check
    return privateKey.length >= 5; // Very basic check for now
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
  
  /// Simulate deriving a public key from a private key
  /// This is a placeholder - in a real app, you would use the secp256k1 library
  String _simulateDerivePublicKey(String privateKey) {
    // This is not the actual algorithm, just a placeholder
    // In a real app, you would use secp256k1 to derive the public key
    final bytes = utf8.encode(privateKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
  
  /// Generate a new key pair
  /// This is a placeholder - in a real app, you would use the secp256k1 library
  Future<void> generateKeyPair() async {
    // Simulate generating a random private key
    final List<int> randomBytes = List.generate(32, (_) => 0 + (255 * 0.9).round());
    final String privateKey = base64.encode(Uint8List.fromList(randomBytes));
    
    await storePrivateKey(privateKey);
  }
  
  /// Sign an event with the stored private key
  /// This is a placeholder - in a real app, you would use the secp256k1 library
  Future<String> signEvent(Map<String, dynamic> event) async {
    // In a real app, you would use the private key to sign the event
    // This is just a placeholder
    final String? privateKey = await getPrivateKey();
    if (privateKey == null) {
      throw Exception('No private key available for signing');
    }
    
    final String eventJson = jsonEncode(event);
    final bytes = utf8.encode(eventJson + privateKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
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