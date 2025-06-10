import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

class ProfileReference {
  final String pubkey;
  final List<String> relays;
  final double score;
  final DateTime lastUpdated;

  ProfileReference({
    required this.pubkey,
    required this.relays,
    required this.score,
    required this.lastUpdated,
  });

  factory ProfileReference.fromJson(Map<String, dynamic> json) {
    return ProfileReference(
      pubkey: json['pubkey'],
      relays: List<String>.from(json['relays']),
      score: json['score'].toDouble(),
      lastUpdated: DateTime.parse(json['last_updated']),
    );
  }
}

class IndexerApiService {
  static const String DEV_API_URL = 'http://localhost:8000';
  static const String PROD_API_URL = 'https://nostr-profile-indexer.deno.dev';
  
  // Toggle this to switch between development and production
  static const bool USE_LOCAL_SERVER = false;
  static const String baseUrl = USE_LOCAL_SERVER ? DEV_API_URL : PROD_API_URL;
  static final String sessionId = const Uuid().v4();

  static Future<List<ProfileReference>> getProfileBatch({
    int count = 50,
    List<String> excludeIds = const [],
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/profiles/batch').replace(
        queryParameters: {
          'count': count.toString(),
          if (excludeIds.isNotEmpty) 'exclude': excludeIds.join(','),
          'session_id': sessionId,
        },
      );

      if (kDebugMode) {
        print('[IndexerAPI] Fetching profiles from: $uri');
      }

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final profiles = (data['profiles'] as List)
            .map((p) => ProfileReference.fromJson(p))
            .toList();
        
        if (kDebugMode) {
          print('[IndexerAPI] Received ${profiles.length} profiles from server');
        }
        
        return profiles;
      } else {
        throw Exception('Failed to load profiles: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[IndexerAPI] Error fetching profile batch: $e');
      }
      throw e;
    }
  }

  static Future<void> reportInteraction({
    required String pubkey,
    required String action,
  }) async {
    try {
      final body = jsonEncode({
        'session_id': sessionId,
        'pubkey': pubkey,
        'action': action,
      });

      if (kDebugMode) {
        print('[IndexerAPI] Reporting interaction: $action for $pubkey');
      }

      await http.post(
        Uri.parse('$baseUrl/api/profiles/interaction'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      // Don't throw - this is optional functionality
      if (kDebugMode) {
        print('[IndexerAPI] Failed to report interaction: $e');
      }
    }
  }
}