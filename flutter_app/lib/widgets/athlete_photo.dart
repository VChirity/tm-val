import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Fotos WTT são retratos verticais — usamos [BoxFit.contain] para não cortar.
class AthletePhoto extends StatelessWidget {
  const AthletePhoto({
    super.key,
    this.photoUrl,
    required this.width,
    required this.height,
    this.borderRadius = 12,
    this.iconSize = 28,
    this.memCacheSize = 160,
  });

  const AthletePhoto.thumbnail({
    super.key,
    required this.photoUrl,
  })  : width = 52,
        height = 52,
        borderRadius = 10,
        iconSize = 24,
        memCacheSize = 120;

  const AthletePhoto.hero({
    super.key,
    required this.photoUrl,
  })  : width = 240,
        height = 300,
        borderRadius = 16,
        iconSize = 64,
        memCacheSize = 480;

  final String? photoUrl;
  final double width;
  final double height;
  final double borderRadius;
  final double iconSize;
  final int memCacheSize;

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).colorScheme.surfaceContainerHighest;

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: photoUrl != null && photoUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: photoUrl!,
                  width: width,
                  height: height,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  memCacheWidth: memCacheSize,
                  memCacheHeight: memCacheSize,
                  maxWidthDiskCache: memCacheSize,
                  maxHeightDiskCache: memCacheSize,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (_, __) => _placeholder(context, showLoader: true),
                  errorWidget: (_, __, ___) => _placeholder(context),
                )
              : _placeholder(context),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context, {bool showLoader = false}) {
    if (showLoader) {
      return Center(
        child: SizedBox(
          width: iconSize * 0.7,
          height: iconSize * 0.7,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Center(
      child: Icon(
        Icons.person,
        size: iconSize,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
