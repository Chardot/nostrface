import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/profile_buffer_service_indexed.dart';
import 'package:nostrface/features/profile_discovery/presentation/widgets/profile_card_new.dart';
import 'package:nostrface/features/profile_discovery/presentation/widgets/swipe_overlays.dart' show SwipeOverlay;
import 'package:nostrface/features/direct_messages/presentation/widgets/dm_composer.dart';
import 'package:nostrface/main.dart'; // For appStartTime

class DiscoveryScreenIndexed extends ConsumerStatefulWidget {
  const DiscoveryScreenIndexed({Key? key}) : super(key: key);

  @override
  ConsumerState<DiscoveryScreenIndexed> createState() => _DiscoveryScreenIndexedState();
}

class _DiscoveryScreenIndexedState extends ConsumerState<DiscoveryScreenIndexed> {
  late CardSwiperController _controller;
  List<NostrProfile> _displayProfiles = [];
  int _currentIndex = 0;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _controller = CardSwiperController();
    
    final initTime = DateTime.now();
    if (kDebugMode) {
      print('[PERF] DiscoveryScreenIndexed initState: ${initTime.difference(appStartTime).inMilliseconds}ms from start');
    }
    
    // Initialize profiles after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeProfiles();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _initializeProfiles() async {
    if (kDebugMode) {
      print('[Discovery] Initializing profiles with indexer...');
    }
    
    // Get the buffer service
    final bufferService = ref.read(profileBufferServiceIndexedProvider);
    
