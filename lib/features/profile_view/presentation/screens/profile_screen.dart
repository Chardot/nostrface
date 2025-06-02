import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/profile_service.dart';
import 'package:nostrface/features/direct_messages/presentation/widgets/dm_composer.dart';
import 'package:nostrface/core/widgets/formatted_content.dart';
import 'package:nostrface/features/profile_view/presentation/widgets/share_note_sheet.dart';
import 'package:nostrface/features/profile_view/presentation/widgets/share_profile_sheet.dart';

// Provider for fetching recent notes from a user with auto-refresh
final userNotesProvider = FutureProvider.family.autoDispose<List<NostrEvent>, String>((ref, pubkey) async {
  // Fetch real notes from the profile service
  final profileService = ref.watch(profileServiceProvider);
  return await profileService.getUserNotes(pubkey, limit: 10);
});

class ProfileScreen extends ConsumerWidget {
  final String profileId;

  const ProfileScreen({
    Key? key,
    required this.profileId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch profile data using the profileId
    final profileAsync = ref.watch(profileProvider(profileId));
    final notesAsync = ref.watch(userNotesProvider(profileId));
    
    return Scaffold(
      body: profileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(
              child: Text('Profile not found'),
            );
          }
          
          // Debug logging
          if (kDebugMode) {
            print('Profile View - pubkey: ${profile.pubkey}');
            print('Profile View - picture URL: ${profile.picture}');
            print('Profile View - name: ${profile.name}');
            print('Profile View - displayName: ${profile.displayName}');
            print('Profile View - about: ${profile.about}');
          }
          
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 300.0,
                floating: false,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(profile.displayNameOrName),
                  background: profile.picture != null
                    ? CachedNetworkImage(
                        imageUrl: profile.picture!,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(Icons.error, size: 50),
                          ),
                        ),
                      )
                    : Container(
                        color: Colors.grey[300],
                        child: const Center(
                          child: Icon(Icons.person, size: 120),
                        ),
                      ),
                ),
                actions: [
                  Consumer(
                    builder: (context, ref, child) {
                      final isFollowedAsync = ref.watch(isProfileFollowedProvider(profileId));
                      final isFollowed = isFollowedAsync.valueOrNull ?? false;
                      
                      return IconButton(
                        icon: Icon(isFollowed ? Icons.favorite : Icons.favorite_border),
                        color: isFollowed ? Colors.red : null,
                        onPressed: () async {
                          // Check if user is logged in
                          final isLoggedIn = await ref.read(isLoggedInProvider.future);
                          
                          if (isLoggedIn == false && context.mounted) {
                            // Show dialog to prompt user to log in
                            showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) => AlertDialog(
                                key: const Key('profile_login_dialog'),
                                title: const Text('Login Required'),
                                content: const Text(
                                  'You need to be logged in to follow profiles. Would you like to log in now?'
                                ),
                                actions: [
                                  TextButton(
                                    key: const Key('profile_login_cancel'),
                                    onPressed: () => Navigator.of(dialogContext).pop(),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    key: const Key('profile_login_confirm'),
                                    onPressed: () {
                                      Navigator.of(dialogContext).pop();
                                      // Use push to preserve the stack
                                      context.push('/login');
                                    },
                                    child: const Text('Log In'),
                                  ),
                                ],
                              ),
                            );
                            return;
                          }
                          
                          // Optimistically update the UI immediately
                          final profileService = ref.read(profileServiceProvider);
                          if (isFollowed) {
                            profileService.optimisticallyUnfollow(profileId);
                          } else {
                            profileService.optimisticallyFollow(profileId);
                          }
                          
                          // Show immediate feedback
                          if (context.mounted) {
                            final profileName = profile.displayNameOrName;
                            final message = isFollowed 
                              ? 'Unfollowing $profileName...' 
                              : 'Following $profileName...';
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(message),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          }
                          
                          // Publish to relays in the background
                          ref.read(publishFollowEventProvider.future).then((result) {
                            if (!result.isSuccess) {
                              // Revert the optimistic update if failed
                              if (isFollowed) {
                                profileService.optimisticallyFollow(profileId);
                              } else {
                                profileService.optimisticallyUnfollow(profileId);
                              }
                              
                              if (context.mounted) {
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
                            }
                          });
                        },
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: () {
                      ShareProfileSheet.show(context, profile);
                    },
                  ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (profile.nip05 != null && profile.nip05!.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.verified, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(
                              profile.nip05!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        'About',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        profile.about ?? 'No bio available',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      if (profile.website != null && profile.website!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Icon(Icons.link, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              profile.website!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Recent Posts',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              notesAsync.when(
                data: (notes) {
                  if (notes.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(
                          child: Text('No posts available'),
                        ),
                      ),
                    );
                  }
                  
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final note = notes[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundImage: profile.picture != null
                                        ? CachedNetworkImageProvider(profile.picture!)
                                        : null,
                                      child: profile.picture == null
                                        ? const Icon(Icons.person)
                                        : null,
                                      radius: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          profile.displayNameOrName,
                                          style: Theme.of(context).textTheme.titleMedium,
                                        ),
                                        Text(
                                          _formatDate(DateTime.fromMillisecondsSinceEpoch(note.created_at * 1000)),
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                FormattedContent(
                                  content: note.content,
                                  textStyle: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.favorite_border),
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Like feature coming soon!')),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.repeat),
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Repost feature coming soon!')),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.share),
                                      onPressed: () {
                                        ShareNoteSheet.show(
                                          context,
                                          note,
                                          profile.displayNameOrName,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: notes.length,
                    ),
                  );
                },
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
                error: (error, stackTrace) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Center(
                      child: Text('Error loading posts: ${error.toString()}'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(),
        ),
        error: (error, stackTrace) => Center(
          child: Text('Error loading profile: ${error.toString()}'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Check if profile is loaded
          if (!profileAsync.hasValue || profileAsync.value == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unable to load profile for messaging')),
            );
            return;
          }
          
          // Check if user is logged in
          final isLoggedIn = await ref.read(isLoggedInProvider.future);
          
          if (isLoggedIn == false && context.mounted) {
            // Show dialog to prompt user to log in
            showDialog(
              context: context,
              builder: (BuildContext dialogContext) => AlertDialog(
                key: const Key('dm_login_dialog'),
                title: const Text('Login Required'),
                content: const Text(
                  'You need to be logged in to send direct messages. Would you like to log in now?'
                ),
                actions: [
                  TextButton(
                    key: const Key('dm_login_cancel'),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    key: const Key('dm_login_confirm'),
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      // Use push to preserve the stack
                      context.push('/login');
                    },
                    child: const Text('Log In'),
                  ),
                ],
              ),
            );
            return;
          }

          // If logged in and profile is loaded, show the message bottom sheet
          if (context.mounted) {
            _showMessageBottomSheet(context, profileAsync.value!);
          }
        },
        child: const Icon(Icons.message),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 30) {
      return '${difference.inDays}d ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '${months}mo ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '${years}y ago';
    }
  }
  

  void _showMessageBottomSheet(BuildContext context, NostrProfile profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).canvasColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      // Use at least 60% of screen height and expand if keyboard is shown
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
        minHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      builder: (BuildContext context) {
        return AnimatedPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: DirectMessageComposer(
            recipient: profile,
            onMessageSent: () {
              // Close the bottom sheet after message is sent
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }
}