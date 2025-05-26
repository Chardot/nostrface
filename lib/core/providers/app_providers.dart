import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/services/note_cache_service.dart';

/// Hardcoded relay for the app
final defaultRelaysProvider = Provider<List<String>>((ref) {
  return [
    'wss://relay.nos.social',
  ];
});

/// Provider for relay URLs - hardcoded to relay.nos.social
final relayUrlsProvider = Provider<List<String>>((ref) {
  return ref.watch(defaultRelaysProvider);
});

/// Note cache service provider
final noteCacheServiceProvider = Provider<NoteCacheService>((ref) {
  return NoteCacheService();
});