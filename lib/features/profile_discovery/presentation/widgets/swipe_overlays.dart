import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

class SwipeOverlay extends StatelessWidget {
  final CardSwiperDirection direction;
  final double progress;

  const SwipeOverlay({
    Key? key,
    required this.direction,
    required this.progress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final opacity = progress.clamp(0.0, 1.0);
    
    if (direction == CardSwiperDirection.none || opacity == 0) {
      return const SizedBox.shrink();
    }

    Widget content;
    Color overlayColor;
    IconData icon;
    String text;

    switch (direction) {
      case CardSwiperDirection.left:
        overlayColor = Colors.red.withOpacity(0.5 * opacity);
        icon = Icons.close;
        text = 'NOPE';
        break;
      case CardSwiperDirection.right:
        overlayColor = Colors.green.withOpacity(0.5 * opacity);
        icon = Icons.favorite;
        text = 'LIKE';
        break;
      case CardSwiperDirection.top:
        overlayColor = Colors.blue.withOpacity(0.5 * opacity);
        icon = Icons.star;
        text = 'SUPER LIKE';
        break;
      case CardSwiperDirection.bottom:
        overlayColor = Colors.orange.withOpacity(0.5 * opacity);
        icon = Icons.block;
        text = 'PASS';
        break;
      default:
        return const SizedBox.shrink();
    }

    // Create a positioned overlay based on swipe direction
    switch (direction) {
      case CardSwiperDirection.left:
        content = Positioned(
          top: 60,
          right: 20,
          child: Transform.rotate(
            angle: 0.3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red, width: 4),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.9),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        );
        break;
      case CardSwiperDirection.right:
        content = Positioned(
          top: 60,
          left: 20,
          child: Transform.rotate(
            angle: -0.3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green, width: 4),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.9),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        );
        break;
      case CardSwiperDirection.top:
        content = Positioned(
          bottom: 120,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        break;
      case CardSwiperDirection.bottom:
        content = Positioned(
          top: MediaQuery.of(context).size.height * 0.35,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.orange, width: 4),
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.9),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        );
        break;
      default:
        return const SizedBox.shrink();
    }
    
    // Add background overlay
    final backgroundOverlay = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: overlayColor.withOpacity(0.3),
      ),
    );
    
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          backgroundOverlay,
          content,
        ],
      ),
    );
  }
}

class NopeOverlay extends StatelessWidget {
  final double opacity;

  const NopeOverlay({
    Key? key,
    required this.opacity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      right: 20,
      child: Transform.rotate(
        angle: 0.3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.red, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'NOPE',
            style: TextStyle(
              color: Colors.red,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ).copyWith(
              color: Colors.red.withOpacity(opacity),
            ),
          ),
        ),
      ),
    );
  }
}

class LikeOverlay extends StatelessWidget {
  final double opacity;

  const LikeOverlay({
    Key? key,
    required this.opacity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 50,
      left: 20,
      child: Transform.rotate(
        angle: -0.3,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'LIKE',
            style: TextStyle(
              color: Colors.green,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ).copyWith(
              color: Colors.green.withOpacity(opacity),
            ),
          ),
        ),
      ),
    );
  }
}

class SuperLikeOverlay extends StatelessWidget {
  final double opacity;

  const SuperLikeOverlay({
    Key? key,
    required this.opacity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'SUPER LIKE',
            style: TextStyle(
              color: Colors.blue,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ).copyWith(
              color: Colors.blue.withOpacity(opacity),
            ),
          ),
        ),
      ),
    );
  }
}

class PassOverlay extends StatelessWidget {
  final double opacity;

  const PassOverlay({
    Key? key,
    required this.opacity,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.4,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.orange, width: 3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'PASS',
            style: TextStyle(
              color: Colors.orange,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ).copyWith(
              color: Colors.orange.withOpacity(opacity),
            ),
          ),
        ),
      ),
    );
  }
}