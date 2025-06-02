import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nostrface/core/services/profile_service.dart';
import 'package:nostrface/core/models/nostr_profile.dart';
import 'package:go_router/go_router.dart';
import 'package:nostrface/core/utils/nostr_utils.dart';
import 'package:nostrface/shared/widgets/media_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Utility class for formatting Nostr content with proper mention handling
class ContentFormatter {
  static final RegExp _nostrMentionRegex = RegExp(
    r'nostr:((nprofile|npub|note|nevent)1[a-z0-9]+)',
  );
  
  static final RegExp _urlRegex = RegExp(
    r'https?:\/\/[^\s]+',
  );
  
  static final RegExp _imageUrlRegex = RegExp(
    r'\.(jpg|jpeg|png|gif|webp|bmp|svg)(\?.*)?$',
    caseSensitive: false,
  );
  
  /// Check if a URL points to an image
  static bool isImageUrl(String url) {
    // Check for common image extensions
    if (_imageUrlRegex.hasMatch(url)) {
      return true;
    }
    
    // Check for common image hosting services without extensions
    final imageHosts = [
      'imgur.com',
      'i.imgur.com',
      'pbs.twimg.com',
      'media.tenor.com',
      'i.redd.it',
      'media.discordapp.net',
      'cdn.discordapp.com',
      'imageproxy.iris.to',
      'imgproxy.iris.to',
      'i.nostr.build',
      'nostr.build',
      'void.cat',
      'media.nicecrew.digital',
      'media.discordapp.com',
      'cdn.nostr.build',
    ];
    
    try {
      final uri = Uri.parse(url);
      return imageHosts.any((host) => uri.host.contains(host));
    } catch (e) {
      return false;
    }
  }

  /// Parse content and return a list of TextSpan widgets with clickable mentions
  /// Note: This method should only be called for text segments that don't contain
  /// standalone image URLs, as images are handled separately by FormattedContent
  static List<InlineSpan> parseContent(
    BuildContext context,
    WidgetRef ref,
    String content,
  ) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    
    // Find all nostr mentions
    final allMatches = <_Match>[];
    
    // Add nostr mention matches
    for (final match in _nostrMentionRegex.allMatches(content)) {
      final fullBech32 = match.group(1)!; // e.g., "nprofile1xyz..."
      final type = match.group(2)!; // e.g., "nprofile"
      allMatches.add(_Match(
        match.start,
        match.end,
        match.group(0)!,
        _MatchType.nostrMention,
        type,
        fullBech32,
      ));
    }
    
    // Add URL matches that don't overlap with nostr mentions
    for (final match in _urlRegex.allMatches(content)) {
      bool overlaps = false;
      for (final existing in allMatches) {
        if ((match.start >= existing.start && match.start < existing.end) ||
            (match.end > existing.start && match.end <= existing.end)) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        allMatches.add(_Match(
          match.start,
          match.end,
          match.group(0)!,
          _MatchType.url,
        ));
      }
    }
    
    // Sort matches by start position
    allMatches.sort((a, b) => a.start.compareTo(b.start));
    
    // Build spans
    for (final match in allMatches) {
      // Add text before this match
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: content.substring(lastEnd, match.start),
        ));
      }
      
      // Add the match as a clickable span
      if (match.type == _MatchType.nostrMention) {
        spans.add(_buildMentionSpan(context, ref, match));
      } else if (match.type == _MatchType.url) {
        spans.add(_buildUrlSpan(context, match.text));
      }
      
      lastEnd = match.end;
    }
    
    // Add any remaining text
    if (lastEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastEnd),
      ));
    }
    
    return spans;
  }
  
  static InlineSpan _buildMentionSpan(
    BuildContext context,
    WidgetRef ref,
    _Match match,
  ) {
    // For now, we'll show a placeholder that will be replaced with the actual username
    // when the profile is loaded
    return WidgetSpan(
      child: _MentionWidget(
        mentionType: match.mentionType!,
        mentionId: match.mentionId!,
        fullMatch: match.text,
      ),
    );
  }
  
  static TextSpan _buildUrlSpan(BuildContext context, String url) {
    final isImage = isImageUrl(url);
    final displayText = isImage 
        ? '🖼️ Image' 
        : (url.length > 30 ? '${url.substring(0, 30)}...' : url);
    
    return TextSpan(
      text: displayText,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()
        ..onTap = () {
          if (isImage) {
            // Open image in media viewer
            MediaViewer.show(context, imageUrl: url);
          } else {
            // For non-image URLs, show snackbar for now
            // TODO: Open URL in browser
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Opening $url')),
            );
          }
        },
    );
  }
}

/// Widget that displays a mention and loads the profile name
class _MentionWidget extends ConsumerWidget {
  final String mentionType;
  final String mentionId; // This is now the full bech32 string
  final String fullMatch;
  
  const _MentionWidget({
    required this.mentionType,
    required this.mentionId,
    required this.fullMatch,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (mentionType != 'nprofile' && mentionType != 'npub') {
      // For non-profile mentions, just show the type
      return Text(
        '[$mentionType]',
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    
    // Try to decode the nprofile/npub to get the public key
    final fullBech32 = mentionId; // mentionId is already the full bech32 string
    final decodedPubkey = NostrUtils.decodeBech32PublicKey(fullBech32);
    
    // If we couldn't decode, try using the mentionId directly as it might be hex
    final pubkey = decodedPubkey ?? mentionId;
    
    // Try to get the profile from cache first
    final profileAsync = ref.watch(profileProvider(pubkey));
    
    return GestureDetector(
      onTap: () {
        // Navigate to the profile - check current route to determine the correct path
        final currentRoute = GoRouterState.of(context).uri.toString();
        if (currentRoute.startsWith('/discovery')) {
          context.go('/discovery/profile/$pubkey');
        } else {
          context.push('/profile/$pubkey');
        }
      },
      child: profileAsync.when(
        data: (profile) {
          if (profile != null) {
            return Text(
              '@${profile.displayNameOrName}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            );
          }
          // Fallback to showing the npub
          return Text(
            '@${pubkey.substring(0, 8)}...',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
            ),
          );
        },
        loading: () => Text(
          '@...',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        error: (_, __) => Text(
          '@${pubkey.substring(0, 8)}...',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

enum _MatchType {
  nostrMention,
  url,
}

class _Match {
  final int start;
  final int end;
  final String text;
  final _MatchType type;
  final String? mentionType;
  final String? mentionId;
  
  _Match(
    this.start,
    this.end,
    this.text,
    this.type,
    [this.mentionType,
    this.mentionId]
  );
}