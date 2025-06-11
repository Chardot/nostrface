import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/features/profile_discovery/presentation/widgets/profile_card_new.dart';
import 'package:nostrface/main.dart'; // For appStartTime

class SwipeHistoryItem {
  final NostrProfile profile;
  final CardSwiperDirection direction;
  final DateTime timestamp;
  
  SwipeHistoryItem({
    required this.profile,
    required this.direction,
    required this.timestamp,
  });
}

class DiscoveryScreenIndexed extends ConsumerStatefulWidget {
  const DiscoveryScreenIndexed({Key? key}) : super(key: key);

  @override
  ConsumerState<DiscoveryScreenIndexed> createState() => _DiscoveryScreenIndexedState();
}

class _DiscoveryScreenIndexedState extends ConsumerState<DiscoveryScreenIndexed> {
  late CardSwiperController _controller;
  List<NostrProfile> _displayProfiles = [];
  final List<SwipeHistoryItem> _swipeHistory = [];

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
    if (bufferService.hasLoadedProfiles && bufferService.currentProfiles.isNotEmpty) {
      if (kDebugMode) {
        print('[Discovery] Buffer has ${bufferService.currentProfiles.length} profiles ready');
      }
      setState(() {
        _displayProfiles = bufferService.currentProfiles.take(5).toList();
      });
    } else {
      if (kDebugMode) {
        print('[Discovery] Buffer not ready yet, waiting for profiles...');
      }
      // Wait for initial load - the stream will update us
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
    
    // Add to swipe history for undo
    _swipeHistory.add(SwipeHistoryItem(
      profile: swipedProfile,
      direction: direction,
      timestamp: DateTime.now(),
    ));
    
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
    
    // Limit swipe history to last 10 swipes
    if (_swipeHistory.length > 10) {
      _swipeHistory.removeAt(0);
    }
    
    // Defer the state update to avoid changing cards during animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      
      setState(() {
        _displayProfiles.removeAt(previousIndex);
        
        // Add a new profile from the buffer
        final newProfile = bufferService.getNextProfile();
        if (newProfile != null) {
          _displayProfiles.add(newProfile);
        }
        
      });
    });
    
    // Load more profiles if buffer is running low
    if (_displayProfiles.length < 3) {
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


  @override
  Widget build(BuildContext context) {
    // Watch the indexed buffer stream
    final profilesAsync = ref.watch(indexedBufferedProfilesProvider);
    
    
    // Update display profiles when buffer changes
    profilesAsync.whenData((profiles) {
      if (kDebugMode) {
        print('[Discovery] Buffer stream data: ${profiles.length} profiles, _displayProfiles: ${_displayProfiles.length}');
      }
      if (profiles.isNotEmpty && _displayProfiles.isEmpty && mounted) {
        if (kDebugMode) {
          print('[Discovery] Updating display profiles from stream: ${profiles.take(5).map((p) => p.displayNameOrName).toList()}');
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _displayProfiles = profiles.take(5).toList();
            });
          }
        });
      }
    });
    
    // Always show loading if we don't have display profiles yet
    if (_displayProfiles.isEmpty) {
      if (kDebugMode) {
        print('[Discovery] No display profiles yet, showing loading screen');
      }
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
              if (profilesAsync.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Error: ${profilesAsync.error}',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Swiper
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: CardSwiper(
                  controller: _controller,
                  cardsCount: _displayProfiles.length,
                  numberOfCardsDisplayed: _displayProfiles.length >= 3 ? 3 : _displayProfiles.length,
                  backCardOffset: const Offset(40, 40),
                  onSwipe: _onSwipe,
                cardBuilder: (context, index, horizontalOffsetPercentage, verticalOffsetPercentage) {
                  if (index >= _displayProfiles.length) {
                    return const SizedBox();
                  }
                  
                  final profile = _displayProfiles[index];
                  
                  if (kDebugMode) {
                    print('[Discovery] Card $index - Displaying profile: ${profile.pubkey}');
                    print('[Discovery] Card $index - Profile picture URL: ${profile.picture}');
                    print('[Discovery] Card $index - Profile name: ${profile.displayNameOrName}');
                  }
                  
                  return Stack(
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
                      // Like overlay (swipe right)
                      if (horizontalOffsetPercentage > 50)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.green.withOpacity(
                                ((horizontalOffsetPercentage - 50) / 50 * 0.5).clamp(0.0, 0.5),
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.favorite,
                                size: 100,
                                color: Colors.white.withOpacity(
                                  ((horizontalOffsetPercentage - 50) / 50).clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Nope overlay (swipe left)
                      if (horizontalOffsetPercentage < -50)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.red.withOpacity(
                                ((horizontalOffsetPercentage.abs() - 50) / 50 * 0.5).clamp(0.0, 0.5),
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.close,
                                size: 100,
                                color: Colors.white.withOpacity(
                                  ((horizontalOffsetPercentage.abs() - 50) / 50).clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Super like overlay (swipe up)
                      if (verticalOffsetPercentage < -50)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              color: Colors.blue.withOpacity(
                                ((verticalOffsetPercentage.abs() - 50) / 50 * 0.5).clamp(0.0, 0.5),
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.star,
                                size: 100,
                                color: Colors.white.withOpacity(
                                  ((verticalOffsetPercentage.abs() - 50) / 50).clamp(0.0, 1.0),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
                ),
              ),
            ),
            // Bottom action panel
            Container(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Swipe Direction Indicators',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildIndicator(
                            Icons.close,
                            'Left',
                            Colors.red,
                            'Nope',
                            () => _handleButtonSwipe(CardSwiperDirection.left),
                          ),
                          _buildIndicator(
                            Icons.favorite,
                            'Right',
                            Colors.green,
                            'Like',
                            () => _handleButtonSwipe(CardSwiperDirection.right),
                          ),
                          _buildIndicator(
                            Icons.star,
                            'Up',
                            Colors.blue,
                            'Super Like',
                            () => _handleButtonSwipe(CardSwiperDirection.top),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_swipeHistory.isNotEmpty)
                        TextButton.icon(
                          onPressed: _handleUndo,
                          icon: const Icon(Icons.undo, size: 20),
                          label: const Text('Undo'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.orange,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicator(
    IconData icon,
    String direction,
    Color color,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              direction,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleButtonSwipe(CardSwiperDirection direction) async {
    if (_displayProfiles.isEmpty) return;
    
    // The swipe will be recorded in _onSwipe callback
    
    _controller.swipe(direction);
  }

  Future<void> _handleUndo() async {
    if (_swipeHistory.isEmpty) return;
    
    final lastSwipe = _swipeHistory.removeLast();
    final profile = lastSwipe.profile;
    
    // Undo the action based on swipe direction
    switch (lastSwipe.direction) {
      case CardSwiperDirection.right:
        // Undo follow
        final profileService = ref.read(profileServiceV2Provider);
        final keyService = ref.read(keyManagementServiceProvider);
        await profileService.toggleFollowProfile(profile.pubkey, keyService);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unfollowed ${profile.displayNameOrName}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        break;
      case CardSwiperDirection.left:
        // Undo discard
        final discardedService = ref.read(discardedProfilesServiceProvider);
        await discardedService.undiscardProfile(profile.pubkey);
        break;
      case CardSwiperDirection.top:
        // Nothing to undo for view action
        break;
      default:
        break;
    }
    
    // Add the profile back to the beginning of the display list
    setState(() {
      _displayProfiles.insert(0, profile);
    });
  }
}