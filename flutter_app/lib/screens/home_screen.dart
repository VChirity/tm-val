import 'package:flutter/material.dart';

import '../models/athlete.dart';
import '../models/broadcast_note.dart';
import '../services/athlete_repository.dart';
import '../services/app_auth_service.dart';
import '../services/broadcast_note_repository.dart';
import '../services/photo_cache_service.dart';
import '../widgets/add_athlete_dialog.dart';
import '../widgets/athlete_list_tile.dart';
import '../widgets/sync_progress_dialog.dart';
import 'athlete_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _repository = AthleteRepository();
  final _broadcastRepository = BroadcastNoteRepository();
  final _auth = AppAuthService();
  final _searchController = TextEditingController();
  final _newBroadcastController = TextEditingController();
  final _editBroadcastController = TextEditingController();

  late final TabController _tabController;

  List<Athlete> _maleAthletes = [];
  List<Athlete> _femaleAthletes = [];
  List<BroadcastNote> _broadcastNotes = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isSavingBroadcast = false;
  bool _broadcastExpanded = false;
  String? _editingBroadcastId;
  String? _errorMessage;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
    _loadAthletes();
    _loadBroadcastNotes();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _newBroadcastController.dispose();
    _editBroadcastController.dispose();
    super.dispose();
  }

  Future<void> _loadBroadcastNotes() async {
    try {
      final notes = await _broadcastRepository.fetchNotes();
      if (!mounted) return;
      setState(() => _broadcastNotes = notes);
    } catch (_) {}
  }

  Future<void> _loadAthletes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _repository.fetchAthletes(gender: 'male'),
        _repository.fetchAthletes(gender: 'female'),
      ]);

      if (!mounted) return;
      setState(() {
        _maleAthletes = results[0];
        _femaleAthletes = results[1];
        _isLoading = false;
      });

      if (!mounted) return;
      // Só pré-carrega as primeiras fotos visíveis de cada aba (não as ~100+
      // de cada gênero) para não travar o carregamento inicial da home.
      const visibleCount = 20;
      await PhotoCacheService.warmUpAthletes(
        context,
        [
          ..._maleAthletes.take(visibleCount),
          ..._femaleAthletes.take(visibleCount),
        ],
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _syncFromWtt() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    final result = await showWttSyncDialog(context);

    if (!mounted) return;
    setState(() => _isSyncing = false);

    if (result == null) {
      return;
    }

    if (result.hasUpdates) {
      await _loadAthletes();
      if (!mounted) return;
      final titlesPart = result.titlesChanged > 0
          ? ', ${result.titlesChanged} título(s) atualizado(s)'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.athletesChecked} atletas verificados'
            '$titlesPart — '
            'semana ${result.rankingWeek ?? "?"} de ${result.rankingYear ?? "?"}.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.athletesChecked} atletas verificados — nada mudou.',
          ),
        ),
      );
    }
  }

  Future<void> _addAthlete() async {
    final added = await showAddAthleteDialog(context);
    if (added == true) {
      await _loadAthletes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Atleta adicionado à home.')),
      );
    }
  }

  Future<void> _addBroadcastNote() async {
    final content = _newBroadcastController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSavingBroadcast = true);
    try {
      final saved = await _broadcastRepository.addNote(content);
      if (!mounted) return;
      setState(() {
        _broadcastNotes = [..._broadcastNotes, saved];
        _newBroadcastController.clear();
        _isSavingBroadcast = false;
        _broadcastExpanded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingBroadcast = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar anotação: $error')),
      );
    }
  }

  Future<void> _saveBroadcastEdit(BroadcastNote note) async {
    final content = _editBroadcastController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSavingBroadcast = true);
    try {
      final updated = await _broadcastRepository.updateNote(
        noteId: note.id,
        content: content,
      );
      if (!mounted) return;
      setState(() {
        _broadcastNotes = _broadcastNotes
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
        _editingBroadcastId = null;
        _editBroadcastController.clear();
        _isSavingBroadcast = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingBroadcast = false);
    }
  }

  Future<void> _deleteBroadcastNote(BroadcastNote note) async {
    setState(() => _isSavingBroadcast = true);
    try {
      await _broadcastRepository.deleteNote(note.id);
      if (!mounted) return;
      setState(() {
        _broadcastNotes =
            _broadcastNotes.where((item) => item.id != note.id).toList();
        _isSavingBroadcast = false;
        if (_editingBroadcastId == note.id) {
          _editingBroadcastId = null;
          _editBroadcastController.clear();
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSavingBroadcast = false);
    }
  }

  Widget _buildBroadcastNoteItem(BroadcastNote note) {
    if (_editingBroadcastId == note.id) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _editBroadcastController,
              maxLines: 2,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: _isSavingBroadcast
                      ? null
                      : () => _saveBroadcastEdit(note),
                  child: const Text('Salvar'),
                ),
                TextButton(
                  onPressed: _isSavingBroadcast
                      ? null
                      : () => setState(() => _editingBroadcastId = null),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(child: Text(note.content)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () {
              setState(() {
                _editingBroadcastId = note.id;
                _editBroadcastController.text = note.content;
              });
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _deleteBroadcastNote(note),
          ),
        ],
      ),
    );
  }

  Widget _buildBroadcastNotesCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ExpansionTile(
        initiallyExpanded: _broadcastExpanded,
        onExpansionChanged: (value) =>
            setState(() => _broadcastExpanded = value),
        title: Text(
          'Anotações gerais (${_broadcastNotes.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: const Text(
          'Notas de transmissão sem vínculo com atleta',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_broadcastNotes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Nenhuma anotação geral ainda.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                else
                  ..._broadcastNotes.map(_buildBroadcastNoteItem),
                TextField(
                  controller: _newBroadcastController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Nova anotação: convidado, curiosidade...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _isSavingBroadcast ? null : _addBroadcastNote,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar tópico'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Athlete> _filterAthletes(List<Athlete> athletes) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return athletes;
    }

    return athletes
        .where((athlete) => athlete.name.toLowerCase().contains(query))
        .toList();
  }

  Future<void> _openAthleteDetail(Athlete athlete) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AthleteDetailScreen(athleteId: athlete.id),
      ),
    );

    if (updated == true) {
      await _loadAthletes();
    }
  }

  Widget _buildAthleteList(List<Athlete> athletes) {
    final filtered = _filterAthletes(athletes);

    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _searchQuery.isEmpty
                    ? 'Nenhum atleta encontrado. Toque em "Atualizar" para buscar na WTT.'
                    : 'Nenhum resultado para "$_searchQuery".',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAthletes,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final athlete = filtered[index];
          return AthleteListTile(
            athlete: athlete,
            onTap: () => _openAthleteDetail(athlete),
          );
        },
      ),
    );
  }

  List<Widget> _buildAppBarActions(bool compact) {
    if (compact) {
      return [
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'sync') {
              _syncFromWtt();
            } else if (value == 'add') {
              _addAthlete();
            } else if (value == 'logout') {
              _auth.signOut();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: !_isSyncing,
              value: 'sync',
              child: ListTile(
                leading: _isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_download_outlined),
                title: const Text('Atualizar ranking'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'add',
              child: ListTile(
                leading: Icon(Icons.person_add_alt_1_outlined),
                title: Text('Adicionar atleta'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'logout',
              child: ListTile(
                leading: Icon(Icons.logout),
                title: Text('Sair'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ];
    }

    return [
      FilledButton.tonalIcon(
        onPressed: _addAthlete,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Adicionar atleta'),
      ),
      const SizedBox(width: 8),
      FilledButton.tonalIcon(
        onPressed: _isSyncing ? null : _syncFromWtt,
        icon: _isSyncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_download_outlined),
        label: const Text('Atualizar'),
      ),
      IconButton(
        tooltip: 'Sair',
        onPressed: () async {
          await _auth.signOut();
        },
        icon: const Icon(Icons.logout),
      ),
      const SizedBox(width: 4),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/tm_val_logo.png',
              width: 32,
              height: 32,
            ),
            const SizedBox(width: 10),
            const Text('TM Val'),
          ],
        ),
        actions: _buildAppBarActions(compact),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Masculino'),
            Tab(text: 'Feminino'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 16,
                12,
                compact ? 12 : 16,
                4,
              ),
              child: SearchBar(
                controller: _searchController,
                hintText: 'Buscar atleta...',
                leading: const Icon(Icons.search),
                trailing: _searchQuery.isEmpty
                    ? null
                    : [
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _searchController.clear,
                        ),
                      ],
              ),
            ),
            _buildBroadcastNotesCard(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Erro ao carregar atletas',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _loadAthletes,
                                  child: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildAthleteList(_maleAthletes),
                            _buildAthleteList(_femaleAthletes),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
