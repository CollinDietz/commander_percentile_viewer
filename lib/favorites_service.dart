import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  static const _key = 'favorite_card_ids';
  final SharedPreferences _prefs;

  FavoritesService._(this._prefs);

  static Future<FavoritesService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return FavoritesService._(prefs);
  }

  Set<String> getFavorites() {
    final list = _prefs.getStringList(_key);
    return list?.toSet() ?? {};
  }

  Future<void> toggleFavorite(String cardId) async {
    final favorites = getFavorites();
    if (favorites.contains(cardId)) {
      favorites.remove(cardId);
    } else {
      favorites.add(cardId);
    }
    await _prefs.setStringList(_key, favorites.toList());
  }

  bool isFavorite(String cardId) {
    return getFavorites().contains(cardId);
  }
}
