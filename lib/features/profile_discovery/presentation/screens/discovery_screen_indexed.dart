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
    
    // Load initial profiles from buffer using getNextProfile
    final initialProfiles = <NostrProfile>[];
    for (int i = 0; i < 5; i++) {
      final profile = bufferService.getNextProfile();
      if (profile != null) {
        initialProfiles.add(profile);
      }
    }
    
    if (initialProfiles.isNotEmpty) {
      if (kDebugMode) {
        print('[Discovery] Got ${initialProfiles.length} initial profiles from buffer');
      }
      setState(() {
        _displayProfiles = initialProfiles;
      });
    } else {
      if (kDebugMode) {
        print('[Discovery] No profiles available yet, waiting for buffer to load...');
      }
      // The stream watcher in build() will update us when profiles arrive
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
      // If we don't have any display profiles and buffer has some, grab them
      if (_displayProfiles.isEmpty && profiles.isNotEmpty && mounted) {
        if (kDebugMode) {
          print('[Discovery] No display profiles, fetching from buffer...');
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final bufferService = ref.read(profileBufferServiceIndexedProvider);
            final newProfiles = <NostrProfile>[];
            for (int i = 0; i < 5; i++) {
              final profile = bufferService.getNextProfile();
              if (profile != null) {
                newProfiles.add(profile);
              }
            }
            if (newProfiles.isNotEmpty) {
              setState(() {
                _displayProfiles = newProfiles;
              });
            }
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    Icons.close,
                    Colors.red,
                    () => _handleButtonSwipe(CardSwiperDirection.left),
                  ),
                  _buildActionButton(
                    Icons.favorite,
                    Colors.green,
                    () => _handleButtonSwipe(CardSwiperDirection.right),
                  ),
                  _buildActionButton(
                    Icons.star,
                    Colors.blue,
                    () => _handleButtonSwipe(CardSwiperDirection.top),
                  ),
                  if (_swipeHistory.isNotEmpty)
                    _buildActionButton(
                      Icons.undo,
                      Colors.orange,
                      _handleUndo,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: color,
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: Colors.white,
            size: 28,
          ),
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