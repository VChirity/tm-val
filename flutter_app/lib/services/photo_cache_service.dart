import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/athlete.dart';

/// Pré-carrega fotos dos atletas para exibição instantânea na lista.
class PhotoCacheService {
  PhotoCacheService._();

  static Future<void> warmUpAthletes(
    BuildContext context,
    List<Athlete> athletes,
  ) async {
    if (!context.mounted) return;

    final urls = athletes
        .map((athlete) => athlete.photoUrl)
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toSet();

    final futures = urls.map(
      (url) => precacheImage(
        CachedNetworkImageProvider(
          url,
          maxWidth: 160,
          maxHeight: 160,
        ),
        context,
      ),
    );

    await Future.wait(futures);
  }
}
