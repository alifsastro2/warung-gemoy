class MenuModel {
  final String id;
  final String name;
  final String? description;
  final int price;
  final String? imageUrl;
  final bool isAvailable;
  final String? categoryId;
  final String? categoryName;
  final int categorySortOrder;

  MenuModel({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    this.imageUrl,
    required this.isAvailable,
    this.categoryId,
    this.categoryName,
    this.categorySortOrder = 999,
  });

  factory MenuModel.fromJson(Map<String, dynamic> json) {
    final category = json['menu_categories'] as Map<String, dynamic>?;
    return MenuModel(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      price: json['price'],
      imageUrl: json['image_url'],
      isAvailable: json['is_available'] ?? true,
      categoryId: json['category_id'] as String?,
      categoryName: category?['name'] as String?,
      categorySortOrder: category?['sort_order'] as int? ?? 999,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'price': price,
    'image_url': imageUrl,
    'is_available': isAvailable,
    'category_id': categoryId,
  };
}
