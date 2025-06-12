import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/ndk_service.dart';
import 'package:nostrface/core/services/ndk_event_signer.dart';
import 'package:nostrface/core/services/profile_service_ndk.dart';
import 'package:nostrface/core/services/direct_message_service_ndk.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/services/failed_images_service.dart';
import 'package:nostrface/core/services/image_validation_service.dart';
import 'package:nostrface/core/services/profile_buffer_service_indexed.dart';
import 'package:nostrface/core/services/profile_readiness_service.dart';
import 'package:nostrface/core/services/indexer_api_service.dart';
import 'package:nostrface/core/services/profile_service_v2.dart';
import 'package:nostrface/core/services/reactions_service_ndk.dart';
import 'package:nostrface/core/services/lists_service_ndk.dart';
import 'package:nostrface/core/services/note_cache_service.dart';
import 'package:nostrface/core/providers/ndk_providers.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/models/ndk_adapters.dart';

/// Key management service provider
final keyManagementServiceProvider = Provider<KeyManagementService>((ref) {
  return KeyManagementService();
});

/// NDK event signer provider
final ndkEventSignerProvider = Provider<NdkEventSigner>((ref) {
  final keyService = ref.watch(keyManagementServiceProvider);
  return NdkEventSigner(keyService);
});

/// Profile service provider (NDK-based)
final profileServiceNdkProvider = Provider<ProfileServiceNdk>((ref) {
  final ndkService = ref.watch(ndkServiceProvider);
  final signer = ref.watch(ndkEventSignerProvider);
  
  final service = ProfileServiceNdk(
    ndkService: ndkService,
    signer: signer,
  );
  
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
});

/// Direct message service provider (NDK-based)
final directMessageServiceNdkProvider = Provider<DirectMessageServiceNdk>((ref) {
  final ndkService = ref.watch(ndkServiceProvider);
  final signer = ref.watch(ndkEventSignerProvider);
  
  final service = DirectMessageServiceNdk(
    ndkService: ndkService,
    signer: signer,
  );
  
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
});

/// Initialize all services
final servicesInitializerProvider = FutureProvider<void>((ref) async {
  // Initialize NDK
  await ref.read(ndkProvider.future);
  
  // Initialize profile service
  final profileService = ref.read(profileServiceNdkProvider);
  await profileService.initialize();
  
  // Initialize other services
  final discardedService = ref.read(discardedProfilesServiceProvider);
  await discardedService.initialize();
  
  final failedImagesService = ref.read(failedImagesServiceProvider);
  await failedImagesService.init();
});

/// Current user pubkey provider
final currentUserPubkeyProvider = FutureProvider<String?>((ref) async {
  final keyService = ref.watch(keyManagementServiceProvider);
  return await keyService.getPublicKey();
});

/// Is user authenticated provider
final isAuthenticatedProvider = FutureProvider<bool>((ref) async {
  final pubkey = await ref.watch(currentUserPubkeyProvider.future);
  return pubkey != null;
});

/// Following status provider
final isFollowingProvider = FutureProvider.family<bool, String>((ref, pubkey) async {
  final profileService = ref.watch(profileServiceNdkProvider);
  await ref.watch(servicesInitializerProvider.future);
  return await profileService.isFollowing(pubkey);
});

/// User following list provider
final userFollowingProvider = StreamProvider<Set<String>>((ref) async* {
  final profileService = ref.watch(profileServiceNdkProvider);
  await ref.watch(servicesInitializerProvider.future);
  
  // Get initial following list
  final following = await profileService.getFollowing();
  yield following;
  
  // Stream updates
  yield* profileService.followingUpdates;
});

/// Profile provider by pubkey
final profileByPubkeyProvider = FutureProvider.family<NostrProfile?, String>((ref, pubkey) async {
  final profileService = ref.watch(profileServiceNdkProvider);
  await ref.watch(servicesInitializerProvider.future);
  return await profileService.getProfile(pubkey);
});

/// Profile stream provider for discovery
final profileDiscoveryProvider = StreamProvider<List<NostrProfile>>((ref) async* {
  final profileService = ref.watch(profileServiceNdkProvider);
  await ref.watch(servicesInitializerProvider.future);
  
  final profiles = <NostrProfile>[];
  await for (final profile in profileService.streamProfiles()) {
    profiles.add(profile);
    yield List.from(profiles);
  }
});

// Keep existing providers that don't need migration
final discardedProfilesServiceProvider = Provider<DiscardedProfilesService>((ref) {
  return DiscardedProfilesService();
});

final failedImagesServiceProvider = Provider<FailedImagesService>((ref) {
  final service = FailedImagesService();
  service.init();
  return service;
});

final imageValidationServiceProvider = Provider<ImageValidationService>((ref) {
  return ImageValidationService();
});

final profileBufferServiceIndexedProvider = Provider<ProfileBufferServiceIndexed>((ref) {
  final profileService = ref.watch(profileServiceV2Provider);
  final discardedService = ref.watch(discardedProfilesServiceProvider);
  final failedImagesService = ref.watch(failedImagesServiceProvider);
  
  return ProfileBufferServiceIndexed(
    profileService,
    discardedService,
    failedImagesService,
  );
});

final profileReadinessServiceProvider = Provider<ProfileReadinessService>((ref) {
  return ProfileReadinessService();
});

final indexerApiServiceProvider = Provider<IndexerApiService>((ref) {
  return IndexerApiService();
});

// Keep old ProfileServiceV2 for buffer service compatibility
final profileServiceV2Provider = Provider<ProfileServiceV2>((ref) {
  final keyService = ref.watch(keyManagementServiceProvider);
  // TODO: Replace with relay service when migrating ProfileServiceV2
  throw UnimplementedError('ProfileServiceV2 needs to be migrated to NDK');
});

// Note cache service provider
final noteCacheServiceProvider = Provider<NoteCacheService>((ref) {
  return NoteCacheService();
});

/// Reactions service provider (NDK-based)
final reactionsServiceNdkProvider = Provider<ReactionsServiceNdk>((ref) {
  final ndkService = ref.watch(ndkServiceProvider);
  final signer = ref.watch(ndkEventSignerProvider);
  
  final service = ReactionsServiceNdk(
    ndkService: ndkService,
    signer: signer,
  );
  
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
});

/// Lists service provider (NDK-based)
final listsServiceNdkProvider = Provider<ListsServiceNdk>((ref) {
  final ndkService = ref.watch(ndkServiceProvider);
  final signer = ref.watch(ndkEventSignerProvider);
  
  final service = ListsServiceNdk(
    ndkService: ndkService,
    signer: signer,
  );
  
  ref.onDispose(() {
    service.dispose();
  });
  
  return service;
});