import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:nostrface/core/models/nostr_event.dart';

/// Service for caching user notes to improve performance
class NoteCacheService {
  static const String _boxName = 'note_cache';
  static const Duration _cacheExpiry = Duration(minutes: 5);
  
  /// Cache structure: pubkey -> CachedNotes
  late Box<String> _cacheBox;
  bool _isInitialized = false;
  
  /// Initialize the cache
  Future<void> init() async {
    if (_isInitialized) return;
    
    _cacheBox = await Hive.openBox<String>(_boxName);
    _isInitialized = true;
  }
  
  /// Get cached notes for a user
  Future<List<NostrEvent>?> getCachedNotes(String pubkey) async {
    if (!_isInitialized) await init();
    
    try {
      final cacheData = _cacheBox.get(pubkey);
      if (cacheData == null) return null;
      
      final cached = CachedNotes.fromJson(jsonDecode(cacheData));
      
      // Check if cache is expired
      if (DateTime.now().isAfter(cached.expiry)) {
        await _cacheBox.delete(pubkey);
        return null;
      }
      
      return cached.notes;
    } catch (e) {
      if (kDebugMode) {
        print('Error reading cached notes: $e');
      }
      return null;
    }
  }
  
  /// Cache notes for a user
  Future<void> cacheNotes(String pubkey, List<NostrEvent> notes) async {
    if (!_isInitialized) await init();
    
    try {
      final cached = CachedNotes(
        notes: notes,
        expiry: DateTime.now().add(_cacheExpiry),
      );
      
      await _cacheBox.put(pubkey, jsonEncode(cached.toJson()));
    } catch (e) {
      if (kDebugMode) {
        print('Error caching notes: $e');
      }
    }
  }
  
  /// Clear all cached notes
  Future<void> clearCache() async {
    if (!_isInitialized) await init();
    await _cacheBox.clear();
  }
  
  /// Clear cached notes for a specific user
  Future<void> clearUserCache(String pubkey) async {
    if (!_isInitialized) await init();
    await _cacheBox.delete(pubkey);
  }
}

/// Model for cached notes with expiry
class CachedNotes {
  final List<NostrEvent> notes;
  final DateTime expiry;
  
  CachedNotes({
    required this.notes,
    required this.expiry,
  });
  
  factory CachedNotes.fromJson(Map<String, dynamic> json) {
    return CachedNotes(
      notes: (json['notes'] as List<dynamic>)
          .map((e) => NostrEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      expiry: DateTime.parse(json['expiry'] as String),
    );
  }
  
  Map<String, dynamic> toJson() => {
    'notes': notes.map((e) => e.toJson()).toList(),
    'expiry': expiry.toIso8601String(),
  };
}