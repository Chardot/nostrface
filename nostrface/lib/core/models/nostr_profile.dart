import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'nostr_profile.g.dart';

@JsonSerializable()
class NostrProfile extends Equatable {
  final String pubkey;
  final String? name;
  final String? displayName;
  final String? picture;
  final String? banner;
  final String? about;
  final String? website;
  final String? nip05;
  final String? lud16;

  const NostrProfile({
    required this.pubkey,
    this.name,
    this.displayName,
    this.picture,
    this.banner,
    this.about,
    this.website,
    this.nip05,
    this.lud16,
  });

  factory NostrProfile.fromJson(Map<String, dynamic> json) => 
      _$NostrProfileFromJson(json);

  Map<String, dynamic> toJson() => _$NostrProfileToJson(this);

  @override
  List<Object?> get props => [
        pubkey,
        name,
        displayName,
        picture,
        banner,
        about,
        website,
        nip05,
        lud16,
      ];

  // Create a profile from a Kind 0 Nostr event
  factory NostrProfile.fromMetadataEvent(String pubkey, String content) {
    Map<String, dynamic> metadata;
    try {
      metadata = json.decode(content) as Map<String, dynamic>;
    } catch (e) {
      // If JSON parsing fails, return a profile with just the pubkey
      return NostrProfile(pubkey: pubkey);
    }

    return NostrProfile(
      pubkey: pubkey,
      name: metadata['name'] as String?,
      displayName: metadata['display_name'] as String?,
      picture: metadata['picture'] as String?,
      banner: metadata['banner'] as String?,
      about: metadata['about'] as String?,
      website: metadata['website'] as String?,
      nip05: metadata['nip05'] as String?,
      lud16: metadata['lud16'] as String?,
    );
  }

  // Get the best available name for display purposes
  String get displayNameOrName => displayName ?? name ?? _shortenPubkey(pubkey);

  // Helper to shorten pubkey for display
  static String _shortenPubkey(String pubkey) {
    if (pubkey.length <= 12) return pubkey;
    return '${pubkey.substring(0, 6)}...${pubkey.substring(pubkey.length - 6)}';
  }

  // Create a merged profile, preferring values from newer profile
  NostrProfile merge(NostrProfile other) {
    return NostrProfile(
      pubkey: pubkey,
      name: other.name ?? name,
      displayName: other.displayName ?? displayName,
      picture: other.picture ?? picture,
      banner: other.banner ?? banner,
      about: other.about ?? about,
      website: other.website ?? website,
      nip05: other.nip05 ?? nip05,
      lud16: other.lud16 ?? lud16,
    );
  }
}