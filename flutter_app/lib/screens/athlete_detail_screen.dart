import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/athlete.dart';
import '../models/athlete_note.dart';
import '../services/athlete_repository.dart';
import '../services/wtt_head_to_head_service.dart';
import '../utils/pt_br.dart';
import '../utils/title_utils.dart';
import '../widgets/athlete_photo.dart';

class AthleteDetailScreen extends StatefulWidget {
  const AthleteDetailScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  State<AthleteDetailScreen> createState() => _AthleteDetailScreenState();
}

class _AthleteDetailScreenState extends State<AthleteDetailScreen> {
  final _repository = AthleteRepository();
  final _h2hService = WttHeadToHeadService();
  final _newNoteController = TextEditingController();
  final _opponentSearchController = TextEditingController();
  final _pointsController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _bioController = TextEditingController();

  Athlete? _athlete;
  List<AthleteNote> _notes = [];
  String? _editingNoteId;
  final _editNoteController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;
  bool _notesChanged = false;
  bool _editingFicha = false;
  String? _editHand;
  bool _profileChanged = false;

  int? _fromYear;
  TitleCategory _titleCategory = TitleCategory.all;
  Athlete? _opponent;
  HeadToHeadSummary? _h2hSummary;
  bool _h2hLoading = false;
  String? _h2hError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _newNoteController.dispose();
    _editNoteController.dispose();
    _opponentSearchController.dispose();
    _pointsController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _fillFichaControllers(Athlete athlete) {
    _pointsController.text =
        athlete.rankingPoints != null ? '${athlete.rankingPoints}' : '';
    _ageController.text = athlete.age != null ? '${athlete.age}' : '';
    _heightController.text = athlete.height != null
        ? athlete.height!.toStringAsFixed(2)
        : '';
    _bioController.text = athlete.shortBio?.trim() ?? '';
    _editHand = _normalizeHandValue(athlete.hand);
  }

  String? _normalizeHandValue(String? hand) {
    if (hand == null || hand.trim().isEmpty) return null;
    final normalized = hand.toLowerCase();
    if (normalized.contains('right') ||
        normalized == 'r' ||
        normalized.contains('destro')) {
      return 'Right';
    }
    if (normalized.contains('left') ||
        normalized == 'l' ||
        normalized.contains('canhot')) {
      return 'Left';
    }
    if (normalized.contains('both') || normalized.contains('amb')) {
      return 'Ambidextrous';
    }
    return hand;
  }

  void _startEditingFicha() {
    final athlete = _athlete;
    if (athlete == null) return;
    _fillFichaControllers(athlete);
    setState(() => _editingFicha = true);
  }

  void _cancelEditingFicha() {
    setState(() => _editingFicha = false);
  }

  Future<void> _saveFicha() async {
    final athlete = _athlete;
    if (athlete == null) return;

    final pointsText = _pointsController.text.trim();
    final ageText = _ageController.text.trim();
    final heightText = _heightController.text.trim().replaceAll(',', '.');
    final bioText = _bioController.text.trim();

    int? rankingPoints;
    if (pointsText.isNotEmpty) {
      rankingPoints = int.tryParse(pointsText);
      if (rankingPoints == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pontuação inválida.')),
        );
        return;
      }
    }

