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
  });

  const AthletePhoto.thumbnail({
    super.key,
    required this.photoUrl,
  })  : width = 56,
        height = 56,
        borderRadius = 12,
        iconSize = 28;

  const AthletePhoto.hero({
    super.key,
    required this.photoUrl,
  })  : width = 280,
        height = 340,
        borderRadius = 16,
        iconSize = 72;

  final String? photoUrl;
  final double width;
  final double height;
  final double borderRadius;
  final double iconSize;

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
                  placeholder: (_, __) => Center(
                    child: SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => _placeholder(context),
                )
              : _placeholder(context),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Center(
      child: Icon(
        Icons.person,
        size: iconSize,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
