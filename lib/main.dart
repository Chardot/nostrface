import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nostrface/core/config/app_router.dart';
import 'package:nostrface/core/config/theme.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/services/note_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive for local storage
  await Hive.initFlutter();
  
  // Register Hive adapters here
  
  runApp(
    // Enable Riverpod for the entire app
    ProviderScope(
      overrides: [
        // Initialize discarded profiles service
        discardedProfilesServiceProvider.overrideWith((ref) {
          final service = DiscardedProfilesService();
          service.initialize(); // Initialize on app start
          return service;
        }),
        // Initialize note cache service
        noteCacheServiceProvider.overrideWith((ref) {
          final service = NoteCacheService();
          service.init(); // Initialize cache on app start
          return service;
        }),
      ],
      child: const NostrFaceApp(),
    ),
  );
}

class NostrFaceApp extends ConsumerWidget {
  const NostrFaceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    
    return MaterialApp.router(
      title: 'NostrFace',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerDelegate: router.routerDelegate,
      routeInformationParser: router.routeInformationParser,
      routeInformationProvider: router.routeInformationProvider,
      debugShowCheckedModeBanner: false,
    );
  }
}
