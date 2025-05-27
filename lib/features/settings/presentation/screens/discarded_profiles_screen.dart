import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/services/profile_service.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:logging/logging.dart';

class DiscardedProfilesScreen extends ConsumerStatefulWidget {
  const DiscardedProfilesScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<DiscardedProfilesScreen> createState() => _DiscardedProfilesScreenState();
}

class _DiscardedProfilesScreenState extends ConsumerState<DiscardedProfilesScreen> {
  final _logger = Logger('DiscardedProfilesScreen');
  bool _isLoading = false;

  Future<void> _clearAllDiscarded() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear All Discarded Profiles?'),
        content: const Text('This will restore all discarded profiles to your discovery feed. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _isLoading = true;
      });

      try {
        final discardedService = ref.read(discardedProfilesServiceProvider);
        await discardedService.clearAllDiscarded();
        
        // Update the count provider
        ref.read(discardedProfilesCountProvider.notifier).state = 0;
        
        // Refresh the profile buffer to include previously discarded profiles
        final bufferService = ref.read(profileBufferServiceProvider);
        await bufferService.refreshBuffer();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All discarded profiles have been cleared')),
          );
        }
      } catch (e) {
        _logger.severe('Error clearing discarded profiles', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error clearing profiles: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final discardedService = ref.watch(discardedProfilesServiceProvider);
    final discardedCount = ref.watch(discardedProfilesCountProvider);
    final discardedPubkeys = discardedService.discardedPubkeys.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discarded Profiles'),
        centerTitle: true,
      ),
      body: discardedPubkeys.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_off,
                    size: 64,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No discarded profiles',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Profiles you discard will appear here',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Text(
                            '$discardedCount',
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Discarded Profiles',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _clearAllDiscarded,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.clear_all),
                            label: const Text('Clear All'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: discardedPubkeys.length,
                    itemBuilder: (context, index) {
                      final pubkey = discardedPubkeys[index];
                      
                      return FutureBuilder(
                        future: ref.read(profileProvider(pubkey).future),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(
                                  pubkey.substring(0, 16) + '...',
                                  style: const TextStyle(fontFamily: 'monospace'),
                                ),
                                subtitle: const Text('Loading...'),
                              ),
                            );
                          }
                          
                          final profile = snapshot.data!;
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundImage: profile.picture != null
                                    ? NetworkImage(profile.picture!)
                                    : null,
                                child: profile.picture == null
                                    ? const Icon(Icons.person)
                                    : null,
                              ),
                              title: Text(profile.displayNameOrName),
                              subtitle: Text(
                                profile.about ?? 'No bio available',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.restore),
                                tooltip: 'Restore profile',
                                onPressed: () async {
                                  await discardedService.undiscardProfile(pubkey);
                                  ref.read(discardedProfilesCountProvider.notifier).state = 
                                      discardedService.discardedCount;
                                  
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Restored ${profile.displayNameOrName}'),
                                      ),
                                    );
                                  }
                                },
                              ),
                              onTap: () {
                                // Navigate to profile view
                                context.push('/profile/$pubkey');
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}