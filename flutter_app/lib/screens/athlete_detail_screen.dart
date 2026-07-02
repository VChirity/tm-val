import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/athlete.dart';
import '../models/athlete_note.dart';
import '../services/athlete_repository.dart';
import '../utils/pt_br.dart';
import '../widgets/athlete_photo.dart';

class AthleteDetailScreen extends StatefulWidget {
  const AthleteDetailScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  State<AthleteDetailScreen> createState() => _AthleteDetailScreenState();
}

class _AthleteDetailScreenState extends State<AthleteDetailScreen> {
  final _repository = AthleteRepository();
  final _newNoteController = TextEditingController();

  Athlete? _athlete;
  List<AthleteNote> _notes = [];
  String? _editingNoteId;
  final _editNoteController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  bool _notesChanged = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _newNoteController.dispose();
    _editNoteController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _editingNoteId = null;
    });

    try {
      final athlete = await _repository.fetchAthleteById(widget.athleteId);
      final notes = await _repository.fetchNotesByAthleteId(widget.athleteId);

      if (!mounted) return;
      setState(() {
        _athlete = athlete;
        _notes = notes;
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

  Future<void> _addNote() async {
    final content = _newNoteController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escreva um tópico antes de salvar.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final saved = await _repository.addNote(
        athleteId: widget.athleteId,
        content: content,
      );

      if (!mounted) return;
      setState(() {
        _notes = [..._notes, saved];
        _newNoteController.clear();
        _isSaving = false;
        _notesChanged = true;
        _athlete = _athlete?.copyWith(hasNote: true);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $error')),
      );
    }
  }

  void _startEditing(AthleteNote note) {
    setState(() {
      _editingNoteId = note.id;
      _editNoteController.text = note.content;
    });
  }

  void _cancelEditing() {
    setState(() {
      _editingNoteId = null;
      _editNoteController.clear();
    });
  }

  Future<void> _saveEditedNote(AthleteNote note) async {
    final content = _editNoteController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O tópico não pode ficar vazio.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updated = await _repository.updateNote(
        noteId: note.id,
        content: content,
      );

      if (!mounted) return;
      setState(() {
        _notes = _notes
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
        _editingNoteId = null;
        _editNoteController.clear();
        _isSaving = false;
        _notesChanged = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao editar: $error')),
      );
    }
  }

  Future<void> _deleteNote(AthleteNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir tópico'),
        content: Text('Deseja remover este tópico?\n\n"${note.content}"'),
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
      await _repository.deleteNote(note.id);
      if (!mounted) return;

      final updatedNotes =
          _notes.where((item) => item.id != note.id).toList();

      setState(() {
        _notes = updatedNotes;
        _isSaving = false;
        _notesChanged = true;
        _athlete = _athlete?.copyWith(hasNote: updatedNotes.isNotEmpty);
        if (_editingNoteId == note.id) {
          _editingNoteId = null;
          _editNoteController.clear();
        }
      });
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

  Widget _buildNoteTopic(AthleteNote note) {
    final isEditing = _editingNoteId == note.id;

    if (isEditing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _editNoteController,
              enabled: !_isSaving,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _isSaving ? null : () => _saveEditedNote(note),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Salvar'),
                ),
                TextButton(
                  onPressed: _isSaving ? null : _cancelEditing,
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('• '),
          ),
          Expanded(
            child: Text(
              note.content,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          IconButton(
            tooltip: 'Editar tópico',
            visualDensity: VisualDensity.compact,
            onPressed: _isSaving ? null : () => _startEditing(note),
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Excluir tópico',
            visualDensity: VisualDensity.compact,
            onPressed: _isSaving ? null : () => _deleteNote(note),
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anotações da Valesca',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
            if (_notes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Nenhum tópico salvo ainda.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              ..._notes.map(_buildNoteTopic),
            const SizedBox(height: 8),
            TextField(
              controller: _newNoteController,
              enabled: !_isSaving,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addNote(),
              decoration: const InputDecoration(
                hintText: 'Novo tópico: observação tática, histórico...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isSaving ? null : _addNote,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: const Text('Adicionar tópico'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(Athlete athlete) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 520 ? 12 : 16,
        vertical: 16,
      ),
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
          'Ranking #${athlete.ranking} • ${PtBr.formatRankingPoints(athlete.rankingPoints)}',
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
                _buildInfoRow('Gênero', PtBr.genderLabel(athlete.gender)),
                _buildInfoRow(
                  'Pontuação',
                  PtBr.formatRankingPoints(athlete.rankingPoints),
                ),
                _buildInfoRow('Idade', PtBr.formatAge(athlete.age)),
                _buildInfoRow(
                  'Altura',
                  athlete.height != null
                      ? '${athlete.height!.toStringAsFixed(2)} m'
                      : 'Não informada',
                ),
                _buildInfoRow('Mão', PtBr.handLabel(athlete.hand)),
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
                          Expanded(
                            child: Text(PtBr.translateHighlight(title)),
                          ),
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
        _buildNotesSection(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _notesChanged);
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
