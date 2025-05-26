import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Force refresh of authentication state on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(isLoggedInProvider);
      ref.invalidate(currentPublicKeyProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Get authentication state
    final isLoggedInAsync = ref.watch(isLoggedInProvider);
    final publicKeyAsync = ref.watch(currentPublicKeyProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          // Auth Status Section
          _buildAuthSection(context, ref, isLoggedInAsync, publicKeyAsync),
          
          _buildSection(
            context,
            title: 'Account',
            items: [
              _buildSettingTile(
                context,
                title: 'Profile',
                subtitle: 'View and edit your Nostr profile',
                icon: Icons.person,
                onTap: () {
                  // TODO: Navigate to profile editing
                  _showComingSoonDialog(context);
                },
              ),
              _buildSettingTile(
                context,
                title: 'Key Management',
                subtitle: 'Manage your private keys',
                icon: Icons.key,
                onTap: () {
                  // TODO: Navigate to key management
                  _showComingSoonDialog(context);
                },
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'Network',
            items: [
              _buildSettingTile(
                context,
                title: 'Content Filters',
                subtitle: 'Customize your discovery preferences',
                icon: Icons.filter_list,
                onTap: () {
                  // TODO: Navigate to content filters
                  _showComingSoonDialog(context);
                },
              ),
              Consumer(
                builder: (context, ref, child) {
                  final discardedCount = ref.watch(discardedProfilesCountProvider);
                  return _buildSettingTile(
                    context,
                    title: 'Discarded Profiles',
                    subtitle: discardedCount > 0 
                        ? '$discardedCount profiles discarded'
                        : 'No discarded profiles',
                    icon: Icons.person_off,
                    onTap: () {
                      // Navigate to discarded profiles screen
                      context.push('/settings/discarded');
                    },
                  );
                },
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'App Settings',
            items: [
              _buildSwitchTile(
                context,
                title: 'Dark Mode',
                subtitle: 'Toggle dark theme',
                icon: Icons.dark_mode,
                value: Theme.of(context).brightness == Brightness.dark,
                onChanged: (value) {
                  // TODO: Implement theme switching
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(value ? 'Dark mode enabled' : 'Dark mode disabled'),
                    ),
                  );
                },
              ),
              _buildSwitchTile(
                context,
                title: 'Notifications',
                subtitle: 'Enable or disable push notifications',
                icon: Icons.notifications,
                value: true, // TODO: Use actual stored setting
                onChanged: (value) {
                  // TODO: Implement notification toggle
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        value ? 'Notifications enabled' : 'Notifications disabled',
                      ),
                    ),
                  );
                },
              ),
              _buildSettingTile(
                context,
                title: 'Cache',
                subtitle: 'Manage app cache',
                icon: Icons.storage,
                onTap: () {
                  // TODO: Implement cache management
                  _showComingSoonDialog(context);
                },
              ),
            ],
          ),
          _buildSection(
            context,
            title: 'About',
            items: [
              _buildSettingTile(
                context,
                title: 'About NostrFace',
                subtitle: 'Version 0.1.0',
                icon: Icons.info,
                onTap: () {
                  // TODO: Show about dialog
                  showAboutDialog(
                    context: context,
                    applicationName: 'NostrFace',
                    applicationVersion: '0.1.0',
                    applicationIcon: const FlutterLogo(size: 64),
                    applicationLegalese: '© 2023 NostrFace',
                    children: [
                      const Text(
                        'NostrFace is a profile discovery app for the Nostr network.',
                      ),
                    ],
                  );
                },
              ),
              _buildSettingTile(
                context,
                title: 'Privacy Policy',
                subtitle: 'View our privacy policy',
                icon: Icons.privacy_tip,
                onTap: () {
                  // TODO: Navigate to privacy policy
                  _showComingSoonDialog(context);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuthSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<bool> isLoggedInAsync,
    AsyncValue<String?> publicKeyAsync,
  ) {
    return isLoggedInAsync.when(
      data: (isLoggedIn) {
        return _buildSection(
          context,
          title: 'Authentication',
          items: [
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isLoggedIn ? Icons.check_circle : Icons.info,
                          color: isLoggedIn ? Colors.green : Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isLoggedIn ? 'Logged In' : 'Read-Only Mode',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isLoggedIn) ...[
                      publicKeyAsync.when(
                        data: (publicKey) {
                          if (publicKey == null) {
                            return const Text('No public key available');
                          }
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Your public key:'),
                              const SizedBox(height: 4),
                              Text(
                                _formatKey(publicKey),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          );
                        },
                        loading: () => const Text('Loading public key...'),
                        error: (error, _) => Text('Error: $error'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _handleLogout(context, ref),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Log Out'),
                      ),
                    ] else ...[
                      const Text(
                        'You are currently using NostrFace in read-only mode. Sign in to interact with other profiles and customize your experience.',
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Log In / Sign Up'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
      loading: () => _buildSection(
        context,
        title: 'Authentication',
        items: [
          const ListTile(
            title: Text('Loading authentication status...'),
            leading: CircularProgressIndicator(),
          ),
        ],
      ),
      error: (error, _) => _buildSection(
        context,
        title: 'Authentication',
        items: [
          ListTile(
            title: Text('Error: $error'),
            leading: const Icon(Icons.error, color: Colors.red),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    final keyService = ref.read(keyManagementServiceProvider);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text(
          'Are you sure you want to log out? This will remove your stored keys from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await keyService.clearKeys();
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logged out successfully')),
                );
                // Refresh providers
                ref.invalidate(isLoggedInProvider);
                ref.invalidate(currentPublicKeyProvider);
              }
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  String _formatKey(String key) {
    if (key.length <= 12) return key;
    return '${key.substring(0, 8)}...${key.substring(key.length - 8)}';
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required List<Widget> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...items,
        const Divider(),
      ],
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  void _showComingSoonDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coming Soon'),
        content: const Text('This feature is not yet implemented.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}