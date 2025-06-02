import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MediaViewer extends ConsumerStatefulWidget {
  final String imageUrl;
  final String? heroTag;

  const MediaViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
  });

  static Future<void> show(
    BuildContext context, {
    required String imageUrl,
    String? heroTag,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black87,
      enableDrag: true,
      builder: (context) => MediaViewer(
        imageUrl: imageUrl,
        heroTag: heroTag,
      ),
    );
  }

  @override
  ConsumerState<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends ConsumerState<MediaViewer>
    with SingleTickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;

  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _normalizedOffset = Offset.zero;
  double _dragExtent = 0.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onAnimateReset() {
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    _animationController.forward(from: 0);
    _animation!.addListener(() {
      _transformationController.value = _animation!.value;
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_scale > 1.0) return; // Disable drag when zoomed in
    
    setState(() {
      _isDragging = true;
      _dragExtent += details.delta.dy;
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_scale > 1.0) return;
    
    setState(() {
      _isDragging = false;
    });

    // If dragged down more than 100 pixels, close the viewer
    if (_dragExtent > 100) {
      Navigator.of(context).pop();
    } else {
      // Animate back to original position
      setState(() {
        _dragExtent = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final opacity = 1.0 - (_dragExtent.abs() / 300).clamp(0.0, 1.0);

    return AnimatedContainer(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
      transform: Matrix4.translationValues(0, _dragExtent, 0),
      child: Opacity(
        opacity: opacity,
        child: Container(
          height: screenSize.height,
          width: screenSize.width,
          color: Colors.black.withOpacity(opacity * 0.9),
          child: Stack(
            children: [
              // Image viewer
              GestureDetector(
                onVerticalDragUpdate: _handleDragUpdate,
                onVerticalDragEnd: _handleDragEnd,
                onDoubleTap: () {
                  if (_scale > 1.0) {
                    _onAnimateReset();
                    setState(() {
                      _scale = 1.0;
                    });
                  } else {
                    final position = TapDownDetails(
                      globalPosition: Offset(
                        screenSize.width / 2,
                        screenSize.height / 2,
                      ),
                    );
                    _handleDoubleTap(position);
                  }
                },
                onDoubleTapDown: _handleDoubleTap,
                child: Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    onInteractionUpdate: (details) {
                      setState(() {
                        _scale = details.scale;
                      });
                    },
                    onInteractionEnd: (details) {
                      setState(() {
                        _previousScale = _scale;
                      });
                    },
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Hero(
                      tag: widget.heroTag ?? widget.imageUrl,
                      child: CachedNetworkImage(
                        imageUrl: widget.imageUrl,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[900],
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[900],
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.red[400],
                                  size: 48,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      // Force rebuild to retry loading
                                    });
                                  },
                                  child: const Text(
                                    'Retry',
                                    style: TextStyle(
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Close button
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
              // Image info (optional - can show URL or metadata)
              if (_scale <= 1.0)
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.grey[400],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Swipe down to close • Double tap to zoom',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_scale > 1.0) {
      _onAnimateReset();
      setState(() {
        _scale = 1.0;
      });
    } else {
      final position = details.localPosition;
      final double scale = 2.0;
      
      final x = -position.dx * (scale - 1);
      final y = -position.dy * (scale - 1);
      
      final zoomed = Matrix4.identity()
        ..translate(x, y)
        ..scale(scale);
      
      final value = Matrix4Tween(
        begin: _transformationController.value,
        end: zoomed,
      ).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ),
      );
      
      _animation = value;
      _animationController.forward(from: 0);
      _animation!.addListener(() {
        _transformationController.value = _animation!.value;
      });
      
      setState(() {
        _scale = scale;
      });
    }
  }
}

// Extension to make it easier to show the media viewer
extension MediaViewerExtension on BuildContext {
  Future<void> showMediaViewer({
    required String imageUrl,
    String? heroTag,
  }) {
    return MediaViewer.show(
      this,
      imageUrl: imageUrl,
      heroTag: heroTag,
    );
  }
}