    int? age;
    if (ageText.isNotEmpty) {
      age = int.tryParse(ageText);
      if (age == null || age < 5 || age > 120) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Idade inválida.')),
        );
        return;
      }
    }

    double? height;
    if (heightText.isNotEmpty) {
      height = double.tryParse(heightText);
      if (height == null || height < 1.0 || height > 2.5) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Altura inválida. Use metros (ex.: 1.75).'),
          ),
        );
        return;
      }
    }

    final edited = <String>{};
    if (rankingPoints != athlete.rankingPoints) {
      edited.add('ranking_points');
    }
    if (age != athlete.age) edited.add('age');
    final currentHeight = athlete.height;
    final heightChanged = height == null && currentHeight != null ||
        height != null && currentHeight == null ||
        (height != null &&
            currentHeight != null &&
            (height - currentHeight).abs() > 0.001);
    if (heightChanged) edited.add('height');
    if (_editHand != _normalizeHandValue(athlete.hand)) {
      edited.add('hand');
    }
    if (bioText != (athlete.shortBio?.trim() ?? '')) {
      edited.add('short_bio');
    }

    if (edited.isEmpty) {
      setState(() => _editingFicha = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhuma alteração para salvar.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updated = await _repository.updateAthleteProfile(
        athleteId: widget.athleteId,
        rankingPoints: rankingPoints,
        age: age,
        height: height,
        hand: _editHand,
        shortBio: bioText.isEmpty ? null : bioText,
        editedFields: edited,
      );

      if (!mounted) return;
      setState(() {
        _athlete = updated.copyWith(hasNote: _notes.isNotEmpty);
        _editingFicha = false;
        _isSaving = false;
        _profileChanged = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ficha técnica salva. Valores manuais serão mantidos no Atualizar.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar ficha: $error')),
      );
    }
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

  Future<void> _loadHeadToHead(Athlete opponent) async {
    final athlete = _athlete;
    if (athlete?.ittfId == null || opponent.ittfId == null) {
      setState(() {
        _h2hError = 'Um dos jogadores não possui ID ITTF cadificado.';
        _h2hSummary = null;
      });
      return;
    }

    setState(() {
      _opponent = opponent;
      _h2hLoading = true;
      _h2hError = null;
      _h2hSummary = null;
    });

    try {
      final summary = await _h2hService.fetchSummary(
        player1IttfId: athlete!.ittfId!,
        player2IttfId: opponent.ittfId!,
        player1Name: athlete.name,
        player2Name: opponent.name,
      );

      if (!mounted) return;
      setState(() {
        _h2hSummary = summary;
        _h2hLoading = false;
        if (summary == null) {
          _h2hError = 'Nenhum confronto encontrado na WTT.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _h2hLoading = false;
        _h2hError = 'Erro ao buscar confronto: $error';
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

  Widget _buildTitlesSection(Athlete athlete) {
    final allTitles = athlete.championshipsWon;
    final years = TitleUtils.availableYears(allTitles);
    final displayed = TitleUtils.buildDisplayTitles(
      allTitles,
      fromYear: _fromYear,
      category: _titleCategory,
    );

    return Card(
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
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('A partir de:'),
                DropdownButton<int?>(
                  value: _fromYear,
                  hint: const Text('Todos'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    ...years.map(
                      (year) => DropdownMenuItem<int?>(
                        value: year,
                        child: Text('$year'),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _fromYear = value),
                ),
                const Text('Categoria:'),
                DropdownButton<TitleCategory>(
                  value: _titleCategory,
                  items: const [
                    DropdownMenuItem(
                      value: TitleCategory.all,
                      child: Text('Todos'),
                    ),
                    DropdownMenuItem(
                      value: TitleCategory.wtt,
                      child: Text('WTT'),
                    ),
                    DropdownMenuItem(
                      value: TitleCategory.nacional,
                      child: Text('Nacionais'),
                    ),
                    DropdownMenuItem(
                      value: TitleCategory.panAm,
                      child: Text('Pan-Am'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _titleCategory = value);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (displayed.isEmpty)
              Text(
                _fromYear == null && _titleCategory == TitleCategory.all
                    ? 'Nenhum título cadastrado.'
                    : 'Nenhum título encontrado para os filtros selecionados.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              )
            else
              ...displayed.map(
                (title) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(
                        child: Text(
                          title,
                          style: TitleUtils.isWinLine(title)
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadToHeadSection(Athlete athlete) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confronto direto',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Divider(),
            if (athlete.ittfId == null)
              const Text(
                'Este atleta ainda não possui ID ITTF. Clique em Atualizar na lista.',
              )
            else ...[
              Autocomplete<Athlete>(
                optionsBuilder: (textEditingValue) async {
                  final query = textEditingValue.text.trim();
                  if (query.length < 2) {
                    return const Iterable<Athlete>.empty();
                  }
                  return _repository.searchAthletes(
                    query: query,
                    excludeId: athlete.id,
                  );
                },
                displayStringForOption: (option) => option.name,
                onSelected: _loadHeadToHead,
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  _opponentSearchController.value = controller.value;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'Buscar adversário (ex.: Hugo Calderano)',
                      border: const OutlineInputBorder(),
                      suffixIcon: _h2hLoading
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : const Icon(Icons.search),
                    ),
                  );
                },
              ),
              if (_opponent != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${athlete.name} x ${_opponent!.name}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
              if (_h2hError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _h2hError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (_h2hSummary != null) ...[
                const SizedBox(height: 12),
                _buildInfoRow(
                  'Total de partidas',
                  '${_h2hSummary!.totalMatches}',
                ),
                _buildInfoRow(
                  'Vitórias de ${athlete.name}',
                  '${_h2hSummary!.player1Wins}',
                ),
                _buildInfoRow(
                  'Vitórias de ${_opponent?.name ?? "adversário"}',
                  '${_h2hSummary!.player2Wins}',
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Fonte: WTT Head-to-Head',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !_isSaving,
              keyboardType: keyboardType,
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFichaSection(Athlete athlete) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Ficha técnica',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (!_editingFicha)
                  IconButton(
                    tooltip: 'Editar ficha técnica',
                    onPressed: _isSaving ? null : _startEditingFicha,
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
            const Divider(),
            if (_editingFicha) ...[
              _buildInfoRow('Gênero', PtBr.genderLabel(athlete.gender)),
              _buildEditableField(
                label: 'Pontuação',
                controller: _pointsController,
                keyboardType: TextInputType.number,
                hint: 'ex.: 1250',
              ),
              _buildEditableField(
                label: 'Idade',
                controller: _ageController,
                keyboardType: TextInputType.number,
                hint: 'anos',
              ),
              _buildEditableField(
                label: 'Altura',
                controller: _heightController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                hint: 'metros (ex.: 1.75)',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 120,
                      child: Text(
                        'Mão',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _editHand,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Não informada'),
                          ),
                          DropdownMenuItem<String?>(
                            value: 'Right',
                            child: Text('Destro'),
                          ),
                          DropdownMenuItem<String?>(
                            value: 'Left',
                            child: Text('Canhoto'),
                          ),
                          DropdownMenuItem<String?>(
                            value: 'Ambidextrous',
                            child: Text('Ambidestro'),
                          ),
                        ],
                        onChanged: _isSaving
                            ? null
                            : (value) => setState(() => _editHand = value),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bio curta',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _bioController,
                enabled: !_isSaving,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Resumo curto do atleta…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _saveFicha,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Salvar'),
                  ),
                  TextButton(
                    onPressed: _isSaving ? null : _cancelEditingFicha,
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ] else ...[
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
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(Athlete athlete) {
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
          'Ranking ${PtBr.formatRanking(athlete.ranking)} • ${PtBr.formatRankingPoints(athlete.rankingPoints)}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        _buildFichaSection(athlete),
        if (!_editingFicha &&
            athlete.shortBio != null &&
            athlete.shortBio!.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            athlete.shortBio!.trim(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (athlete.championshipsWon.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildTitlesSection(athlete),
        ],
        const SizedBox(height: 16),
        _buildHeadToHeadSection(athlete),
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
          Navigator.pop(context, _notesChanged || _profileChanged);
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
