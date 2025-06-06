import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nostrface/core/config/app_router.dart';
import 'package:nostrface/core/config/theme.dart';
import 'package:nostrface/core/providers/app_providers.dart';
import 'package:nostrface/core/services/discarded_profiles_service.dart';
import 'package:nostrface/core/services/note_cache_service.dart';

// Global variable to track app start time
late final DateTime appStartTime;

void main() async {
  // Record app start time
  appStartTime = DateTime.now();
  print('[PERF] App launch started at: ${appStartTime.toIso8601String()}');
  
  WidgetsFlutterBinding.ensureInitialized();
  final bindingTime = DateTime.now();
  print('[PERF] Flutter binding initialized: ${bindingTime.difference(appStartTime).inMilliseconds}ms from start');
  
  // Initialize Hive for local storage
  final hiveStartTime = DateTime.now();
  await Hive.initFlutter();
  final hiveEndTime = DateTime.now();
  print('[PERF] Hive initialization took: ${hiveEndTime.difference(hiveStartTime).inMilliseconds}ms (${hiveEndTime.difference(appStartTime).inMilliseconds}ms from start)');
  
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
  
  final runAppTime = DateTime.now();
  print('[PERF] runApp called: ${runAppTime.difference(appStartTime).inMilliseconds}ms from start');
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
