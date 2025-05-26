import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logging/logging.dart';

class DiscardedProfilesService {
  static const String _boxName = 'discarded_profiles';
  static const String _discardedKey = 'discarded_pubkeys';
  
  final _logger = Logger('DiscardedProfilesService');
  late Box<dynamic> _box;
  final Set<String> _discardedPubkeys = {};
  
  Future<void> initialize() async {
    try {
      _box = await Hive.openBox(_boxName);
      await _loadDiscardedProfiles();
      _logger.info('DiscardedProfilesService initialized with ${_discardedPubkeys.length} discarded profiles');
    } catch (e) {
      _logger.severe('Failed to initialize DiscardedProfilesService', e);
    }
  }
  
  Future<void> _loadDiscardedProfiles() async {
    try {
      final List<dynamic>? stored = _box.get(_discardedKey);
      if (stored != null) {
        _discardedPubkeys.clear();
        _discardedPubkeys.addAll(stored.cast<String>());
      }
    } catch (e) {
      _logger.severe('Failed to load discarded profiles', e);
    }
  }
  
  Future<void> _saveDiscardedProfiles() async {
    try {
      await _box.put(_discardedKey, _discardedPubkeys.toList());
    } catch (e) {
      _logger.severe('Failed to save discarded profiles', e);
    }
  }
  
  Future<void> discardProfile(String pubkey) async {
    if (_discardedPubkeys.add(pubkey)) {
      await _saveDiscardedProfiles();
      _logger.info('Profile discarded: $pubkey');
    }
  }
  
  Future<void> undiscardProfile(String pubkey) async {
    if (_discardedPubkeys.remove(pubkey)) {
      await _saveDiscardedProfiles();
      _logger.info('Profile undiscarded: $pubkey');
    }
  }
  
  Future<void> clearAllDiscarded() async {
    _discardedPubkeys.clear();
    await _saveDiscardedProfiles();
    _logger.info('All discarded profiles cleared');
  }
  
  bool isDiscarded(String pubkey) {
    return _discardedPubkeys.contains(pubkey);
  }
  
  Set<String> get discardedPubkeys => Set.unmodifiable(_discardedPubkeys);
  
  int get discardedCount => _discardedPubkeys.length;
}

// Provider for the service
final discardedProfilesServiceProvider = Provider<DiscardedProfilesService>((ref) {
  return DiscardedProfilesService();
});

// Provider for discarded count
final discardedProfilesCountProvider = StateProvider<int>((ref) {
  final service = ref.watch(discardedProfilesServiceProvider);
  return service.discardedCount;
});