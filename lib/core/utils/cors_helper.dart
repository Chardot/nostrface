import 'package:flutter/foundation.dart';

/// Helper class to handle CORS issues on web platform
class CorsHelper {
  /// List of known CORS proxy services (use with caution in production)
  static const List<String> corsProxies = [
    'https://corsproxy.io/?',
    'https://api.allorigins.win/raw?url=',
  ];
  
  /// Check if URL needs CORS proxy (for web platform)
  static bool needsCorsProxy(String url) {
    if (!kIsWeb) return false;
    
    // List of domains known to have CORS issues
    final problematicDomains = [
      'misskey.bubbletea.dev',
      'social.heise.de',
      'poliverso.org',
      's3.solarcom.ch',
      'media.misskeyusercontent.com',
    ];
    
    final uri = Uri.parse(url);
    return problematicDomains.any((domain) => uri.host.contains(domain));
  }
  
  /// Wrap URL with CORS proxy if needed
  static String wrapWithCorsProxy(String url) {
    if (!needsCorsProxy(url)) return url;
    
    // Use the first available CORS proxy
    // In production, you should run your own CORS proxy
    final proxy = corsProxies.first;
    
    if (kDebugMode) {
      print('[CorsHelper] Wrapping URL with CORS proxy: $url');
      print('[CorsHelper] Proxied URL: $proxy${Uri.encodeComponent(url)}');
    }
    
    return '$proxy${Uri.encodeComponent(url)}';
  }
  
  /// Get original URL from proxied URL
  static String getOriginalUrl(String proxiedUrl) {
    for (final proxy in corsProxies) {
      if (proxiedUrl.startsWith(proxy)) {
        final encoded = proxiedUrl.substring(proxy.length);
        return Uri.decodeComponent(encoded);
      }
    }
    return proxiedUrl;
  }
}