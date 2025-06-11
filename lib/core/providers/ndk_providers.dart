import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ndk/ndk.dart';
import 'package:nostrface/core/services/ndk_service.dart';

/// Provider for the NDK service instance
final ndkServiceProvider = Provider<NdkService>((ref) {
  final service = NdkService();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// Provider for initialized NDK instance
final ndkProvider = FutureProvider<Ndk>((ref) async {
  final service = ref.watch(ndkServiceProvider);
  if (!service.isInitialized) {
    await service.initialize();
  }
  return service.ndk;
});

/// Stream provider for fetching metadata by pubkey
final metadataStreamProvider = StreamProvider.family<Metadata?, String>((ref, pubkey) {
  final service = ref.watch(ndkServiceProvider);
  if (!service.isInitialized) {
    // Initialize if not done yet
    ref.read(ndkProvider);
    return const Stream.empty();
  }
  return service.getMetadata(pubkey);
});

/// Stream provider for fetching multiple metadata
final multipleMetadataStreamProvider = StreamProvider.family<Map<String, Metadata>, List<String>>((ref, pubkeys) {
  final service = ref.watch(ndkServiceProvider);
  if (!service.isInitialized) {
    ref.read(ndkProvider);
    return const Stream.empty();
  }
  return service.getMetadataMultiple(pubkeys);
});

/// Provider for contact list by pubkey
final contactListProvider = FutureProvider.family<ContactList?, String>((ref, pubkey) async {
  final service = ref.watch(ndkServiceProvider);
  if (!service.isInitialized) {
    await ref.read(ndkProvider.future);
  }
  return service.getContactList(pubkey);
});

/// Provider to check if one pubkey follows another
final isFollowingProvider = FutureProvider.family<bool, (String, String)>((ref, params) async {
  final (followerPubkey, followeePubkey) = params;
  final service = ref.watch(ndkServiceProvider);
  if (!service.isInitialized) {
    await ref.read(ndkProvider.future);
  }
  return service.isFollowing(followerPubkey, followeePubkey);
});

/// Stream provider for text notes by author
final textNotesStreamProvider = StreamProvider.family<List<Nip01Event>, String>((ref, authorPubkey) {
  final service = ref.watch(ndkServiceProvider);
  if (!service.isInitialized) {
    ref.read(ndkProvider);
    return Stream.value([]);
  }

  final filter = Filter(
    authors: [authorPubkey],
    kinds: [1], // Text note kind
    limit: 50,
  );

  final events = <Nip01Event>[];
  return service.queryEvents([filter]).map((event) {
    events.add(event);
    return List<Nip01Event>.from(events)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  });
});

/// Stream provider for profile discovery
final profileDiscoveryStreamProvider = StreamProvider<List<Metadata>>((ref) async* {
  final service = ref.watch(ndkServiceProvider);
  if (!service.isInitialized) {
    await ref.read(ndkProvider.future);
  }

  // Get metadata events from various relays
  final filter = Filter(
    kinds: [0], // Metadata kind
    limit: 100,
    since: DateTime.now().subtract(const Duration(days: 7)),
  );

  final metadataMap = <String, Metadata>{};
  
  await for (final event in service.queryEvents([filter])) {
    try {
      final metadata = Metadata.fromNip01Event(event);
      // Only add if has picture and not already in map
      if (metadata.picture != null && metadata.picture!.isNotEmpty) {
        metadataMap[event.pubkey] = metadata;
        yield metadataMap.values.toList();
      }
    } catch (e) {
      // Skip invalid metadata
    }
  }
});