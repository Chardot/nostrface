// Minimal implementations of nostr package classes needed during migration
// This allows us to remove the dependency on the broken nostr package

import 'dart:convert';
import 'dart:math';
import 'package:bip340/bip340.dart' as bip340;
import 'package:bech32/bech32.dart';
import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

/// Minimal Event implementation for legacy code
class Event {
  final int kind;
  final String pubkey;
  final int created_at;
  final String content;
  final List<List<String>> tags;
  final String id;
  final String sig;

  Event({
    required this.kind,
    required this.pubkey,
    required this.created_at,
    required this.content,
    required this.tags,
    required this.id,
    required this.sig,
  });

  // Add getter for compatibility
  int get createdAt => created_at;

  factory Event.from({
    required int kind,
    required List<List<String>> tags,
    required String content,
    required String privkey,
    int? created_at,
  }) {
    final createdAt = created_at ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final pubkey = bip340.getPublicKey(privkey);
    
    // Create event ID
    final eventData = [
      0,
      pubkey,
      createdAt,
      kind,
      tags,
      content,
    ];
    
    final serialized = jsonEncode(eventData);
    final bytes = utf8.encode(serialized);
    final hash = sha256.convert(bytes);
    final id = hex.encode(hash.bytes);
    
    // Sign the event - bip340 requires aux parameter
    final aux = hex.encode(List<int>.generate(32, (i) => 
      DateTime.now().millisecondsSinceEpoch * i % 256));
    final sig = bip340.sign(privkey, id, aux);
    
    return Event(
      kind: kind,
      pubkey: pubkey,
      created_at: createdAt,
      content: content,
      tags: tags,
      id: id,
      sig: sig,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pubkey': pubkey,
    'created_at': created_at,
    'kind': kind,
    'tags': tags,
    'content': content,
    'sig': sig,
  };

  String serialize() => jsonEncode(['EVENT', toJson()]);
  
  static Event deserialize(List<dynamic> data, {bool verify = true}) {
    if (data[0] != 'EVENT') throw Exception('Invalid event format');
    final eventData = data[2] as Map<String, dynamic>;
    
    return Event(
      id: eventData['id'],
      pubkey: eventData['pubkey'],
      created_at: eventData['created_at'],
      kind: eventData['kind'],
      tags: List<List<String>>.from(
        (eventData['tags'] as List).map((tag) => List<String>.from(tag))
      ),
      content: eventData['content'],
      sig: eventData['sig'],
    );
  }
}

/// Minimal Filter implementation for legacy code
class Filter {
  final List<String>? ids;
  final List<String>? authors;
  final List<int>? kinds;
  final int? since;
  final int? until;
  final int? limit;
  final List<String>? e;
  final List<String>? p;

  Filter({
    this.ids,
    this.authors,
    this.kinds,
    this.since,
    this.until,
    this.limit,
    this.e,
    this.p,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (ids != null) json['ids'] = ids;
    if (authors != null) json['authors'] = authors;
    if (kinds != null) json['kinds'] = kinds;
    if (since != null) json['since'] = since;
    if (until != null) json['until'] = until;
    if (limit != null) json['limit'] = limit;
    if (e != null) json['#e'] = e;
    if (p != null) json['#p'] = p;
    return json;
  }
}

/// Minimal Request implementation for legacy code
class Request {
  final String subscriptionId;
  final List<Filter> filters;

  Request(this.subscriptionId, this.filters);

  String serialize() => jsonEncode([
    'REQ',
    subscriptionId,
    ...filters.map((f) => f.toJson()),
  ]);
}

/// Minimal Close implementation for legacy code
class Close {
  final String subscriptionId;

  Close(this.subscriptionId);

  String serialize() => jsonEncode(['CLOSE', subscriptionId]);
}

/// Minimal Keychain implementation for legacy code
class Keychain {
  final String private;
  String get public => bip340.getPublicKey(private);

  Keychain(String key) : private = _parsePrivateKey(key);

  factory Keychain.generate() {
    // Generate 32 random bytes and convert to hex
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final privateKey = hex.encode(bytes);
    return Keychain(privateKey);
  }

  static String _parsePrivateKey(String key) {
    key = key.trim();
    
    if (key.startsWith('nsec')) {
      try {
        final decoded = bech32.decode(key);
        if (decoded.hrp != 'nsec') {
          throw Exception('Invalid nsec format');
        }
        final data = _convertBits(decoded.data, 5, 8, false);
        return hex.encode(data);
      } catch (e) {
        throw Exception('Invalid nsec format: $e');
      }
    } else {
      if (key.length != 64) {
        throw Exception('Invalid private key length. Expected 64 hex characters.');
      }
      try {
        hex.decode(key);
      } catch (e) {
        throw Exception('Invalid hex format: $e');
      }
      return key;
    }
  }

  static List<int> _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final byte in data) {
      if (byte < 0 || byte >> fromBits != 0) {
        throw Exception('Invalid data for conversion');
      }
      acc = (acc << fromBits) | byte;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      throw Exception('Invalid padding');
    }

    return result;
  }
}

/// Minimal Nip19 implementation for legacy code
class Nip19 {
  static String encodePubkey(String pubkey) {
    final bytes = hex.decode(pubkey);
    final converted = _convertBits(bytes, 8, 5, true);
    final bech32Data = Bech32('npub', converted);
    return bech32.encode(bech32Data);
  }

  static String decodePubkey(String npub) {
    final decoded = bech32.decode(npub);
    if (decoded.hrp != 'npub') {
      throw Exception('Invalid npub format');
    }
    final data = _convertBits(decoded.data, 5, 8, false);
    return hex.encode(data);
  }

  static String encodeNote(String noteId) {
    final bytes = hex.decode(noteId);
    final converted = _convertBits(bytes, 8, 5, true);
    final bech32Data = Bech32('note', converted);
    return bech32.encode(bech32Data);
  }

  static String decodePrivkey(String nsec) {
    final decoded = bech32.decode(nsec);
    if (decoded.hrp != 'nsec') {
      throw Exception('Invalid nsec format');
    }
    final data = _convertBits(decoded.data, 5, 8, false);
    return hex.encode(data);
  }

  static List<int> _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final byte in data) {
      if (byte < 0 || byte >> fromBits != 0) {
        throw Exception('Invalid data for conversion');
      }
      acc = (acc << fromBits) | byte;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      throw Exception('Invalid padding');
    }

    return result;
  }
}