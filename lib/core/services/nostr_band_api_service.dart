import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:nostrface/core/models/nostr_profile.dart';

class NostrBandApiService {
  static const String baseUrl = 'https://api.nostr.band/v0';

  /// Fetch trending profiles from nostr.band
  static Future<List<NostrProfile>> getTrendingProfiles({int count = 50}) async {
    final uri = Uri.parse('$baseUrl/trending/profiles?count=$count');
    try {
      if (kDebugMode) {
        print('[NostrBandAPI] Fetching trending profiles from: $uri');
      }
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final profiles = (data['profiles'] as List)
            .map((p) {
              final profileEvent = p['profile'];
              if (profileEvent != null && profileEvent['content'] != null) {
                return NostrProfile.fromMetadataEvent(
                  p['pubkey'],
                  profileEvent['content'],
                );
              } else {
                // fallback: create minimal profile
                return NostrProfile(pubkey: p['pubkey']);
              }
            })
            .where((profile) => profile != null)
            .cast<NostrProfile>()
            .toList();
        if (kDebugMode) {
          print('[NostrBandAPI] Received ${profiles.length} trending profiles');
        }
        return profiles;
      } else {
        throw Exception('Failed to load trending profiles: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[NostrBandAPI] Error fetching trending profiles: $e');
      }
      rethrow;
    }
  }
} 