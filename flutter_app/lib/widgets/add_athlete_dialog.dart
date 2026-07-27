import 'dart:async';

import 'package:flutter/material.dart';

import '../services/wtt_player_lookup_service.dart';
import '../utils/pt_br.dart';
import 'athlete_photo.dart';

/// Mostra o diálogo "Adicionar atleta": busca por nome no registro (~top
/// 1000 nomes) + WTT ao vivo, e hidrata o atleta escolhido para a home.
///
/// Retorna `true` se um atleta foi adicionado/atualizado com sucesso.
Future<bool?> showAddAthleteDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _AddAthleteDialog(),
  );
}

class _AddAthleteDialog extends StatefulWidget {
  const _AddAthleteDialog();

  @override
  State<_AddAthleteDialog> createState() => _AddAthleteDialogState();
}

class _AddAthleteDialogState extends State<_AddAthleteDialog> {
  final _service = WttPlayerLookupService();
  final _controller = TextEditingController();
  Timer? _debounce;

  List<PlayerCandidate> _candidates = [];
  bool _isSearching = false;
  bool _isHydrating = false;
  String? _hydratingName;
  String? _error;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _candidates = [];
        _searched = false;
        _error = null;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () => _runSearch(value));
  }

  Future<void> _runSearch(String value) async {
    final query = value.trim();
    if (query.length < 2) return;

    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final results = await _service.search(query: query);
      if (!mounted) return;
      setState(() {
        _candidates = results;
        _isSearching = false;
        _searched = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searched = true;
        _error = 'Erro ao buscar: $error';
      });
    }
  }

  Future<void> _selectCandidate(PlayerCandidate candidate) async {
    setState(() {
      _isHydrating = true;
      _hydratingName = candidate.name;
      _error = null;
    });

    try {
      await _service.hydrate(ittfId: candidate.ittfId, gender: candidate.gender);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isHydrating = false;
        _hydratingName = null;
        _error = 'Erro ao carregar perfil completo: $error';
      });
    }
  }

  Widget _buildCandidateTile(PlayerCandidate candidate) {
    return ListTile(
      leading: AthletePhoto(
        photoUrl: candidate.photoUrl,
        width: 56,
        height: 56,
        borderRadius: 28,
        iconSize: 28,
        memCacheSize: 112,
      ),
      title: Text(candidate.name),
      subtitle: Text(
        '${PtBr.genderLabel(candidate.gender)}'
        '${candidate.countryCode != null ? " • ${candidate.countryCode}" : ""}'
        ' • ${PtBr.formatRanking(candidate.ranking)}',
      ),
      trailing: candidate.alreadyAdded
          ? const Chip(label: Text('Já na home'))
          : const Icon(Icons.add_circle_outline),
      onTap: _isHydrating ? null : () => _selectCandidate(candidate),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar atleta'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_isHydrating,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: 'Digite o nome do atleta (ex.: Bruna Takahashi)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            if (_isHydrating)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('Carregando perfil de $_hydratingName...'),
                      const SizedBox(height: 4),
                      Text(
                        'Buscando ficha, foto e títulos na WTT/Wikipedia',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              )
            else if (_candidates.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    _searched
                        ? 'Nenhum atleta encontrado para esse nome.'
                        : 'Digite ao menos 2 letras para buscar.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _candidates.length,
                  itemBuilder: (context, index) =>
                      _buildCandidateTile(_candidates[index]),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isHydrating ? null : () => Navigator.of(context).pop(false),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
