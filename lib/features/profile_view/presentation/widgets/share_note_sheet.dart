import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:nostrface/core/models/nostr_event.dart';
import 'package:nostrface/core/utils/nostr_utils.dart';

class ShareNoteSheet extends StatelessWidget {
  final NostrEvent note;
  final String authorName;
  
  const ShareNoteSheet({
    Key? key,
    required this.note,
    required this.authorName,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // Generate the note ID in bech32 format (note1...)
    final noteId = _encodeNoteId(note.id);
    // Create a shareable link (you might want to customize this URL)
    final noteLink = 'https://njump.me/$noteId';
    
    return Container(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Share Note',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          // Share options
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Copy Link to Note'),
            subtitle: Text(noteLink, style: Theme.of(context).textTheme.bodySmall),
            onTap: () {
              Clipboard.setData(ClipboardData(text: noteLink));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('Copy Note ID'),
            subtitle: Text(noteId, style: Theme.of(context).textTheme.bodySmall),
            onTap: () {
              Clipboard.setData(ClipboardData(text: noteId));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Note ID copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Share via...'),
            subtitle: const Text('Open system share sheet'),
            onTap: () {
              Navigator.pop(context);
              // Share via system share sheet
              final shareText = '"${_truncateContent(note.content)}" - $authorName\n\n$noteLink';
              Share.share(
                shareText,
                subject: 'Note from $authorName on Nostr',
              );
            },
          ),
          const SizedBox(height: 16),
          // Cancel button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
          ),
          // Bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
  
  String _encodeNoteId(String hexId) {
    try {
      // Encode as note1... format using NostrUtils
      return NostrUtils.hexToNoteId(hexId);
    } catch (e) {
      return hexId;
    }
  }
  
  String _truncateContent(String content) {
    const maxLength = 100;
    if (content.length <= maxLength) return content;
    return '${content.substring(0, maxLength)}...';
  }
  
  static void show(BuildContext context, NostrEvent note, String authorName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return ShareNoteSheet(
          note: note,
          authorName: authorName,
        );
      },
    );
  }
}