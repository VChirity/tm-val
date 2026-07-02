import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/athlete.dart';
import '../models/athlete_note.dart';
import '../services/athlete_repository.dart';
import '../widgets/athlete_photo.dart';

class AthleteDetailScreen extends StatefulWidget {
  const AthleteDetailScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  State<AthleteDetailScreen> createState() => _AthleteDetailScreenState();
}

class _AthleteDetailScreenState extends State<AthleteDetailScreen> {
  final _repository = AthleteRepository();
  final _noteController = TextEditingController();

  Athlete? _athlete;
  AthleteNote? _note;
  bool _isLoading = true;
  bool _isEditingNote = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final athlete = await _repository.fetchAthleteById(widget.athleteId);
      final note = await _repository.fetchNoteByAthleteId(widget.athleteId);

      if (!mounted) return;
      setState(() {
        _athlete = athlete;
        _note = note;
        _noteController.text = note?.content ?? '';
        _isEditingNote = note == null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveNote() async {
    final content = _noteController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escreva uma anotação antes de salvar.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final saved = await _repository.saveNote(
        athleteId: widget.athleteId,
        content: content,
        existingNote: _note,
      );

      if (!mounted) return;
      setState(() {
        _note = saved;
        _isEditingNote = false;
        _isSaving = false;
        _athlete = _athlete?.copyWith(hasNote: true);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anotação salva com sucesso.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $error')),
      );
    }
  }

  Future<void> _deleteNote() async {
    if (_note == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir anotação'),
        content: const Text('Deseja remover a anotação deste atleta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      await _repository.deleteNote(_note!.id);
      if (!mounted) return;

      setState(() {
        _note = null;
        _noteController.clear();
        _isEditingNote = true;
        _isSaving = false;
        _athlete = _athlete?.copyWith(hasNote: false);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anotação excluída.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao excluir: $error')),
      );
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildProfile(Athlete athlete) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: AthletePhoto.hero(photoUrl: athlete.photoUrl),
        ),
        const SizedBox(height: 20),
        Text(
          athlete.name,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Ranking #${athlete.ranking}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ficha técnica',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Divider(),
                _buildInfoRow(
                  'Gênero',
                  athlete.gender == 'male' ? 'Masculino' : 'Feminino',
                ),
                _buildInfoRow(
                  'Idade',
                  athlete.age?.toString() ?? 'Não informada',
                ),
                _buildInfoRow(
                  'Altura',
                  athlete.height != null
                      ? '${athlete.height!.toStringAsFixed(2)} m'
                      : 'Não informada',
                ),
                _buildInfoRow(
                  'Mão',
                  athlete.hand ?? 'Não informada',
                ),
                if (athlete.updatedAt != null)
                  _buildInfoRow(
                    'Atualizado em',
                    dateFormat.format(athlete.updatedAt!.toLocal()),
                  ),
              ],
            ),
          ),
        ),
        if (athlete.championshipsWon.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Títulos / destaques',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Divider(),
                  ...athlete.championshipsWon.map(
                    (title) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• '),
                          Expanded(child: Text(title)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Anotações da Valesca',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  readOnly: !_isEditingNote || _isSaving,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Comentários, observações táticas, histórico...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_isEditingNote)
                      FilledButton.icon(
                        onPressed: _isSaving ? null : _saveNote,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.save),
                        label: Text(_note == null ? 'Salvar' : 'Salvar'),
                      ),
                    if (_note != null && !_isEditingNote)
                      OutlinedButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () => setState(() => _isEditingNote = true),
                        icon: const Icon(Icons.edit),
                        label: const Text('Editar'),
                      ),
                    if (_note != null)
                      TextButton.icon(
                        onPressed: _isSaving ? null : _deleteNote,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Excluir'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, true);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_athlete?.name ?? 'Detalhes do atleta'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_errorMessage!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loadData,
                            child: const Text('Tentar novamente'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _athlete == null
                    ? const Center(child: Text('Atleta não encontrado.'))
                    : _buildProfile(_athlete!),
      ),
    );
  }
}
