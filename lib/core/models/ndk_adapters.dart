import 'dart:convert';
import 'package:ndk/ndk.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'package:nostrface/core/models/nostr_profile.dart';

/// Adapter functions for converting between existing models and NDK models
class NostrEventAdapter {
  /// Convert from existing NostrEvent to NDK Nip01Event
  static Nip01Event toNip01Event(NostrEvent event) {
    // Use fromJson to create with all fields including id and sig
    return Nip01Event.fromJson({
      'id': event.id,
      'pubkey': event.pubkey,
      'created_at': event.created_at,
      'kind': event.kind,
      'tags': event.tags,
      'content': event.content,
      'sig': event.sig,
    });
  }

  /// Convert from NDK Nip01Event to existing NostrEvent
  static NostrEvent fromNip01Event(Nip01Event event) {
    return NostrEvent(
      id: event.id,
      pubkey: event.pubKey,
      created_at: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      sig: event.sig,
    );
  }
}

/// Adapter functions for NostrProfile and Metadata
class NostrProfileAdapter {
  /// Convert NostrProfile to NDK's Metadata
  static Metadata toMetadata(NostrProfile profile) {
    return Metadata(
      pubKey: profile.pubkey,
      name: profile.name,
      displayName: profile.displayName,
      picture: profile.picture,
      banner: profile.banner,
      about: profile.about,
      website: profile.website,
      nip05: profile.nip05,
      lud16: profile.lud16,
      lud06: profile.lud06,
      updatedAt: profile.lastUpdated,
    );
  }

  /// Create NostrProfile from NDK's Metadata
  static NostrProfile fromMetadata(Metadata metadata) {
    return NostrProfile(
      pubkey: metadata.pubKey,
      name: metadata.name,
      displayName: metadata.displayName,
      picture: metadata.picture,
      banner: metadata.banner,
      about: metadata.about,
      website: metadata.website,
      nip05: metadata.nip05,
      lud16: metadata.lud16,
      lud06: metadata.lud06,
      lastUpdated: metadata.updatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Create NostrProfile from metadata event
  static NostrProfile fromMetadataEvent(Nip01Event event) {
    if (event.kind != 0) {
      throw ArgumentError('Event must be kind 0 (metadata)');
    }

    try {
      // Parse content as JSON
      final content = jsonDecode(event.content) as Map<String, dynamic>;
      
      // Create Metadata object from parsed content
      final metadata = Metadata.fromJson(content);
      metadata.pubKey = event.pubKey;
      metadata.updatedAt = event.createdAt;
      
      return fromMetadata(metadata);
    } catch (e) {
      // Fallback to manual parsing if JSON parsing fails
      try {
        final content = jsonDecode(event.content) as Map<String, dynamic>;
        return NostrProfile(
          pubkey: event.pubKey,
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
      } catch (e) {
        // If all else fails, return minimal profile
        return NostrProfile(
          pubkey: event.pubKey,
          lastUpdated: event.createdAt,
        );
      }
    }
  }
}

/// Extension to work with contact lists
extension ContactListAdapter on ContactList {
  /// Get list of followed pubkeys
  List<String> get followedPubkeys {
    return contacts;
  }

  /// Check if a pubkey is in the contact list
  bool isFollowing(String pubkey) {
    return contacts.contains(pubkey);
  }

  /// Add a contact to the list
  ContactList addContact(String pubkey) {
    final updatedContacts = List<String>.from(contacts);
    // Add if not already exists
    if (!updatedContacts.contains(pubkey)) {
      updatedContacts.add(pubkey);
    }
    
    return ContactList(
      pubKey: this.pubKey,
      contacts: updatedContacts,
    );
  }

  /// Remove a contact from the list
  ContactList removeContact(String pubkey) {
    final updatedContacts = List<String>.from(contacts)
      ..remove(pubkey);
    
    return ContactList(
      pubKey: this.pubKey,
      contacts: updatedContacts,
    );
  }

  /// Convert to Nostr event for publishing
  Nip01Event toEvent(EventSigner signer) {
    // Build tags from contacts with relays if available
    final tags = <List<String>>[];
    
    // Add p tags for contacts
    for (int i = 0; i < contacts.length; i++) {
      final tag = ['p', contacts[i]];
      
      // Add relay if available
      if (i < contactRelays.length && contactRelays[i].isNotEmpty) {
        tag.add(contactRelays[i]);
        
        // Add petname if available  
        if (i < petnames.length && petnames[i].isNotEmpty) {
          tag.add(petnames[i]);
        }
      }
      
      tags.add(tag);
    }
    
    // Add followed tags
    for (final tagName in followedTags) {
      tags.add(['t', tagName]);
    }
    
    // Add followed communities
    for (final id in followedCommunities) {
      tags.add(['a', id]);
    }
    
    // Add followed events
    for (final id in followedEvents) {
      tags.add(['e', id]);
    }

    final unsignedEvent = Nip01Event(
      pubKey: pubKey,
      createdAt: createdAt,
      kind: 3, // Contact list kind
      tags: tags,
      content: '', // Contact lists typically have empty content
    );

    // Return the unsigned event - the caller should sign it
    return unsignedEvent;
  }
}