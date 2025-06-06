import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/profile_service.dart';
import 'package:nostrface/features/profile_discovery/presentation/widgets/profile_card_new.dart';
import 'package:nostrface/features/profile_discovery/presentation/widgets/swipe_overlays.dart';
import 'package:nostrface/features/direct_messages/presentation/widgets/dm_composer.dart';
import 'package:nostrface/main.dart'; // For appStartTime

// Provider to track the current profile index
final currentProfileIndexProvider = StateProvider<int>((ref) => 0, name: 'currentProfileIndex');

// Provider to track discarded profiles count
final discardedProfilesCountProvider = StateProvider<int>((ref) => 0);

class DiscoveryScreenNew extends ConsumerStatefulWidget {
  const DiscoveryScreenNew({Key? key}) : super(key: key);

  @override
  ConsumerState<DiscoveryScreenNew> createState() => _DiscoveryScreenNewState();
}

class _DiscoveryScreenNewState extends ConsumerState<DiscoveryScreenNew> {
  late CardSwiperController _controller;
  bool _isLoading = false;
  bool _hasLoggedFirstDisplay = false;
  // CardSwiperDirection _currentSwipeDirection = CardSwiperDirection.none;
  // double _swipeProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = CardSwiperController();
    
    final initTime = DateTime.now();
    print('[PERF] DiscoveryScreen initState: ${initTime.difference(appStartTime).inMilliseconds}ms from start');
    
