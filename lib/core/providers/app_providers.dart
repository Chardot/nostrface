import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/services/note_cache_service.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/services/failed_images_service.dart';
import 'package:nostrface/core/services/profile_readiness_service.dart';

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

/// Provider for discarded profiles service
final discardedProfilesServiceProvider = Provider<DiscardedProfilesService>((ref) {
  return DiscardedProfilesService();
});

/// Provider for failed images service
final failedImagesServiceProvider = Provider<FailedImagesService>((ref) {
  final service = FailedImagesService();
  service.init(); // Initialize on creation
  return service;
});

/// Provider for profile readiness service
final profileReadinessServiceProvider = Provider<ProfileReadinessService>((ref) {
  return ProfileReadinessService();
});