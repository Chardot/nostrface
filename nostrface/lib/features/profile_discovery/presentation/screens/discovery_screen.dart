import 'package:card_swiper/card_swiper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/profile_service.dart';
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
    // Make sure we don't update state after dispose
    final savedIndex = ref.read(currentProfileIndexProvider);
    
    // Save the current index to the buffer service before disposing
    if (savedIndex > 0) {
      final bufferService = ref.read(profileBufferServiceProvider);
      bufferService.lastViewedIndex = savedIndex;
    }
    
    _swiperController.dispose();
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
    final isFetchingMore = ref.watch(isFetchingMoreProfilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NostrFace'),
        centerTitle: true,
        actions: [
          if (isFetchingMore)
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
            return const Center(
              child: Text(
                'No trusted profiles found.\nWe filter profiles by trust score for your safety.\nTry refreshing or check your relay connections.',
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
                      final isFollowed = ref.watch(isProfileFollowedProvider(profile.pubkey));
                      return ProfileCard(
                        name: profile.displayNameOrName,
                        imageUrl: profile.picture ?? 'https://picsum.photos/500/500?random=$index',
                        bio: profile.about ?? 'No bio available',
                        isFollowed: isFollowed,
                        onTap: () {
                          context.go('/discovery/profile/${profile.pubkey}');
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
                          onPressed: hasProfiles ? () {
                            _swiperController.next();
                          } : null,
                        );
                      },
                    ),
                    Consumer(
                      builder: (context, ref, child) {
                        final currentIndex = ref.watch(currentProfileIndexProvider);
                        final hasProfiles = profiles.isNotEmpty && currentIndex < profiles.length;
                        
                        return _buildActionButton(
                          icon: Icons.star,
                          color: Colors.blue,
                          onPressed: hasProfiles ? () {
                            // TODO: Save to favorites
                            _swiperController.next();
                          } : null,
                        );
                      },
                    ),
                    Consumer(
                      builder: (context, ref, child) {
                        final currentIndex = ref.watch(currentProfileIndexProvider);
                        if (currentIndex < 0 || currentIndex >= profiles.length) {
                          return _buildActionButton(
                            icon: Icons.favorite,
                            color: Colors.green,
                            onPressed: null,
                          );
                        }
                        
                        final profile = profiles[currentIndex];
                        final isFollowed = ref.watch(isProfileFollowedProvider(profile.pubkey));
                        
                        return _buildActionButton(
                          icon: isFollowed ? Icons.favorite : Icons.favorite_border,
                          color: isFollowed ? Colors.red : Colors.green,
                          onPressed: () async {
                            // Check if user is logged in
                            final isLoggedIn = await ref.read(isLoggedInProvider.future);
                            
                            if (isLoggedIn == false && context.mounted) {
                              // Show dialog to prompt user to log in
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
                                        // Use push to preserve the stack (we want to return to discovery after login)
                                        context.push('/login');
                                      },
                                      child: const Text('Log In'),
                                    ),
                                  ],
                                ),
                              );
                              return;
                            }
                            
                            // If logged in, toggle follow status
                            final result = await ref.read(followProfileProvider(profile.pubkey).future);
                            
                            if (result && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    isFollowed ? 'Unfollowed ${profile.displayNameOrName}' : 'Following ${profile.displayNameOrName}'
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                            
                            // Advance to next profile
                            _swiperController.next();
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
        loading: () => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading profiles from Nostr relays...'),
            ],
          ),
        ),
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
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }
}