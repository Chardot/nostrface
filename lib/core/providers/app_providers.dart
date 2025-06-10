import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/services/note_cache_service.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/services/failed_images_service.dart';
import 'package:nostrface/core/services/profile_readiness_service.dart';
import 'package:nostrface/core/services/profile_service_v2.dart';
import 'package:nostrface/core/services/profile_buffer_service_indexed.dart';
import 'package:nostrface/core/models/nostr_profile.dart';

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

/// Provider for ProfileServiceV2
final profileServiceV2Provider = Provider<ProfileServiceV2>((ref) {
  final relays = ref.watch(relayUrlsProvider);
  return ProfileServiceV2(relays);
});

/// Provider for the indexed profile buffer service
final profileBufferServiceIndexedProvider = Provider<ProfileBufferServiceIndexed>((ref) {
  final profileService = ref.watch(profileServiceV2Provider);
  final discardedService = ref.watch(discardedProfilesServiceProvider);
  final failedImagesService = ref.watch(failedImagesServiceProvider);
  return ProfileBufferServiceIndexed(profileService, discardedService, failedImagesService);
});

/// Stream provider for indexed buffered profiles
final indexedBufferedProfilesProvider = StreamProvider<List<NostrProfile>>((ref) {
  final bufferService = ref.watch(profileBufferServiceIndexedProvider);
  return bufferService.profilesStream;
});

/// Provider for indexed buffer loading state
final indexedBufferLoadingProvider = StreamProvider<bool>((ref) {
  final bufferService = ref.watch(profileBufferServiceIndexedProvider);
  return bufferService.loadingStream;
});