    // Check if already has profiles
    if (bufferService.hasLoadedProfiles) {
      setState(() {
        _displayProfiles = bufferService.currentProfiles.take(5).toList();
        _currentIndex = bufferService.lastViewedIndex;
        _isInitializing = false;
      });
    } else {
      // Wait for initial load
      setState(() {
        _isInitializing = true;
      });
    }
  }

  Future<bool> _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) async {
    if (previousIndex < 0 || previousIndex >= _displayProfiles.length) {
      return false;
    }

    final swipedProfile = _displayProfiles[previousIndex];
    final bufferService = ref.read(profileBufferServiceIndexedProvider);
    
    // Report interaction to indexer
    String action = 'pass';
    switch (direction) {
      case CardSwiperDirection.right:
        action = 'like';
        break;
      case CardSwiperDirection.left:
        action = 'pass';
        break;
      case CardSwiperDirection.top:
        action = 'view';
        break;
      default:
        break;
    }
    
    bufferService.reportInteraction(swipedProfile.pubkey, action);
    
    // Handle different swipe directions
    switch (direction) {
      case CardSwiperDirection.right:
        await _handleLikeProfile(swipedProfile);
        break;
      case CardSwiperDirection.left:
        await _handlePassProfile(swipedProfile);
        break;
      case CardSwiperDirection.top:
        _handleViewProfile(swipedProfile);
        break;
      default:
        break;
    }
    
    // Update current index
    if (currentIndex != null) {
      setState(() {
        _currentIndex = currentIndex;
      });
      bufferService.lastViewedIndex = currentIndex;
    }
    
    // Load more profiles if needed
    if (currentIndex != null && currentIndex >= _displayProfiles.length - 2) {
      _loadMoreProfiles();
    }
    
    return true;
  }

  Future<void> _handleLikeProfile(NostrProfile profile) async {
    final profileService = ref.read(profileServiceV2Provider);
    final keyService = ref.read(keyManagementServiceProvider);
    
    // Follow the profile
    await profileService.toggleFollowProfile(profile.pubkey, keyService);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Following ${profile.displayNameOrName}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _handlePassProfile(NostrProfile profile) async {
    final discardedService = ref.read(discardedProfilesServiceProvider);
    await discardedService.discardProfile(profile.pubkey);
    
    if (kDebugMode) {
      print('Discarded profile: ${profile.displayNameOrName}');
    }
  }

  void _handleViewProfile(NostrProfile profile) {
    context.push('/discovery/profile/${profile.pubkey}');
  }

  Future<void> _loadMoreProfiles() async {
    final bufferService = ref.read(profileBufferServiceIndexedProvider);
    
    // Get next profiles from buffer
    final newProfiles = <NostrProfile>[];
    for (int i = 0; i < 5; i++) {
      final profile = bufferService.getNextProfile();
      if (profile != null) {
        newProfiles.add(profile);
      }
    }
    
    if (newProfiles.isNotEmpty && mounted) {
      setState(() {
        _displayProfiles.addAll(newProfiles);
      });
    }
  }

  Future<void> _refreshProfiles() async {
    setState(() {
      _isInitializing = true;
    });
    
    try {
      final bufferService = ref.read(profileBufferServiceIndexedProvider);
      await bufferService.refreshBuffer();
      
      // Get new profiles
      final newProfiles = <NostrProfile>[];
      for (int i = 0; i < 5; i++) {
        final profile = bufferService.getNextProfile();
        if (profile != null) {
          newProfiles.add(profile);
        }
      }
      
      if (mounted) {
        setState(() {
          _displayProfiles = newProfiles;
          _currentIndex = 0;
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error refreshing profiles: $e');
      }
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the indexed buffer stream
    final profilesAsync = ref.watch(indexedBufferedProfilesProvider);
    final loadingAsync = ref.watch(indexedBufferLoadingProvider);
    
    // Handle loading state
    final isLoading = loadingAsync.when(
      data: (loading) => loading,
      loading: () => true,
      error: (_, __) => false,
    );
    
    // Update display profiles when buffer changes
    profilesAsync.whenData((profiles) {
      if (profiles.isNotEmpty && _displayProfiles.isEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _displayProfiles = profiles.take(5).toList();
            _isInitializing = false;
          });
        });
      }
    });
    
    if (_isInitializing || isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Finding interesting people...',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Using indexed server for faster loading',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }
    
    if (_displayProfiles.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_search, size: 64),
              const SizedBox(height: 16),
              Text(
                'No profiles available',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refreshProfiles,
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Swiper
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: CardSwiper(
                controller: _controller,
                cardsCount: _displayProfiles.length,
                numberOfCardsDisplayed: 2,
                onSwipe: _onSwipe,
                cardBuilder: (context, index, horizontalOffsetPercentage, verticalOffsetPercentage) {
                  if (index >= _displayProfiles.length) {
                    return const SizedBox();
                  }
                  
                  final profile = _displayProfiles[index];
                  
                  // Calculate swipe progress and direction
                  final swipeProgress = (horizontalOffsetPercentage.abs() > verticalOffsetPercentage.abs()
                      ? horizontalOffsetPercentage.abs()
                      : verticalOffsetPercentage.abs()) / 100;
                  
                  CardSwiperDirection swipeDirection = CardSwiperDirection.none;
                  if (horizontalOffsetPercentage.abs() > verticalOffsetPercentage.abs()) {
                    swipeDirection = horizontalOffsetPercentage > 0 
                        ? CardSwiperDirection.right 
                        : CardSwiperDirection.left;
                  } else if (verticalOffsetPercentage < -20) {
                    swipeDirection = CardSwiperDirection.top;
                  }
                  
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      ProfileCardNew(
                        name: profile.displayNameOrName,
                        imageUrl: profile.picture ?? '',
                        bio: profile.about ?? '',
                        onTap: () {
                          context.push('/discovery/profile/${profile.pubkey}');
                        },
                        isFollowed: ref.read(profileServiceV2Provider).isProfileFollowed(profile.pubkey),
                      ),
                      // Show swipe overlay when swiping
                      if (swipeProgress > 0.05)
                        AnimatedOpacity(
                          opacity: swipeProgress.clamp(0.0, 1.0),
                          duration: const Duration(milliseconds: 50),
                          child: SwipeOverlay(
                            direction: swipeDirection,
                            progress: swipeProgress,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            
            // Profile counter
            Positioned(
              top: 8,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${_displayProfiles.length}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            
            // Refresh button
            Positioned(
              top: 8,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refreshProfiles,
              ),
            ),
          ],
        ),
      ),
    );
  }
}