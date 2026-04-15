import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item_model.dart';
import '../models/menu_model.dart';

class CartProvider extends ChangeNotifier {
  final List<CartItemModel> _items = [];
  static const _key = 'cart_items';

  CartProvider() {
    _loadFromPrefs();
  }

  List<CartItemModel> get items => _items;

  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);

  int get totalPrice => _items.fold(0, (sum, item) => sum + item.subtotal);

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final List decoded = jsonDecode(raw);
      _items.addAll(decoded.map((e) => CartItemModel.fromJson(e)));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_items.map((e) => e.toJson()).toList());
      await prefs.setString(_key, encoded);
    } catch (_) {}
  }

  void addItem(MenuModel menu) {
    final index = _items.indexWhere((item) => item.menu.id == menu.id);
    if (index >= 0) {
      _items[index].quantity++;
    } else {
      _items.add(CartItemModel(menu: menu));
    }
    notifyListeners();
    _saveToPrefs();
  }

  void setQuantity(String menuId, int quantity) {
    final index = _items.indexWhere((item) => item.menu.id == menuId);
    if (index >= 0) {
      if (quantity <= 0) {
        _items.removeAt(index);
      } else {
        _items[index].quantity = quantity;
      }
      notifyListeners();
      _saveToPrefs();
    }
  }

  void updateNotes(String menuId, String notes) {
    final index = _items.indexWhere((item) => item.menu.id == menuId);
    if (index >= 0) {
      _items[index].notes = notes;
      notifyListeners();
      _saveToPrefs();
    }
  }

  void removeItem(String menuId) {
    _items.removeWhere((item) => item.menu.id == menuId);
    notifyListeners();
    _saveToPrefs();
  }

  void decreaseItem(String menuId) {
    final index = _items.indexWhere((item) => item.menu.id == menuId);
    if (index >= 0) {
      if (_items[index].quantity > 1) {
        _items[index].quantity--;
      } else {
        _items.removeAt(index);
      }
      notifyListeners();
      _saveToPrefs();
    }
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
    _saveToPrefs();
  }

  bool hasItem(String menuId) {
    return _items.any((item) => item.menu.id == menuId);
  }

  int getQuantity(String menuId) {
    final index = _items.indexWhere((item) => item.menu.id == menuId);
    return index >= 0 ? _items[index].quantity : 0;
  }
}
