import 'package:card_swiper/card_swiper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/profile_service.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:nostrface/features/profile_discovery/presentation/widgets/profile_card.dart';

// Provider to track the current profile index in the swiper
// Using autoDispose: false to ensure it persists across widget rebuilds
final currentProfileIndexProvider = StateProvider<int>((ref) => 0, name: 'currentProfileIndex');

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  late SwiperController _swiperController;
  bool _isLoading = false;
  

  @override
  void initState() {
    super.initState();
    _swiperController = SwiperController();
    
    // Pre-load authentication status to avoid delays on first follow
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(isLoggedInProvider);
        print('[Discovery] Pre-loading authentication status');
      }
    });
    
    // Load profiles after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Get the buffer service
        final bufferService = ref.read(profileBufferServiceProvider);
        
        // If the buffer already has profiles, restore the last position
        if (bufferService.hasLoadedProfiles) {
          if (kDebugMode) {
            print('Restoring to profile index: ${bufferService.lastViewedIndex}');
          }
          
          // Use a short delay to ensure the swiper is ready
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              // Update the current index in state
              ref.read(currentProfileIndexProvider.notifier).state = 
                  bufferService.lastViewedIndex;
              
              // Move the swiper to the saved position
              if (bufferService.lastViewedIndex > 0) {
                _swiperController.move(bufferService.lastViewedIndex);
              }
            }
          });
        } else {
          // If no profiles in buffer yet, trigger a refresh
          _refreshProfiles();
        }
      }
    });
  }

  @override
  void dispose() {
    // Dispose the controller first
    _swiperController.dispose();
    
    // Don't access ref in dispose() as the widget might already be disposed
    super.dispose();
  }

  Future<void> _refreshProfiles() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    
    try {
      // Refresh the profile buffer
      final bufferService = ref.read(profileBufferServiceProvider);
      await bufferService.refreshBuffer();
      
      // Reset swiper to beginning
      _swiperController.move(0);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch the buffered profiles provider
    final profilesAsync = ref.watch(bufferedProfilesProvider);
    final bufferService = ref.watch(profileBufferServiceProvider);

    return Scaffold(
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
            // Check if initial profiles are still loading
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
          
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Swiper(
                    itemBuilder: (BuildContext context, int index) {
                      final profile = profiles[index];
                      final isFollowedAsync = ref.watch(isProfileFollowedProvider(profile.pubkey));
                      final isFollowed = isFollowedAsync.valueOrNull ?? false;
                      return ProfileCard(
                        name: profile.displayNameOrName,
                        imageUrl: profile.picture ?? 'https://picsum.photos/500/500?random=$index',
                        bio: profile.about ?? 'No bio available',
                        isFollowed: isFollowed,
                        onTap: () {
                          context.go('/discovery/profile/${profile.pubkey}');
                        },
                        onImageError: (imageUrl) async {
                          if (kDebugMode) {
                            print('Image failed for profile ${profile.pubkey}: $imageUrl');
                          }
                          
                          // Mark this image as failed
                          final failedImagesService = ref.read(failedImagesServiceProvider);
                          await failedImagesService.markImageAsFailed(imageUrl);
                          
                          // Remove this profile from the buffer
                          final bufferService = ref.read(profileBufferServiceProvider);
                          bufferService.removeProfile(profile.pubkey);
                        },
                      );
                    },
                    itemCount: profiles.length,
                    controller: _swiperController,
                    layout: SwiperLayout.STACK,
                    itemWidth: MediaQuery.of(context).size.width * 0.85,
                    itemHeight: MediaQuery.of(context).size.height * 0.7,
                    onIndexChanged: (index) {
                      // Update the current profile index in the provider
                      ref.read(currentProfileIndexProvider.notifier).state = index;
                      
                      // Save the current position for persistence
                      final bufferService = ref.read(profileBufferServiceProvider);
                      bufferService.lastViewedIndex = index;
                      
                      // Check if we need to prefetch more profiles using our buffer service
                      bufferService.checkBufferState(index);
                    },
                  ),
                ),
              ),
              // Show loading indicator when fetching more profiles
              Consumer(
                builder: (context, ref, child) {
                  final bufferService = ref.watch(profileBufferServiceProvider);
                  if (bufferService.isFetching && !bufferService.isLoadingInitial) {
                    return const LinearProgressIndicator();
                  }
                  return const SizedBox.shrink();
                },
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Consumer(
                      builder: (context, ref, child) {
                        final currentIndex = ref.watch(currentProfileIndexProvider);
                        final hasProfiles = profiles.isNotEmpty && currentIndex < profiles.length;
                        
                        return _buildActionButton(
                          icon: Icons.close,
                          color: Colors.red,
                          onPressed: hasProfiles ? () async {
                            // Get the current profile
                            final profile = profiles[currentIndex];
                            
                            // Discard the profile
                            final discardedService = ref.read(discardedProfilesServiceProvider);
                            await discardedService.discardProfile(profile.pubkey);
                            
                            // Update the discarded count
                            ref.read(discardedProfilesCountProvider.notifier).state = discardedService.discardedCount;
                            
                            // Remove from buffer
                            final bufferService = ref.read(profileBufferServiceProvider);
                            bufferService.removeProfile(profile.pubkey);
                            
                            // Show feedback
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Discarded ${profile.displayNameOrName}'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          } : null,
                        );
                      },
                    ),
                    Consumer(
                      builder: (context, ref, child) {
                        final currentIndex = ref.watch(currentProfileIndexProvider);
                        final hasProfiles = profiles.isNotEmpty && currentIndex < profiles.length;
                        
                        return _buildActionButton(
                          icon: Icons.message,
                          color: Colors.blue,
                          onPressed: hasProfiles ? () async {
                            // Check if user is logged in
                            final isLoggedIn = await ref.read(isLoggedInProvider.future);
                            
                            if (!isLoggedIn && context.mounted) {
                              // Show dialog to prompt user to log in
                              showDialog(
                                context: context,
                                builder: (BuildContext dialogContext) => AlertDialog(
                                  key: const Key('discovery_dm_login_dialog'),
                                  title: const Text('Login Required'),
                                  content: const Text(
                                    'You need to be logged in to send direct messages. Would you like to log in now?'
                                  ),
                                  actions: [
                                    TextButton(
                                      key: const Key('discovery_dm_login_cancel'),
                                      onPressed: () => Navigator.of(dialogContext).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      key: const Key('discovery_dm_login_confirm'),
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
                            
                            // Navigate to profile screen with DM intent
                            final profile = profiles[currentIndex];
                            if (context.mounted) {
                              // For now, navigate to profile screen
                              // TODO: When DM screen is implemented, navigate directly to DM
                              context.go('/discovery/profile/${profile.pubkey}');
                            }
                          } : null,
                        );
                      },
                    ),
                    Builder(
                      builder: (context) {
                        final currentIndex = ref.read(currentProfileIndexProvider);
                        if (currentIndex < 0 || currentIndex >= profiles.length) {
                          return _buildActionButton(
                            icon: Icons.favorite,
                            color: Colors.green,
                            onPressed: null,
                          );
                        }
                        
                        final profile = profiles[currentIndex];
                        
                        // Get initial state only once
                        final initialFollowed = ref.read(isProfileFollowedSimpleProvider(profile.pubkey));
                        
                        return _buildActionButton(
                          icon: Icons.favorite_border,
                          color: Colors.white,
                          iconColor: Colors.green,
                          onPressed: () {
                            final buttonPressTime = DateTime.now();
                            print('\n=== FOLLOW BUTTON PRESSED (SWIPE RIGHT) ===');
                            print('Absolute time: ${buttonPressTime.hour.toString().padLeft(2, '0')}:${buttonPressTime.minute.toString().padLeft(2, '0')}:${buttonPressTime.second.toString().padLeft(2, '0')}.${buttonPressTime.millisecond.toString().padLeft(3, '0')}');
                            print('Profile: ${profile.displayNameOrName} (${profile.pubkey})');
                            
                            // Check if user is logged in first
                            final isLoggedInAsync = ref.read(isLoggedInProvider);
                            final isLoggedIn = isLoggedInAsync.valueOrNull ?? false;
                            
                            if (!isLoggedIn && context.mounted) {
                              showDialog(
                                context: context,
                                builder: (BuildContext dialogContext) => AlertDialog(
                                  key: const Key('discovery_login_dialog'),
                                  title: const Text('Login Required'),
                                  content: const Text(
                                    'You need to be logged in to follow profiles. Would you like to log in now?'
                                  ),
                                  actions: [
                                    TextButton(
                                      key: const Key('discovery_login_cancel'),
                                      onPressed: () => Navigator.of(dialogContext).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      key: const Key('discovery_login_confirm'),
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
                            
                            // Store the profile info for the follow action
                            final profileToFollow = profile;
                            final wasFollowed = initialFollowed;
                            
                            // Just trigger the swipe animation
                            print('Triggering swipe right animation...');
                            _swiperController.next();
                            print('=== SWIPE TRIGGERED ===');
                            
                            // Show immediate feedback
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Following ${profileToFollow.displayNameOrName}...'),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                            
                            // Wait for the card to be swiped away then execute follow
                            Future.delayed(const Duration(milliseconds: 300), () {
                              print('\n=== EXECUTING FOLLOW ACTION (CARD OUT OF VIEW) ===');
                              
                              final profileService = ref.read(profileServiceProvider);
                              if (!wasFollowed) {
                                profileService.optimisticallyFollow(profileToFollow.pubkey);
                              }
                              
                              // Publish to relays
                              ref.read(publishFollowEventProvider.future).then((result) {
                                if (!result.isSuccess && context.mounted) {
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
                            });
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () {
          // Check if initial profiles are being loaded
          final bufferService = ref.read(profileBufferServiceProvider);
          if (bufferService.hasLoadedProfiles && bufferService.currentProfiles.isNotEmpty) {
            // We have profiles in buffer, show them while more load in background
            final profiles = bufferService.currentProfiles;
            return Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Swiper(
                      itemBuilder: (BuildContext context, int index) {
                        final profile = profiles[index];
                        final isFollowedAsync = ref.watch(isProfileFollowedProvider(profile.pubkey));
                        return ProfileCard(
                          name: profile.displayNameOrName,
                          imageUrl: profile.picture ?? 'https://picsum.photos/500/500?random=$index',
                          bio: profile.about ?? 'No bio available',
                          isFollowed: isFollowedAsync.valueOrNull ?? false,
                          onTap: () {
                            context.go('/discovery/profile/${profile.pubkey}');
                          },
                          onImageError: (imageUrl) async {
                            if (kDebugMode) {
                              print('Image failed for profile ${profile.pubkey}: $imageUrl');
                            }
                            
                            // Mark this image as failed
                            final failedImagesService = ref.read(failedImagesServiceProvider);
                            await failedImagesService.markImageAsFailed(imageUrl);
                            
                            // Remove this profile from the buffer
                            final bufferService = ref.read(profileBufferServiceProvider);
                            bufferService.removeProfile(profile.pubkey);
                          },
                        );
                      },
                      itemCount: profiles.length,
                      controller: _swiperController,
                      layout: SwiperLayout.STACK,
                      itemWidth: MediaQuery.of(context).size.width * 0.85,
                      itemHeight: MediaQuery.of(context).size.height * 0.7,
                      onIndexChanged: (index) {
                        ref.read(currentProfileIndexProvider.notifier).state = index;
                        final bufferService = ref.read(profileBufferServiceProvider);
                        bufferService.checkBufferState(index);
                      },
                    ),
                  ),
                ),
                // Show loading indicator in app bar area
                if (bufferService.isFetching)
                  const LinearProgressIndicator(),
              ],
            );
          }
          
          // Otherwise show initial loading screen
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
    Color? iconColor,
    required VoidCallback? onPressed,
  }) {
    return Material(
      elevation: 4,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Ink(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onPressed == null ? Colors.grey : color,
          ),
          child: Container(
            padding: const EdgeInsets.all(16.0),
            child: Icon(
              icon,
              color: iconColor ?? Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}