    // Pre-load authentication status
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(isLoggedInProvider);
        print('[Discovery] Pre-loading authentication status');
      }
    });
    
    // Load profiles after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final bufferService = ref.read(profileBufferServiceProvider);
        
        if (bufferService.hasLoadedProfiles) {
          if (kDebugMode) {
            print('Restoring to profile index: ${bufferService.lastViewedIndex}');
          }
          
          // Update the current index
          ref.read(currentProfileIndexProvider.notifier).state = 
              bufferService.lastViewedIndex;
        } else {
          _refreshProfiles();
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshProfiles() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    
    try {
      final bufferService = ref.read(profileBufferServiceProvider);
      await bufferService.refreshBuffer();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) async {
    if (previousIndex < 0) return false;
    
    final profiles = ref.read(bufferedProfilesProvider).valueOrNull ?? [];
    if (previousIndex >= profiles.length) return false;
    
    print('\n========== SWIPE EVENT ==========');
    print('[Card swiped] Direction: $direction');
    print('Previous index: $previousIndex, Current index: $currentIndex');
    print('Total profiles: ${profiles.length}');
    
    final profile = profiles[previousIndex];
    final bufferService = ref.read(profileBufferServiceProvider);
    
    switch (direction) {
      case CardSwiperDirection.left:
        // Nope - Discard profile
        final discardedService = ref.read(discardedProfilesServiceProvider);
        await discardedService.discardProfile(profile.pubkey);
        ref.read(discardedProfilesCountProvider.notifier).state = discardedService.discardedCount;
        // Don't remove from buffer immediately - let the swiper handle the index
        // bufferService.removeProfile(profile.pubkey);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Discarded ${profile.displayNameOrName}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        break;
        
      case CardSwiperDirection.right:
        // Like - Follow profile
        final isLoggedIn = await ref.read(isLoggedInProvider.future);
        
        if (!isLoggedIn && mounted) {
          _showLoginDialog();
          return false; // Cancel the swipe
        }
        
        final profileService = ref.read(profileServiceProvider);
        profileService.optimisticallyFollow(profile.pubkey);
        // Don't remove from buffer immediately - let the swiper handle the index
        // bufferService.removeProfile(profile.pubkey);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Following ${profile.displayNameOrName}...'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
        
        // Publish to relays
        ref.read(publishFollowEventProvider.future).then((result) {
          if (!result.isSuccess && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Failed to publish follow event (${result.successCount}/${result.totalRelays} relays)'
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }).catchError((e) {
          print('Error publishing follow event: $e');
        });
        break;
        
      case CardSwiperDirection.top:
        // Super Like - Follow with emphasis
        final isLoggedIn = await ref.read(isLoggedInProvider.future);
        
        if (!isLoggedIn && mounted) {
          _showLoginDialog();
          return false;
        }
        
        final profileService = ref.read(profileServiceProvider);
        profileService.optimisticallyFollow(profile.pubkey);
        // Don't remove from buffer immediately - let the swiper handle the index
        // bufferService.removeProfile(profile.pubkey);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Super liked ${profile.displayNameOrName}! ⭐'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.blue,
            ),
          );
        }
        
        // Publish follow
        ref.read(publishFollowEventProvider.future);
        break;
        
      case CardSwiperDirection.bottom:
        // Pass - Skip for now
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Passed on ${profile.displayNameOrName}'),
              duration: const Duration(seconds: 1),
              backgroundColor: Colors.orange,
            ),
          );
        }
        break;
        
      default:
        break;
    }
    
    // Update current index
    if (currentIndex != null) {
      ref.read(currentProfileIndexProvider.notifier).state = currentIndex;
      bufferService.lastViewedIndex = currentIndex;
      bufferService.checkBufferState(currentIndex);
      
      print('\n[After swipe]');
      if (currentIndex < profiles.length) {
        print('[First]  ${profiles[currentIndex].pubkey.substring(0, 16)}... (${profiles[currentIndex].displayNameOrName})');
        if (currentIndex + 1 < profiles.length) {
          print('[Second] ${profiles[currentIndex + 1].pubkey.substring(0, 16)}... (${profiles[currentIndex + 1].displayNameOrName})');
        }
      }
    }
    
    return true;
  }

  void _showLoginDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Login Required'),
        content: const Text(
          'You need to be logged in to follow profiles. Would you like to log in now?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push('/login');
            },
            child: const Text('Log In'),
          ),
        ],
      ),
    );
  }

  void _showDMComposer(NostrProfile profile) async {
    final isLoggedIn = await ref.read(isLoggedInProvider.future);
    
    if (!isLoggedIn && mounted) {
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Login Required'),
          content: const Text(
            'You need to be logged in to send direct messages. Would you like to log in now?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.push('/login');
              },
              child: const Text('Log In'),
            ),
          ],
        ),
      );
      return;
    }
    
    if (mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        builder: (BuildContext sheetContext) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: DirectMessageComposer(
              recipient: profile,
              onMessageSent: () {
                Navigator.of(sheetContext).pop();
              },
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(bufferedProfilesProvider);
    final bufferService = ref.watch(profileBufferServiceProvider);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('NostrFace'),
            if (bufferService.currentProfiles.isNotEmpty)
              Text(
                '${bufferService.currentProfiles.length} profiles loaded',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (bufferService.isFetching && !bufferService.isLoadingInitial)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshProfiles,
          ),
        ],
      ),
      body: profilesAsync.when(
        data: (profiles) {
          if (profiles.isEmpty) {
            final bufferService = ref.read(profileBufferServiceProvider);
            if (bufferService.isLoadingInitial) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading initial profiles...'),
                  ],
                ),
              );
            }
            
            return const Center(
              child: Text(
                'No profiles found.\nTry refreshing or check your relay connections.',
                textAlign: TextAlign.center,
              ),
            );
          }
          
          // Log first profile display
          if (!_hasLoggedFirstDisplay && profiles.isNotEmpty) {
            _hasLoggedFirstDisplay = true;
            final firstDisplayTime = DateTime.now();
            print('[PERF] First profiles displayed: ${firstDisplayTime.difference(appStartTime).inMilliseconds}ms from start');
            print('[PERF] Profile count: ${profiles.length}');
          }
          
          return Stack(
            children: [
              // Card swiper
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 80.0,
                ),
                child: CardSwiper(
                  controller: _controller,
                  cardsCount: profiles.length,
                  onSwipe: _onSwipe,
                  onUndo: (previousIndex, currentIndex, direction) {
                    ref.read(currentProfileIndexProvider.notifier).state = currentIndex;
                    return true;
                  },
                  numberOfCardsDisplayed: 3,
                  backCardOffset: const Offset(0, 40),
                  padding: const EdgeInsets.all(0),
                  cardBuilder: (
                    context,
                    index,
                    horizontalOffsetPercentage,
                    verticalOffsetPercentage,
                  ) {
                    final profile = profiles[index];
                    final isFollowedAsync = ref.watch(isProfileFollowedProvider(profile.pubkey));
                    final isFollowed = isFollowedAsync.valueOrNull ?? false;
                    
                    // Debug logging for card order - only log when building the first card
                    if (index == 0) {
                      print('\n[Card Stack Status]');
                      print('[First]  ${profile.pubkey.substring(0, 16)}... (${profile.displayNameOrName})');
                      if (profiles.length > 1) {
                        print('[Second] ${profiles[1].pubkey.substring(0, 16)}... (${profiles[1].displayNameOrName})');
                      }
                    }
                    
                    // Calculate swipe direction and progress from integer percentages
                    CardSwiperDirection swipeDirection = CardSwiperDirection.none;
                    double swipeProgress = 0.0;
                    
                    // horizontalOffsetPercentage and verticalOffsetPercentage are integers representing
                    // percentage of threshold reached (can exceed 100)
                    final hOffset = horizontalOffsetPercentage;
                    final vOffset = verticalOffsetPercentage;
                    
                    if (hOffset.abs() > vOffset.abs()) {
                      swipeProgress = (hOffset.abs() / 100.0).clamp(0.0, 1.0);
                      swipeDirection = hOffset > 0 
                          ? CardSwiperDirection.right 
                          : CardSwiperDirection.left;
                    } else if (vOffset != 0) {
                      swipeProgress = (vOffset.abs() / 100.0).clamp(0.0, 1.0);
                      swipeDirection = vOffset > 0 
                          ? CardSwiperDirection.bottom 
                          : CardSwiperDirection.top;
                    }
                    
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        ProfileCardNew(
                          name: profile.displayNameOrName,
                          imageUrl: profile.picture ?? 'https://picsum.photos/500/800?random=$index',
                          bio: profile.about ?? 'No bio available',
                          isFollowed: isFollowed,
                          onTap: () {
                            context.go('/discovery/profile/${profile.pubkey}');
                          },
                          onImageError: (imageUrl) async {
                            if (kDebugMode) {
                              print('Image failed for profile ${profile.pubkey}: $imageUrl');
                            }
                            
                            final failedImagesService = ref.read(failedImagesServiceProvider);
                            await failedImagesService.markImageAsFailed(imageUrl);
                            
                            final bufferService = ref.read(profileBufferServiceProvider);
                            bufferService.removeProfile(profile.pubkey);
                          },
                        ),
                        // Swipe overlay - show when card is being swiped
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
                  scale: 0.9,
                  isLoop: false,
                ),
              ),
              
              // Action buttons at bottom
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Undo button
                    _buildActionButton(
                      icon: Icons.undo,
                      color: Colors.amber,
                      onPressed: profiles.isNotEmpty
                          ? () => _controller.undo()
                          : null,
                      size: 50,
                    ),
                    // Discard button
                    _buildActionButton(
                      icon: Icons.close,
                      color: Colors.red,
                      onPressed: profiles.isNotEmpty
                          ? () => _controller.swipe(CardSwiperDirection.left)
                          : null,
                      size: 60,
                    ),
                    // Super like button
                    _buildActionButton(
                      icon: Icons.star,
                      color: Colors.blue,
                      onPressed: profiles.isNotEmpty
                          ? () => _controller.swipe(CardSwiperDirection.top)
                          : null,
                      size: 60,
                    ),
                    // Like button
                    _buildActionButton(
                      icon: Icons.favorite,
                      color: Colors.green,
                      onPressed: profiles.isNotEmpty
                          ? () => _controller.swipe(CardSwiperDirection.right)
                          : null,
                      size: 60,
                    ),
                    // Message button
                    _buildActionButton(
                      icon: Icons.message,
                      color: Colors.purple,
                      onPressed: profiles.isNotEmpty
                          ? () {
                              final currentIndex = ref.read(currentProfileIndexProvider);
                              if (currentIndex >= 0 && currentIndex < profiles.length) {
                                _showDMComposer(profiles[currentIndex]);
                              }
                            }
                          : null,
                      size: 50,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () {
          final bufferService = ref.read(profileBufferServiceProvider);
          if (bufferService.hasLoadedProfiles && bufferService.currentProfiles.isNotEmpty) {
            // Show existing profiles while loading more
            final profiles = bufferService.currentProfiles;
            return Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 80.0,
                  ),
                  child: CardSwiper(
                    controller: _controller,
                    cardsCount: profiles.length,
                    onSwipe: _onSwipe,
                    numberOfCardsDisplayed: 3,
                    backCardOffset: const Offset(0, 40),
                    padding: const EdgeInsets.all(0),
                    cardBuilder: (context, index, hThreshold, vThreshold) {
                      final profile = profiles[index];
                      return ProfileCardNew(
                        name: profile.displayNameOrName,
                        imageUrl: profile.picture ?? 'https://picsum.photos/500/800?random=$index',
                        bio: profile.about ?? 'No bio available',
                        isFollowed: false,
                        onTap: () {
                          context.go('/discovery/profile/${profile.pubkey}');
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          }
          
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading profiles from Nostr relays...'),
              ],
            ),
          );
        },
        error: (error, stackTrace) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 60,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading profiles: ${error.toString()}',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _refreshProfiles,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    double size = 56,
  }) {
    final buttonSize = size;
    final iconSize = size * 0.5;
    
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Ink(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onPressed == null ? Colors.grey[300] : Colors.white,
          ),
          child: Container(
            width: buttonSize,
            height: buttonSize,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: onPressed == null ? Colors.grey : color,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}