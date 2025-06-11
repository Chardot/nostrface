import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nostrface/core/utils/cors_helper.dart';

class ProfileCardNew extends StatefulWidget {
  final String name;
  final String imageUrl;
  final String bio;
  final VoidCallback onTap;
  final bool isFollowed;
  final Function(String imageUrl)? onImageError;

  const ProfileCardNew({
    Key? key,
    required this.name,
    required this.imageUrl,
    required this.bio,
    required this.onTap,
    this.isFollowed = false,
    this.onImageError,
  }) : super(key: key);

  @override
  State<ProfileCardNew> createState() => _ProfileCardNewState();
}

class _ProfileCardNewState extends State<ProfileCardNew> {
  bool _hasLoggedError = false;
  bool _imageLoadFailed = false;
  
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkMode ? Colors.grey[850]! : Colors.grey[100]!;
    
    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Solid background color
            Container(
              color: backgroundColor,
            ),
            // Background image
            Builder(
              builder: (context) {
                // Get the appropriate image URL (with CORS proxy if needed)
                final imageUrl = CorsHelper.wrapWithCorsProxy(widget.imageUrl);
                
                if (kDebugMode && widget.imageUrl.contains('misskey')) {
                  print('[ProfileCardNew] Attempting to load misskey image: ${widget.imageUrl}');
                  print('[ProfileCardNew] Profile name: ${widget.name}');
                  if (imageUrl != widget.imageUrl) {
                    print('[ProfileCardNew] Using CORS proxy: $imageUrl');
                  }
                }
                
                // If image failed to load, show placeholder
                if (_imageLoadFailed) {
                  return Container(
                    color: Colors.grey[300],
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person,
                            size: 80,
                            color: Colors.grey[600],
                          ),
                          if (kDebugMode)
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                'Image failed to load',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }
                
                return CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  cacheManager: DefaultCacheManager(),
                  httpHeaders: const {
                    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
                    'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
                    'Accept-Language': 'en-US,en;q=0.9',
                    'Cache-Control': 'no-cache',
                    'Pragma': 'no-cache',
                  },
                  placeholder: (context, url) {
                    if (kDebugMode && url.contains('misskey')) {
                      print('[ProfileCardNew] Loading placeholder for: $url');
                    }
                    return Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  },
                  errorWidget: (context, url, error) {
                    if (kDebugMode && !_hasLoggedError) {
                      _hasLoggedError = true;
                      print('[ProfileCardNew] ❌ Image loading error for ${widget.name}');
                      print('[ProfileCardNew] URL: $url');
                      print('[ProfileCardNew] Error: $error');
                      print('[ProfileCardNew] Error type: ${error.runtimeType}');
                      
                      // Check if it's a CORS error (common in web)
                      if (kIsWeb) {
                        print('[ProfileCardNew] ⚠️  Running on web - this might be a CORS issue.');
                        print('[ProfileCardNew] The image server needs to send proper CORS headers:');
                        print('[ProfileCardNew] Access-Control-Allow-Origin: *');
                        print('[ProfileCardNew] Or use a CORS proxy for web builds.');
                      }
                    }
                    
                    // Mark image as failed
                    if (!_imageLoadFailed) {
                      setState(() {
                        _imageLoadFailed = true;
                      });
                    }
                    
                    if (widget.onImageError != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        widget.onImageError!(url);
                      });
                    }
                    return Container(
                      color: Colors.grey[300],
                      child: Center(
                        child: Icon(
                          Icons.person,
                          size: 80,
                          color: Colors.grey[600],
                        ),
                      ),
                    );
                  },
                );
              }
            ),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.8),
                  ],
                  stops: const [0.0, 0.5, 0.7, 1.0],
                ),
              ),
            ),
            // Content positioned at bottom
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.isFollowed)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Following',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.bio,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}