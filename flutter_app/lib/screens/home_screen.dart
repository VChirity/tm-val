import 'package:flutter/material.dart';

import '../models/athlete.dart';
import '../services/athlete_repository.dart';
import '../services/app_auth_service.dart';
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
  final _auth = AppAuthService();
  final _searchController = TextEditingController();

  late final TabController _tabController;

  List<Athlete> _maleAthletes = [];
  List<Athlete> _femaleAthletes = [];
  bool _isLoading = true;
  bool _isSyncing = false;
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ranking semana ${result.rankingWeek ?? "?"} de '
            '${result.rankingYear ?? "?"} — '
            '${result.athletesSynced} atletas atualizados.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhuma novidade no site da WTT. Dados já estão em dia.'),
        ),
      );
    }
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
      return Center(
        child: Text(
          _searchQuery.isEmpty
              ? 'Nenhum atleta encontrado. Toque em "Atualizar" para buscar da WTT.'
              : 'Nenhum resultado para "$_searchQuery".',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAthletes,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TM Val'),
        actions: [
          Tooltip(
            message: 'Buscar novidades no site da WTT',
            child: FilledButton.tonalIcon(
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
          ),
          IconButton(
            tooltip: 'Sair',
            onPressed: () async {
              await _auth.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Masculino'),
            Tab(text: 'Feminino'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Buscar atleta por nome...',
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
    );
  }
}
