import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nostrface/core/utils/content_formatter.dart';
import 'package:nostrface/shared/widgets/media_viewer.dart';

/// Widget that displays formatted Nostr content with inline images
class FormattedContent extends ConsumerWidget {
  final String content;
  final TextStyle? textStyle;
  
  const FormattedContent({
    Key? key,
    required this.content,
    this.textStyle,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final defaultTextStyle = textStyle ?? theme.textTheme.bodyMedium;
    
    // Parse content to identify different segments
    final segments = _parseContentSegments(content);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segments.map((segment) {
        if (segment.type == _SegmentType.image) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: _ImageBlock(imageUrl: segment.content),
          );
        } else {
          // Text segment with mentions and non-image URLs
          return RichText(
            text: TextSpan(
              style: defaultTextStyle,
              children: ContentFormatter.parseContent(
                context,
                ref,
                segment.content,
              ),
            ),
          );
        }
      }).toList(),
    );
  }
  
  List<_ContentSegment> _parseContentSegments(String content) {
    final segments = <_ContentSegment>[];
    final urlRegex = RegExp(r'https?:\/\/[^\s]+');
    
    int lastEnd = 0;
    
    for (final match in urlRegex.allMatches(content)) {
      final url = match.group(0)!;
      
      // Add text before this URL
      if (match.start > lastEnd) {
        final textBefore = content.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          segments.add(_ContentSegment(_SegmentType.text, textBefore));
        }
      }
      
      // Check if this URL is an image
      if (ContentFormatter.isImageUrl(url)) {
        // Add image as a separate segment
        segments.add(_ContentSegment(_SegmentType.image, url));
      } else {
        // Keep non-image URLs as part of text
        segments.add(_ContentSegment(_SegmentType.text, url));
      }
      
      lastEnd = match.end;
    }
    
    // Add any remaining text
    if (lastEnd < content.length) {
      final remainingText = content.substring(lastEnd).trim();
      if (remainingText.isNotEmpty) {
        segments.add(_ContentSegment(_SegmentType.text, remainingText));
      }
    }
    
    // If no segments were created, the entire content is text
    if (segments.isEmpty) {
      segments.add(_ContentSegment(_SegmentType.text, content));
    }
    
    // Merge consecutive text segments
    final mergedSegments = <_ContentSegment>[];
    for (final segment in segments) {
      if (mergedSegments.isNotEmpty && 
          mergedSegments.last.type == _SegmentType.text && 
          segment.type == _SegmentType.text) {
        // Merge with previous text segment
        mergedSegments.last = _ContentSegment(
          _SegmentType.text,
          '${mergedSegments.last.content} ${segment.content}',
        );
      } else {
        mergedSegments.add(segment);
      }
    }
    
    return mergedSegments;
  }
}

/// Widget that displays an image block within content
class _ImageBlock extends StatelessWidget {
  final String imageUrl;
  
  const _ImageBlock({
    Key? key,
    required this.imageUrl,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        MediaViewer.show(context, imageUrl: imageUrl);
      },
      child: Hero(
        tag: 'image-$imageUrl',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            placeholder: (context, url) => Container(
              height: 200,
              color: Colors.grey[300],
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              height: 200,
              color: Colors.grey[300],
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('Failed to load image', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SegmentType {
  text,
  image,
}

class _ContentSegment {
  final _SegmentType type;
  final String content;
  
  _ContentSegment(this.type, this.content);
}