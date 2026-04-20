import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'favorites_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final favoritesService = await FavoritesService.create();
  runApp(MyApp(favoritesService: favoritesService));
}

class MyApp extends StatelessWidget {
  final FavoritesService favoritesService;
  const MyApp({super.key, required this.favoritesService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Commander Percentile Viewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
      ),
      home: CommanderGridPage(favoritesService: favoritesService),
    );
  }
}

class CommanderGridPage extends StatefulWidget {
  final FavoritesService favoritesService;
  const CommanderGridPage({super.key, required this.favoritesService});

  @override
  State<CommanderGridPage> createState() => _CommanderGridPageState();
}

class _CommanderGridPageState extends State<CommanderGridPage> {
  List<Map<String, dynamic>> _allItems = [];
  bool _loading = true;
  // Filter state
  RangeValues _deckRange = const RangeValues(1, 45964);
  double _maxDecks = 45964;
  double _minDecks = 1;
  RangeValues _cmcRange = const RangeValues(0, 13);
  Set<String> _selectedColorIdentity = {};
  bool _colorIdentityExact = false;
  Set<String> _selectedRarities = {};
  Set<String> _selectedTypes = {};
  Set<String> _selectedLayouts = {};
  Set<String> _selectedSets = {};
  Set<String> _selectedKeywords = {};
  String? _selectedFormat;
  String _nameSearch = '';
  Set<int> _selectedPercentiles = {};
  bool _showFavoritesOnly = false;
  Set<String> _favoriteIds = {};

