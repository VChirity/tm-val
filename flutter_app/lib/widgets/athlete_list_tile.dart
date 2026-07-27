import 'package:flutter/material.dart';

import '../models/athlete.dart';
import '../utils/pt_br.dart';
import 'athlete_photo.dart';

class AthleteListTile extends StatelessWidget {
  const AthleteListTile({
    super.key,
    required this.athlete,
    required this.onTap,
  });

  final Athlete athlete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              AthletePhoto.thumbnail(photoUrl: athlete.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (athlete.ranking != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              PtBr.formatRanking(athlete.ranking),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (athlete.ranking != null) const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            athlete.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (athlete.hasNote)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.sticky_note_2,
                              size: 20,
                              color: theme.colorScheme.tertiary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (athlete.ranking == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          PtBr.formatRanking(athlete.ranking),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    Text(
                      PtBr.formatRankingPoints(athlete.rankingPoints),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

