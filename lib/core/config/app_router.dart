import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/services/key_management_service.dart';
import 'package:nostrface/features/auth/presentation/screens/login_screen.dart';
import 'package:nostrface/features/profile_discovery/presentation/screens/discovery_screen_new.dart';
import 'package:nostrface/features/profile_view/presentation/screens/profile_screen.dart';
import 'package:nostrface/features/settings/presentation/screens/settings_screen.dart';
import 'package:nostrface/features/settings/presentation/screens/discarded_profiles_screen.dart';
import 'package:nostrface/shared/widgets/scaffold_with_nav_bar.dart';

// Router notifier to handle authentication state changes
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(this._ref) {
    _ref.listen(
      isLoggedInProvider, 
      (_, __) => notifyListeners(),
    );
  }
  
  final Ref _ref;
}

// Provider that exposes the GoRouter instance to the rest of the app
final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);
  
  return GoRouter(
    initialLocation: '/discovery',
    refreshListenable: notifier,
    debugLogDiagnostics: true,
    routes: [
      // Auth routes
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      
      // Main app shell with bottom navigation
      ShellRoute(
        builder: (context, state, child) => ScaffoldWithNavBar(child: child),
        routes: [
          // Discovery Screen
          GoRoute(
            path: '/discovery',
            name: 'discovery',
            builder: (context, state) => const DiscoveryScreenNew(),
            routes: [
              // Profile View (as a sub-route of discovery)
              GoRoute(
                path: 'profile/:id',
                name: 'profile',
                builder: (context, state) {
                  final profileId = state.pathParameters['id'] ?? '';
                  return ProfileScreen(profileId: profileId);
                },
              ),
            ],
          ),
          
          // Settings Screen
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
            routes: [
              // Discarded Profiles (as a sub-route of settings)
              GoRoute(
                path: 'discarded',
                name: 'discarded',
                builder: (context, state) => const DiscardedProfilesScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
    
    // Redirect based on authentication state
    redirect: (context, state) async {
      // Get the current authentication state from the provider
      final authState = await ref.read(isLoggedInProvider.future);
      
      // Check if the user is going to the login screen
      final isGoingToLogin = state.matchedLocation == '/login';
      
      // By default we allow the user to use the app in read-only mode
      // In a real app, you might want to require login for certain features
      
      // If the user is logged in and trying to go to login, redirect to discovery
      if (authState && isGoingToLogin) {
        return '/discovery';
      }
      
      // Otherwise, allow the navigation to proceed
      return null;
    },
    
    // Global error handler
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(
        title: const Text('Error'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
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
                'Error: ${state.error}',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  context.go('/discovery');
                },
                child: const Text('Go to Home'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});