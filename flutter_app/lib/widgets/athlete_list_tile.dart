import 'package:flutter/material.dart';

import '../models/athlete.dart';
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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: AthletePhoto.thumbnail(photoUrl: athlete.photoUrl),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '#${athlete.ranking}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                athlete.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (athlete.hasNote)
              Tooltip(
                message: 'Possui anotação da Valesca',
                child: Icon(
                  Icons.sticky_note_2,
                  color: theme.colorScheme.tertiary,
                ),
              ),
          ],
        ),
        subtitle: Text(
          athlete.age != null ? '${athlete.age} anos' : 'Idade não informada',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
