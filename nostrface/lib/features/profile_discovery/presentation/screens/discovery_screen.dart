import 'package:card_swiper/card_swiper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/profile_service.dart';
import 'package:nostrface/features/profile_discovery/presentation/widgets/profile_card.dart';

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
    
    // Load profiles when screen initializes
    _refreshProfiles();
  }

  @override
  void dispose() {
    _swiperController.dispose();
    super.dispose();
  }

  Future<void> _refreshProfiles() async {
    setState(() {
      _isLoading = true;
    });
    
    // Invalidate the discovery provider to trigger a refresh
    ref.invalidate(profileDiscoveryProvider);
    
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch the discovered profiles provider
    final profilesAsync = ref.watch(profileDiscoveryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('NostrFace'),
        centerTitle: true,
        actions: [
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
                      return ProfileCard(
                        name: profile.displayNameOrName,
                        imageUrl: profile.picture ?? 'https://picsum.photos/500/500?random=$index',
                        bio: profile.about ?? 'No bio available',
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
                      // Pre-fetch more profiles if we're near the end of the list
                      if (index >= profiles.length - 3) {
                        // In a real app, you would fetch more profiles here
                      }
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      icon: Icons.close,
                      color: Colors.red,
                      onPressed: () {
                        _swiperController.next();
                      },
                    ),
                    _buildActionButton(
                      icon: Icons.star,
                      color: Colors.blue,
                      onPressed: () {
                        // TODO: Save to favorites
                        _swiperController.next();
                      },
                    ),
                    _buildActionButton(
                      icon: Icons.favorite,
                      color: Colors.green,
                      onPressed: () {
                        // TODO: Follow profile
                        _swiperController.next();
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
    required VoidCallback onPressed,
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
            color: color,
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