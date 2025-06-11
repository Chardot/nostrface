import 'dart:convert';
import 'package:ndk/ndk.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'package:nostrface/core/models/nostr_profile.dart';

/// Extension to convert between NostrEvent and Nip01Event
extension NostrEventAdapter on NostrEvent {
  /// Convert NostrEvent to NDK's Nip01Event
  Nip01Event toNip01Event() {
    return Nip01Event(
      id: id,
      pubkey: pubkey,
      createdAt: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      sig: sig,
    );
  }

  /// Create NostrEvent from NDK's Nip01Event
  static NostrEvent fromNip01Event(Nip01Event ndkEvent) {
    return NostrEvent(
      id: ndkEvent.id,
      pubkey: ndkEvent.pubkey,
      createdAt: ndkEvent.createdAt,
      kind: ndkEvent.kind,
      tags: ndkEvent.tags,
      content: ndkEvent.content,
      sig: ndkEvent.sig,
    );
  }
}

/// Extension to convert between NostrProfile and Metadata
extension NostrProfileAdapter on NostrProfile {
  /// Convert NostrProfile to NDK's Metadata
  Metadata toMetadata() {
    return Metadata(
      pubkey: pubkey,
      name: name,
      displayName: displayName,
      picture: picture,
      banner: banner,
      about: about,
      website: website,
      nip05: nip05,
      lud16: lud16,
      lud06: lud06,
    );
  }

  /// Create NostrProfile from NDK's Metadata
  static NostrProfile fromMetadata(Metadata metadata) {
    return NostrProfile(
      pubkey: metadata.pubkey,
      name: metadata.name,
      displayName: metadata.displayName,
      picture: metadata.picture,
      banner: metadata.banner,
      about: metadata.about,
      website: metadata.website,
      nip05: metadata.nip05,
      lud16: metadata.lud16,
      lud06: metadata.lud06,
      lastUpdated: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Create NostrProfile from metadata event
  static NostrProfile fromMetadataEvent(Nip01Event event) {
    if (event.kind != 0) {
      throw ArgumentError('Event must be kind 0 (metadata)');
    }

    try {
      final metadata = Metadata.fromNip01Event(event);
      return fromMetadata(metadata);
    } catch (e) {
      // Fallback to manual parsing if NDK parsing fails
      final content = jsonDecode(event.content) as Map<String, dynamic>;
      return NostrProfile(
        pubkey: event.pubkey,
        name: content['name'] as String?,
        displayName: content['display_name'] as String?,
        picture: content['picture'] as String?,
        banner: content['banner'] as String?,
        about: content['about'] as String?,
        website: content['website'] as String?,
        nip05: content['nip05'] as String?,
        lud16: content['lud16'] as String?,
        lud06: content['lud06'] as String?,
        lastUpdated: event.createdAt,
      );
    }
  }
}

/// Extension to work with contact lists
extension ContactListAdapter on ContactList {
  /// Get list of followed pubkeys
  List<String> get followedPubkeys {
    return contacts.map((contact) => contact.pubkey).toList();
  }

  /// Check if a pubkey is in the contact list
  bool isFollowing(String pubkey) {
    return contacts.any((contact) => contact.pubkey == pubkey);
  }

  /// Add a contact to the list
  ContactList addContact(String pubkey, {String? relay, String? petname}) {
    final newContact = Contact(
      pubkey: pubkey,
      relay: relay,
      petname: petname,
    );
    
    final updatedContacts = List<Contact>.from(contacts);
    // Remove if already exists
    updatedContacts.removeWhere((c) => c.pubkey == pubkey);
    // Add new contact
    updatedContacts.add(newContact);
    
    return ContactList(
      pubkey: this.pubkey,
      contacts: updatedContacts,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Remove a contact from the list
  ContactList removeContact(String pubkey) {
    final updatedContacts = List<Contact>.from(contacts)
      ..removeWhere((c) => c.pubkey == pubkey);
    
    return ContactList(
      pubkey: this.pubkey,
      contacts: updatedContacts,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Convert to Nostr event for publishing
  Nip01Event toEvent(EventSigner signer) {
    final tags = contacts.map((contact) {
      final tag = ['p', contact.pubkey];
      if (contact.relay != null) tag.add(contact.relay!);
      if (contact.petname != null) tag.add(contact.petname!);
      return tag;
    }).toList();

    final unsignedEvent = Nip01Event(
      pubkey: pubkey,
      createdAt: createdAt,
      kind: 3, // Contact list kind
      tags: tags,
      content: '', // Contact lists have empty content
    );

    return signer.sign(unsignedEvent);
  }
}

/// Helper class to handle relay recommendations
class RelayRecommendation {
  final String url;
  final ReadWriteMarker marker;

  RelayRecommendation({
    required this.url,
    required this.marker,
  });

  static List<RelayRecommendation> fromUserRelayList(UserRelayList relayList) {
    final recommendations = <RelayRecommendation>[];
    
    for (final entry in relayList.relays.entries) {
      recommendations.add(RelayRecommendation(
        url: entry.key,
        marker: entry.value,
      ));
    }
    
    return recommendations;
  }
}