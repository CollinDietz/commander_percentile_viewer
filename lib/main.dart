import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const CommanderGridPage(),
    );
  }
}

class CommanderGridPage extends StatefulWidget {
  const CommanderGridPage({super.key});

  @override
  State<CommanderGridPage> createState() => _CommanderGridPageState();
}

class _CommanderGridPageState extends State<CommanderGridPage> {
  List<Map<String, dynamic>> _allItems = [];
  bool _loading = true;
  RangeValues _deckRange = const RangeValues(1, 45964);
  double _maxDecks = 45964;
  double _minDecks = 1;

  @override
  void initState() {
    super.initState();
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

  List<Map<String, dynamic>> get _filteredItems {
    return _allItems.where((item) {
      final numDecks =
          (item['edhrecEntry']?['numDecks'] as num?)?.toDouble() ?? 0;
      return numDecks >= _deckRange.start && numDecks <= _deckRange.end;
    }).toList();
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
      appBar: AppBar(
        title: const Text('Commander Percentile Viewer'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Text(
                  'Filter by Number of Decks: '
                  '${_deckRange.start.round()} – ${_deckRange.end.round()}'
                  '  (${filtered.length} commanders)',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                RangeSlider(
                  values: _deckRange,
                  min: _minDecks,
                  max: _maxDecks,
                  divisions: 100,
                  labels: RangeLabels(
                    _deckRange.start.round().toString(),
                    _deckRange.end.round().toString(),
                  ),
                  onChanged: (values) => setState(() => _deckRange = values),
                ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
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
                          child: Column(
                            children: [
                              Text(
                                name,
                                style: Theme.of(context).textTheme.titleSmall,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$numDecks decks',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
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

  void _showDetailModal(BuildContext context, Map<String, dynamic> item) {
    final card = item['card'] as Map<String, dynamic>? ?? {};
    final edhrecEntry = item['edhrecEntry'] as Map<String, dynamic>? ?? {};
    final imageUrl = _getImageUrl(item);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
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
                  if (imageUrl != null)
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          imageUrl,
                          height: 350,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    card['name'] ?? 'Unknown',
                    style: Theme.of(context).textTheme.headlineSmall,
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
                    _detailRow('P/T', '${card['power']}/${card['toughness']}'),
                  if (card['colors'] != null)
                    _detailRow('Colors', (card['colors'] as List).join(', ')),
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
                    _detailRow('EDHREC Rank', card['edhrec_rank'].toString()),
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
