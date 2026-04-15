import 'menu_model.dart';

class CartItemModel {
  final MenuModel menu;
  int quantity;
  String notes;

  CartItemModel({
    required this.menu,
    this.quantity = 1,
    this.notes = '',
  });

  int get subtotal => menu.price * quantity;

  Map<String, dynamic> toJson() => {
    'menu': menu.toJson(),
    'quantity': quantity,
    'notes': notes,
  };

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    return CartItemModel(
      menu: MenuModel.fromJson(json['menu']),
      quantity: json['quantity'] ?? 1,
      notes: json['notes'] ?? '',
    );
  }
}