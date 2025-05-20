import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'nostr_event.g.dart';

@JsonSerializable()
class NostrEvent extends Equatable {
  final String id;
  final String pubkey;
  final int created_at;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  const NostrEvent({
    required this.id,
    required this.pubkey,
    required this.created_at,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  factory NostrEvent.fromJson(Map<String, dynamic> json) => 
      _$NostrEventFromJson(json);

  Map<String, dynamic> toJson() => _$NostrEventToJson(this);

  @override
  List<Object?> get props => [id, pubkey, created_at, kind, tags, content, sig];

  // Helper method to get a tag value by its name (e.g., "e", "p", "d")
  String? getTagValue(String tagName) {
    final tagList = tags.firstWhere(
      (tag) => tag.isNotEmpty && tag[0] == tagName,
      orElse: () => <String>[],
    );
    
    if (tagList.length >= 2) {
      return tagList[1];
    }
    
    return null;
  }

  // Get all values of a specific tag
  List<String> getAllTagValues(String tagName) {
    return tags
        .where((tag) => tag.isNotEmpty && tag[0] == tagName)
        .map((tag) => tag.length >= 2 ? tag[1] : '')
        .where((value) => value.isNotEmpty)
        .toList();
  }

  // Event kinds
  static const int metadataKind = 0;
  static const int textNoteKind = 1;
  static const int recommendRelayKind = 2;
  static const int contactsKind = 3;
  static const int dmKind = 4;
}