  // Available options (populated from data)
  Set<String> _allSets = {};
  List<String> _allKeywords = [];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _favoriteIds = widget.favoritesService.getFavorites();
    _loadData();
  }

  Future<void> _loadData() async {
    final jsonString = await rootBundle.loadString('combinedJson.json');
    final List<dynamic> decoded = json.decode(jsonString);
    final items = decoded.cast<Map<String, dynamic>>();
    final nums = items
        .map((e) => (e['edhrecEntry']?['numDecks'] as num?)?.toDouble() ?? 0)
        .toList();
    final minD = nums.reduce((a, b) => a < b ? a : b);
    final maxD = nums.reduce((a, b) => a > b ? a : b);
    setState(() {
      _allItems = items;
      _minDecks = minD;
      _maxDecks = maxD;
      _deckRange = RangeValues(minD, maxD);

      // Collect available sets and keywords
      final sets = <String>{};
      final kws = <String>{};
      for (final item in items) {
        final c = item['card'] as Map<String, dynamic>? ?? {};
        final setName = c['set_name'] as String?;
        if (setName != null) sets.add(setName);
        final keywords = c['keywords'] as List<dynamic>?;
        if (keywords != null) {
          for (final kw in keywords) {
            kws.add(kw as String);
          }
        }
      }
      _allSets = sets;
      _allKeywords = kws.toList()..sort();

      _loading = false;
    });
  }

  String? _getImageUrl(Map<String, dynamic> item) {
    final card = item['card'] as Map<String, dynamic>?;
    if (card == null) return null;
    final imageUris = card['image_uris'] as Map<String, dynamic>?;
    if (imageUris != null) return imageUris['normal'] as String?;
    final faces = card['card_faces'] as List<dynamic>?;
    if (faces != null && faces.isNotEmpty) {
      final faceUris =
          (faces[0] as Map<String, dynamic>)['image_uris']
              as Map<String, dynamic>?;
      return faceUris?['normal'] as String?;
    }
    return null;
  }

  String? _getLargeImageUrl(Map<String, dynamic> item) {
    final card = item['card'] as Map<String, dynamic>?;
    if (card == null) return null;
    final imageUris = card['image_uris'] as Map<String, dynamic>?;
    if (imageUris != null) return imageUris['large'] as String?;
    final faces = card['card_faces'] as List<dynamic>?;
    if (faces != null && faces.isNotEmpty) {
      final faceUris =
          (faces[0] as Map<String, dynamic>)['image_uris']
              as Map<String, dynamic>?;
      return faceUris?['large'] as String?;
    }
    return null;
  }

  List<Map<String, dynamic>> _filterItems({
    bool excludeDeckRange = false,
    bool excludeCmc = false,
    bool excludePercentiles = false,
  }) {
    // Pre-compute percentile thresholds if needed
    List<double>? sortedNums;
    if (!excludePercentiles && _selectedPercentiles.isNotEmpty) {
      final baseItems = _filterItems(
        excludeDeckRange: true,
        excludePercentiles: true,
      );
      sortedNums =
          baseItems
              .map(
                (e) => (e['edhrecEntry']?['numDecks'] as num?)?.toDouble() ?? 0,
              )
              .toList()
            ..sort();
    }

    return _allItems.where((item) {
      final card = item['card'] as Map<String, dynamic>? ?? {};
      final numDecks =
          (item['edhrecEntry']?['numDecks'] as num?)?.toDouble() ?? 0;

      if (!excludeDeckRange) {
        if (numDecks < _deckRange.start || numDecks > _deckRange.end) {
          return false;
        }
      }

      // Percentile filter
      if (!excludePercentiles &&
          _selectedPercentiles.isNotEmpty &&
          sortedNums != null &&
          sortedNums.isNotEmpty) {
        bool inAnyBucket = false;
        for (final p in _selectedPercentiles) {
          final low = _computePercentile(sortedNums, p);
          final high = p + 10 <= 100
              ? _computePercentile(sortedNums, p + 10)
              : sortedNums.last;
          if (numDecks >= low && numDecks <= high) {
            inAnyBucket = true;
            break;
          }
        }
        if (!inAnyBucket) return false;
      }

      if (!excludeCmc) {
        final cmc = (card['cmc'] as num?)?.toDouble() ?? 0;
        if (cmc < _cmcRange.start || cmc > _cmcRange.end) return false;
      }

      // Name search
      if (_nameSearch.isNotEmpty) {
        final name = (card['name'] as String? ?? '').toLowerCase();
        if (!name.contains(_nameSearch.toLowerCase())) return false;
      }

      // Color identity filter
      if (_selectedColorIdentity.isNotEmpty) {
        final ci =
            (card['color_identity'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toSet() ??
            <String>{};
        if (_colorIdentityExact) {
          if (!ci.containsAll(_selectedColorIdentity) ||
              !_selectedColorIdentity.containsAll(ci)) {
            return false;
          }
        } else {
          if (!ci.containsAll(_selectedColorIdentity)) return false;
        }
      }

      // Rarity filter
      if (_selectedRarities.isNotEmpty) {
        final rarity = card['rarity'] as String? ?? '';
        if (!_selectedRarities.contains(rarity)) return false;
      }

      // Card type filter
      if (_selectedTypes.isNotEmpty) {
        final typeLine = card['type_line'] as String? ?? '';
        final hasMatch = _selectedTypes.any((t) => typeLine.contains(t));
        if (!hasMatch) return false;
      }

      // Layout filter
      if (_selectedLayouts.isNotEmpty) {
        final layout = card['layout'] as String? ?? '';
        if (!_selectedLayouts.contains(layout)) return false;
      }

      // Set filter
      if (_selectedSets.isNotEmpty) {
        final setName = card['set_name'] as String? ?? '';
        if (!_selectedSets.contains(setName)) return false;
      }

      // Keywords filter
      if (_selectedKeywords.isNotEmpty) {
        final kws =
            (card['keywords'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toSet() ??
            <String>{};
        if (!kws.containsAll(_selectedKeywords)) return false;
      }

      // Format legality filter
      if (_selectedFormat != null) {
        final legalities = card['legalities'] as Map<String, dynamic>? ?? {};
        if (legalities[_selectedFormat] != 'legal') return false;
      }

      // Favorites filter
      if (_showFavoritesOnly) {
        final cardId = card['id'] as String? ?? '';
        if (!_favoriteIds.contains(cardId)) return false;
      }

      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredItems => _filterItems();

  Future<void> _toggleFavorite(String cardId) async {
    await widget.favoritesService.toggleFavorite(cardId);
    setState(() {
      _favoriteIds = widget.favoritesService.getFavorites();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Commander Percentile Viewer')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final filtered = _filteredItems;

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _buildFilterDrawer(context),
      appBar: AppBar(
        title: const Text('Commander Percentile Viewer'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filters',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '${filtered.length} commanders shown',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 400,
                childAspectRatio: 0.6,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                final name = item['card']?['name'] ?? 'Unknown';
                final numDecks = item['edhrecEntry']?['numDecks'] ?? 0;
                final imageUrl = _getImageUrl(item);
                final cardId = item['card']?['id'] as String? ?? '';
                final isFav = _favoriteIds.contains(cardId);

                return GestureDetector(
                  onTap: () => _showDetailModal(context, item),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        Expanded(
                          child: imageUrl != null
                              ? Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.broken_image, size: 48),
                                  ),
                                )
                              : const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 48,
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleSmall,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$numDecks decks',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.fitHeight,
                                  child: Icon(
                                    isFav
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: isFav ? null : Colors.transparent,
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
              },
            ),
          ),
        ],
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _deckRange = RangeValues(_minDecks, _maxDecks);
      _cmcRange = const RangeValues(0, 13);
      _selectedColorIdentity = {};
      _colorIdentityExact = false;
      _selectedRarities = {};
      _selectedTypes = {};
      _selectedLayouts = {};
      _selectedSets = {};
      _selectedKeywords = {};
      _selectedFormat = null;
      _nameSearch = '';
      _selectedPercentiles = {};
      _showFavoritesOnly = false;
    });
  }

  double _computePercentile(List<double> sortedValues, int percentile) {
    if (sortedValues.isEmpty) return 0;
    final index = ((percentile / 100) * (sortedValues.length - 1)).round();
    return sortedValues[index];
  }

  Widget _buildFilterDrawer(BuildContext context) {
    const colorLabels = {
      'W': 'White',
      'U': 'Blue',
      'B': 'Black',
      'R': 'Red',
      'G': 'Green',
    };
    const rarities = ['common', 'uncommon', 'rare', 'mythic', 'special'];
    const cardTypes = [
      'Creature',
      'Planeswalker',
      'Enchantment',
      'Artifact',
      'Land',
    ];
    const layouts = [
      'normal',
      'transform',
      'modal_dfc',
      'adventure',
      'flip',
      'meld',
      'mutate',
    ];
    const formats = [
      'commander',
      'legacy',
      'vintage',
      'modern',
      'pioneer',
      'standard',
      'pauper',
      'oathbreaker',
      'duel',
      'brawl',
      'historic',
      'timeless',
    ];

    return Drawer(
      width: 340,
      child: StatefulBuilder(
        builder: (context, setDrawerState) {
          // Compute dynamic ranges from items filtered by other criteria
          final itemsForDeckRange = _filterItems(excludeDeckRange: true);
          final deckNums = itemsForDeckRange
              .map(
                (e) => (e['edhrecEntry']?['numDecks'] as num?)?.toDouble() ?? 0,
              )
              .toList();
          final dynDeckMin = deckNums.isEmpty
              ? _minDecks
              : deckNums.reduce((a, b) => a < b ? a : b);
          final dynDeckMax = deckNums.isEmpty
              ? _maxDecks
              : deckNums.reduce((a, b) => a > b ? a : b);

          final itemsForCmc = _filterItems(excludeCmc: true);
          final cmcNums = itemsForCmc
              .map(
                (e) =>
                    ((e['card'] as Map<String, dynamic>?)?['cmc'] as num?)
                        ?.toDouble() ??
                    0,
              )
              .toList();
          final dynCmcMin = cmcNums.isEmpty
              ? 0.0
              : cmcNums.reduce((a, b) => a < b ? a : b);
          final dynCmcMax = cmcNums.isEmpty
              ? 13.0
              : cmcNums.reduce((a, b) => a > b ? a : b);

          // Clamp current range values to dynamic bounds
          final clampedDeckRange = RangeValues(
            _deckRange.start.clamp(dynDeckMin, dynDeckMax),
            _deckRange.end.clamp(dynDeckMin, dynDeckMax),
          );
          final clampedCmcRange = RangeValues(
            _cmcRange.start.clamp(dynCmcMin, dynCmcMax),
            _cmcRange.end.clamp(dynCmcMin, dynCmcMax),
          );

          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Filters',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          _resetFilters();
                          setDrawerState(() {});
                        },
                        child: const Text('Reset All'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Favorites filter
                      SwitchListTile(
                        title: const Text('Favorites Only'),
                        secondary: const Icon(Icons.favorite),
                        value: _showFavoritesOnly,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) {
                          setState(() => _showFavoritesOnly = v);
                          setDrawerState(() {});
                        },
                      ),
                      const SizedBox(height: 8),

                      // Name search
                      Text(
                        'Name Search',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search by name...',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        controller: TextEditingController(text: _nameSearch),
                        onChanged: (val) {
                          _nameSearch = val;
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 16),

                      // Percentile buttons
                      Text(
                        'Percentile by Deck Count',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (int p = 0; p <= 90; p += 10)
                            FilterChip(
                              label: Text('${p}th'),
                              selected: _selectedPercentiles.contains(p),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedPercentiles.add(p);
                                  } else {
                                    _selectedPercentiles.remove(p);
                                  }
                                  _deckRange = RangeValues(
                                    dynDeckMin,
                                    dynDeckMax,
                                  );
                                });
                                setDrawerState(() {});
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Num Decks range
                      Text(
                        'Number of Decks',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${clampedDeckRange.start.round()} – ${clampedDeckRange.end.round()}'
                        '  (range: ${dynDeckMin.round()} – ${dynDeckMax.round()})',
                      ),
                      RangeSlider(
                        values: clampedDeckRange,
                        min: dynDeckMin,
                        max: dynDeckMax == dynDeckMin
                            ? dynDeckMin + 1
                            : dynDeckMax,
                        divisions: 100,
                        labels: RangeLabels(
                          clampedDeckRange.start.round().toString(),
                          clampedDeckRange.end.round().toString(),
                        ),
                        onChanged: (v) {
                          setState(() {
                            _deckRange = v;
                            _selectedPercentiles = {};
                          });
                          setDrawerState(() {});
                        },
                      ),
                      const SizedBox(height: 16),

                      // CMC range
                      Text(
                        'Mana Value (CMC)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${clampedCmcRange.start.round()} – ${clampedCmcRange.end.round()}'
                        '  (range: ${dynCmcMin.round()} – ${dynCmcMax.round()})',
                      ),
                      RangeSlider(
                        values: clampedCmcRange,
                        min: dynCmcMin,
                        max: dynCmcMax == dynCmcMin ? dynCmcMin + 1 : dynCmcMax,
                        divisions: (dynCmcMax - dynCmcMin).round().clamp(
                          1,
                          100,
                        ),
                        labels: RangeLabels(
                          clampedCmcRange.start.round().toString(),
                          clampedCmcRange.end.round().toString(),
                        ),
                        onChanged: (v) {
                          setState(() => _cmcRange = v);
                          setDrawerState(() {});
                        },
                      ),
                      const SizedBox(height: 16),

                      // Color Identity
                      Text(
                        'Color Identity',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Row(
                        children: [
                          const Text('Exact match'),
                          Switch(
                            value: _colorIdentityExact,
                            onChanged: (v) {
                              setState(() => _colorIdentityExact = v);
                              setDrawerState(() {});
                            },
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: colorLabels.entries.map((e) {
                          final selected = _selectedColorIdentity.contains(
                            e.key,
                          );
                          return FilterChip(
                            label: Text(e.value),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedColorIdentity.add(e.key);
                                } else {
                                  _selectedColorIdentity.remove(e.key);
                                }
                              });
                              setDrawerState(() {});
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Rarity
                      Text(
                        'Rarity',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: rarities.map((r) {
                          final selected = _selectedRarities.contains(r);
                          return FilterChip(
                            label: Text(r[0].toUpperCase() + r.substring(1)),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedRarities.add(r);
                                } else {
                                  _selectedRarities.remove(r);
                                }
                              });
                              setDrawerState(() {});
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Card Type
                      Text(
                        'Card Type',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: cardTypes.map((t) {
                          final selected = _selectedTypes.contains(t);
                          return FilterChip(
                            label: Text(t),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedTypes.add(t);
                                } else {
                                  _selectedTypes.remove(t);
                                }
                              });
                              setDrawerState(() {});
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Layout
                      Text(
                        'Layout',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: layouts.map((l) {
                          final selected = _selectedLayouts.contains(l);
                          return FilterChip(
                            label: Text(l.replaceAll('_', ' ')),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedLayouts.add(l);
                                } else {
                                  _selectedLayouts.remove(l);
                                }
                              });
                              setDrawerState(() {});
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      // Format Legality
                      Text(
                        'Legal In Format',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        value: _selectedFormat,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          hintText: 'Any format',
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Any format'),
                          ),
                          ...formats.map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(f[0].toUpperCase() + f.substring(1)),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _selectedFormat = v);
                          setDrawerState(() {});
                        },
                      ),
                      const SizedBox(height: 16),

                      // Set filter
                      Text(
                        'Set',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      _SearchableMultiSelect(
                        allOptions: _allSets.toList()..sort(),
                        selected: _selectedSets,
                        hintText: 'Search sets...',
                        onChanged: (newSet) {
                          setState(() => _selectedSets = newSet);
                          setDrawerState(() {});
                        },
                      ),
                      const SizedBox(height: 16),

                      // Keywords filter
                      Text(
                        'Keywords',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      _SearchableMultiSelect(
                        allOptions: _allKeywords,
                        selected: _selectedKeywords,
                        hintText: 'Search keywords...',
                        onChanged: (newSet) {
                          setState(() => _selectedKeywords = newSet);
                          setDrawerState(() {});
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDetailModal(BuildContext context, Map<String, dynamic> item) {
    final card = item['card'] as Map<String, dynamic>? ?? {};
    final edhrecEntry = item['edhrecEntry'] as Map<String, dynamic>? ?? {};
    final imageUrl = _getLargeImageUrl(item) ?? _getImageUrl(item);
    final cardFaces = card['card_faces'] as List<dynamic>?;
    final hasFaces = cardFaces != null && cardFaces.length >= 2;

    final cardId = card['id'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isFav = _favoriteIds.contains(cardId);
            return DraggableScrollableSheet(
              initialChildSize: 0.9,
              minChildSize: 0.5,
              maxChildSize: 1,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.grey[600],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      if (hasFaces)
                        Row(
                          children: [
                            for (final face in cardFaces)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      (face
                                              as Map<
                                                String,
                                                dynamic
                                              >)['image_uris']?['large'] ??
                                          (face)['image_uris']?['normal'] ??
                                          '',
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const Center(
                                            child: Icon(
                                              Icons.broken_image,
                                              size: 48,
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        )
                      else if (imageUrl != null)
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(imageUrl, fit: BoxFit.contain),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              card['name'] ?? 'Unknown',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isFav ? Icons.favorite : Icons.favorite_border,
                              color: isFav ? Colors.redAccent : null,
                              size: 28,
                            ),
                            onPressed: () async {
                              await _toggleFavorite(cardId);
                              setModalState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (card['type_line'] != null)
                        _detailRow('Type', card['type_line']),
                      if (card['mana_cost'] != null)
                        _detailRow('Mana Cost', card['mana_cost']),
                      if (card['cmc'] != null)
                        _detailRow('CMC', card['cmc'].toString()),
                      if (card['oracle_text'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Oracle Text',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(card['oracle_text']),
                        const SizedBox(height: 8),
                      ],
                      if (card['power'] != null && card['toughness'] != null)
                        _detailRow(
                          'P/T',
                          '${card['power']}/${card['toughness']}',
                        ),
                      if (card['colors'] != null)
                        _detailRow(
                          'Colors',
                          (card['colors'] as List).join(', '),
                        ),
                      if (card['color_identity'] != null)
                        _detailRow(
                          'Color Identity',
                          (card['color_identity'] as List).join(', '),
                        ),
                      if (card['keywords'] != null &&
                          (card['keywords'] as List).isNotEmpty)
                        _detailRow(
                          'Keywords',
                          (card['keywords'] as List).join(', '),
                        ),
                      if (card['rarity'] != null)
                        _detailRow('Rarity', card['rarity']),
                      if (card['set_name'] != null)
                        _detailRow('Set', card['set_name']),
                      if (card['artist'] != null)
                        _detailRow('Artist', card['artist']),
                      if (card['released_at'] != null)
                        _detailRow('Released', card['released_at']),
                      if (card['edhrec_rank'] != null)
                        _detailRow(
                          'EDHREC Rank',
                          card['edhrec_rank'].toString(),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'EDHREC Data',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      _detailRow(
                        'Num Decks',
                        edhrecEntry['numDecks']?.toString() ?? 'N/A',
                      ),
                      if (edhrecEntry['url'] != null)
                        _detailRow(
                          'EDHREC URL',
                          'https://edhrec.com${edhrecEntry['url']}',
                        ),
                      const SizedBox(height: 12),
                      if (card['prices'] != null) ...[
                        Text(
                          'Prices',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        ..._buildPrices(card['prices'] as Map<String, dynamic>),
                      ],
                      if (card['legalities'] != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Legalities',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: (card['legalities'] as Map<String, dynamic>)
                              .entries
                              .where((e) => e.value == 'legal')
                              .map(
                                (e) => Chip(
                                  label: Text(
                                    e.key,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  List<Widget> _buildPrices(Map<String, dynamic> prices) {
    return prices.entries
        .where((e) => e.value != null)
        .map(
          (e) => _detailRow(
            e.key.replaceAll('_', ' ').toUpperCase(),
            '\$${e.value}',
          ),
        )
        .toList();
  }
}

class _SearchableMultiSelect extends StatefulWidget {
  final List<String> allOptions;
  final Set<String> selected;
  final String hintText;
  final ValueChanged<Set<String>> onChanged;

  const _SearchableMultiSelect({
    required this.allOptions,
    required this.selected,
    required this.hintText,
    required this.onChanged,
  });

  @override
  State<_SearchableMultiSelect> createState() => _SearchableMultiSelectState();
}

class _SearchableMultiSelectState extends State<_SearchableMultiSelect> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty
        ? widget.allOptions
        : widget.allOptions
              .where((o) => o.toLowerCase().contains(_search.toLowerCase()))
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selected.isNotEmpty) ...[
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: widget.selected
                .map(
                  (s) => Chip(
                    label: Text(s, style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () {
                      final newSet = Set<String>.from(widget.selected)
                        ..remove(s);
                      widget.onChanged(newSet);
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
        ],
        TextField(
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (val) => setState(() => _search = val),
        ),
        if (_search.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final option = filtered[index];
                final isSelected = widget.selected.contains(option);
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(option, style: const TextStyle(fontSize: 13)),
                  trailing: isSelected
                      ? const Icon(Icons.check, size: 18)
                      : null,
                  onTap: () {
                    final newSet = Set<String>.from(widget.selected);
                    if (isSelected) {
                      newSet.remove(option);
                    } else {
                      newSet.add(option);
                    }
                    widget.onChanged(newSet);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
