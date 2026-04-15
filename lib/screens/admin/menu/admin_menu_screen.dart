import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminMenuScreen extends StatefulWidget {
  const AdminMenuScreen({super.key});

  @override
  State<AdminMenuScreen> createState() => _AdminMenuScreenState();
}

class _AdminMenuScreenState extends State<AdminMenuScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _menus = [];
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([_loadMenus(), _loadCategories()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadMenus() async {
    try {
      final response = await Supabase.instance.client
          .from('menus')
          .select('*, menu_categories(id, name, sort_order)')
          .order('created_at', ascending: false);
      if (mounted) setState(() => _menus = List<Map<String, dynamic>>.from(response));
    } catch (_) {}
  }

  Future<void> _loadCategories() async {
    try {
      final response = await Supabase.instance.client
          .from('menu_categories')
          .select()
          .order('sort_order', ascending: true);
      if (mounted) setState(() => _categories = List<Map<String, dynamic>>.from(response));
    } catch (_) {}
  }

  String _formatPrice(int price) {
    return 'Rp ${price.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    )}';
  }

  // ── Kategori dialogs ────────────────────────────────────────

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Kategori'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nama Kategori',
            hintText: 'Contoh: Makanan, Minuman',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              final maxOrder = _categories.isEmpty
                  ? 0
                  : _categories.map((c) => (c['sort_order'] as int? ?? 0)).reduce((a, b) => a > b ? a : b) + 1;
              await Supabase.instance.client.from('menu_categories').insert({
                'name': nameController.text.trim(),
                'sort_order': maxOrder,
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _loadAll();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Tambah', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(Map<String, dynamic> category) {
    final nameController = TextEditingController(text: category['name']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Kategori'),
        content: TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Nama Kategori',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx2) => AlertDialog(
                  title: const Text('Hapus Kategori?'),
                  content: Text(
                    'Hapus "${category['name']}"? Menu di kategori ini akan jadi tanpa kategori.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx2, false), child: const Text('Batal')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx2, true),
                      child: const Text('Hapus', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await Supabase.instance.client
                    .from('menu_categories')
                    .delete()
                    .eq('id', category['id']);
                _loadAll();
              }
            },
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              await Supabase.instance.client
                  .from('menu_categories')
                  .update({'name': nameController.text.trim()})
                  .eq('id', category['id']);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadAll();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showReorderCategories() {
    List<Map<String, dynamic>> tempCategories = List.from(_categories);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          bool isSaving = false;
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text('Atur Urutan Kategori',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ReorderableListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (int i = 0; i < tempCategories.length; i++)
                        ListTile(
                          key: ValueKey(tempCategories[i]['id']),
                          leading: const Icon(Icons.drag_handle, color: Colors.grey),
                          title: Text(tempCategories[i]['name']),
                          trailing: Text(
                            '${i + 1}',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ),
                    ],
                    onReorder: (oldIndex, newIndex) {
                      setModalState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = tempCategories.removeAt(oldIndex);
                        tempCategories.insert(newIndex, item);
                      });
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              setModalState(() => isSaving = true);
                              final newOrder = List<Map<String, dynamic>>.from(tempCategories);
                              try {
                                for (int i = 0; i < newOrder.length; i++) {
                                  await Supabase.instance.client
                                      .from('menu_categories')
                                      .update({'sort_order': i})
                                      .eq('id', newOrder[i]['id'])
                                      .select();
                                }
                                // Reload dari DB untuk konfirmasi tersimpan
                                await _loadCategories();
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              } catch (e) {
                                setModalState(() => isSaving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Gagal simpan urutan: $e')),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: isSaving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Simpan Urutan',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Menu form ────────────────────────────────────────────────

  void _showMenuForm({Map<String, dynamic>? menu}) {
    final nameController = TextEditingController(text: menu?['name'] ?? '');
    final descController = TextEditingController(text: menu?['description'] ?? '');
    final priceController = TextEditingController(text: menu?['price']?.toString() ?? '');
    bool isAvailable = menu?['is_available'] ?? true;
    bool isLoading = false;
    File? imageFile;
    String? existingImageUrl = menu?['image_url'];
    String? selectedCategoryId = menu?['category_id'] ??
        (_categories.isNotEmpty ? _categories.first['id'] as String : null);

    Future<File?> pickAndCropImage() async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return null;
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Foto Menu',
            toolbarColor: Colors.orange,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: true,
          ),
        ],
      );
      if (cropped == null) return null;
      return File(cropped.path);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  menu == null ? 'Tambah Menu Baru' : 'Edit Menu',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Upload Foto
                GestureDetector(
                  onTap: () async {
                    final file = await pickAndCropImage();
                    if (file != null) setModalState(() => imageFile = file);
                  },
                  child: Container(
                    width: double.infinity, height: 150,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: imageFile != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(imageFile!, fit: BoxFit.cover),
                          )
                        : existingImageUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  existingImageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (ctx, err, stack) =>
                                      const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined,
                                      size: 40, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text('Tap untuk upload foto (opsional)',
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                                ],
                              ),
                  ),
                ),

                if (existingImageUrl != null && imageFile == null) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => setModalState(() => existingImageUrl = null),
                    child: const Text('Hapus foto', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ],

                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Nama Menu',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Deskripsi (opsional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Harga (Rp)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),

                // Dropdown Kategori
                if (_categories.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Buat kategori dulu sebelum menambah menu',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<String?>(
                    value: selectedCategoryId,
                    decoration: InputDecoration(
                      labelText: 'Kategori',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _categories.map((cat) => DropdownMenuItem<String?>(
                      value: cat['id'] as String,
                      child: Text(cat['name']),
                    )).toList(),
                    onChanged: (val) => setModalState(() => selectedCategoryId = val),
                  ),

                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tersedia untuk dipesan'),
                    Switch(
                      value: isAvailable,
                      activeColor: Colors.orange,
                      onChanged: (val) => setModalState(() => isAvailable = val),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLoading
                        ? null
                        : () async {
                            if (nameController.text.trim().isEmpty ||
                                priceController.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Nama dan harga wajib diisi!')),
                              );
                              return;
                            }
                            if (_categories.isNotEmpty && selectedCategoryId == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pilih kategori untuk menu ini!')),
                              );
                              return;
                            }
                            setModalState(() => isLoading = true);
                            try {
                              String? imageUrl = existingImageUrl;
                              if (imageFile != null) {
                                final fileName =
                                    'menu_${DateTime.now().millisecondsSinceEpoch}.jpg';
                                final bytes = await imageFile!.readAsBytes();
                                await Supabase.instance.client.storage
                                    .from('menu-images')
                                    .uploadBinary(fileName, bytes);
                                imageUrl = Supabase.instance.client.storage
                                    .from('menu-images')
                                    .getPublicUrl(fileName);
                              }
                              final data = {
                                'name': nameController.text.trim(),
                                'description': descController.text.trim(),
                                'price': int.parse(priceController.text.trim()),
                                'is_available': isAvailable,
                                'image_url': imageUrl,
                                'category_id': selectedCategoryId,
                              };
                              if (menu == null) {
                                await Supabase.instance.client.from('menus').insert(data);
                              } else {
                                await Supabase.instance.client
                                    .from('menus')
                                    .update(data)
                                    .eq('id', menu['id']);
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              _loadAll();
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Gagal simpan: ${e.toString()}')),
                                );
                              }
                            } finally {
                              setModalState(() => isLoading = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            menu == null ? 'Tambah Menu' : 'Simpan Perubahan',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteMenu(String menuId, String menuName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Menu?'),
        content: Text('Yakin ingin menghapus "$menuName"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client.from('menus').delete().eq('id', menuId);
      _loadAll();
    }
  }

  // ── Daftar Menu tab widgets ──────────────────────────────────

  Widget _buildCategoryChipsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16, color: Colors.orange),
                    label: const Text('Tambah', style: TextStyle(color: Colors.orange, fontSize: 12)),
                    backgroundColor: Colors.white,
                    side: BorderSide(color: Colors.grey.shade300),
                    onPressed: _showAddCategoryDialog,
                  ),
                  ..._categories.map((cat) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Chip(
                      label: Text(cat['name'],
                          style: const TextStyle(color: Colors.orange, fontSize: 12)),
                      backgroundColor: Colors.orange.withOpacity(0.1),
                      side: const BorderSide(color: Colors.orange),
                    ),
                  )),
                ],
              ),
            ),
          ),
          if (_categories.isNotEmpty) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              icon: const Icon(Icons.sort, size: 16),
              label: const Text('Atur Urutan', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
              onPressed: _showReorderCategories,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(Map<String, dynamic>? category) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: Container(height: 1, color: Colors.grey.shade200)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    (category?['name'] ?? 'Lainnya').toString().toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Expanded(child: Container(height: 1, color: Colors.grey.shade200)),
              ],
            ),
          ),
          if (category != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _showEditCategoryDialog(category),
              child: const Icon(Icons.edit_outlined, size: 16, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMenuCard(Map<String, dynamic> menu) {
    final isAvailable = menu['is_available'] as bool;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: !isAvailable ? Border.all(color: Colors.grey.shade300) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 50, height: 50,
          decoration: BoxDecoration(
            color: isAvailable ? Colors.orange.withOpacity(0.1) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: menu['image_url'] != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    menu['image_url'],
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) =>
                        Icon(Icons.restaurant, color: isAvailable ? Colors.orange : Colors.grey),
                  ),
                )
              : Icon(Icons.restaurant, color: isAvailable ? Colors.orange : Colors.grey),
        ),
        title: Text(
          menu['name'],
          style: TextStyle(
              fontWeight: FontWeight.bold, color: isAvailable ? Colors.black : Colors.grey),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatPrice(menu['price'] as int),
              style: TextStyle(
                  color: isAvailable ? Colors.orange : Colors.grey, fontWeight: FontWeight.bold),
            ),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isAvailable
                    ? Colors.green.withOpacity(0.1)
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isAvailable ? 'Tersedia' : 'Tidak Tersedia',
                style: TextStyle(
                  color: isAvailable ? Colors.green : Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blue),
              onPressed: () => _showMenuForm(menu: menu),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteMenu(menu['id'], menu['name']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuListGrouped() {
    // Tidak ada kategori sama sekali → flat list
    if (_categories.isEmpty) {
      if (_menus.isEmpty) {
        return const Center(
          child: Text('Belum ada menu. Tap + untuk tambah!', style: TextStyle(color: Colors.grey)),
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 80),
        children: _menus.map(_buildMenuCard).toList(),
      );
    }

    final sections = <Widget>[];

    for (final cat in _categories) {
      final catMenus = _menus.where((m) => m['category_id'] == cat['id']).toList();
      sections.add(_buildSectionHeader(cat));
      if (catMenus.isEmpty) {
        sections.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Text('Belum ada menu di kategori ini',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
        ));
      } else {
        sections.addAll(catMenus.map(_buildMenuCard));
      }
    }

    // Menu tanpa kategori
    final uncategorized = _menus.where((m) => m['category_id'] == null).toList();
    if (uncategorized.isNotEmpty) {
      sections.add(_buildSectionHeader(null));
      sections.addAll(uncategorized.map(_buildMenuCard));
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: sections,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text('Kelola Menu',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Daftar Menu'),
            Tab(text: 'Jadwal Mingguan'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              backgroundColor: Colors.orange,
              onPressed: () => _showMenuForm(),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Daftar Menu
                Column(
                  children: [
                    _buildCategoryChipsRow(),
                    const Divider(height: 1),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadAll,
                        child: _buildMenuListGrouped(),
                      ),
                    ),
                  ],
                ),

                // Tab 2: Jadwal Mingguan
                _WeeklyScheduleTab(menus: _menus),
              ],
            ),
    );
  }
}

// ── Weekly Schedule Tab (tidak berubah) ─────────────────────────

class _WeeklyScheduleTab extends StatefulWidget {
  final List<Map<String, dynamic>> menus;

  const _WeeklyScheduleTab({required this.menus});

  @override
  State<_WeeklyScheduleTab> createState() => _WeeklyScheduleTabState();
}

class _WeeklyScheduleTabState extends State<_WeeklyScheduleTab> {
  List<Map<String, dynamic>> _schedules = [];
  bool _isLoading = true;
  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());

  static DateTime _getWeekStart(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() => _isLoading = true);
    try {
      final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
      final response = await Supabase.instance.client
          .from('menu_schedules')
          .select('*, menus(name, price)')
          .gte('scheduled_date', _selectedWeekStart.toIso8601String().split('T')[0])
          .lte('scheduled_date', weekEnd.toIso8601String().split('T')[0])
          .order('scheduled_date');
      setState(() {
        _schedules = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> _getSchedulesForDate(DateTime date) {
    final dateStr = date.toIso8601String().split('T')[0];
    return _schedules.where((s) => s['scheduled_date'] == dateStr).toList();
  }

  String _getDayName(int weekday) {
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    return days[weekday - 1];
  }

  Future<void> _addSchedule(DateTime date) async {
    if (widget.menus.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada menu. Tambah menu dulu!')),
      );
      return;
    }

    // Filter menu yang sudah dijadwalkan di tanggal ini
    final scheduledMenuIds = _getSchedulesForDate(date).map((s) => s['menu_id'] as String).toSet();
    final availableMenus = widget.menus.where((m) => !scheduledMenuIds.contains(m['id'])).toList();

    if (availableMenus.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua menu sudah dijadwalkan di hari ini!')),
      );
      return;
    }

    String? selectedMenuId;
    String? selectedMenuName;
    final maxQtyController = TextEditingController(text: '50');

    // Fungsi untuk buka bottom sheet pilih menu
    Future<void> showMenuPicker(StateSetter setDialogState) async {
      final searchController = TextEditingController();
      List<Map<String, dynamic>> filtered = List.from(availableMenus);

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetCtx) => StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Cari nama menu...',
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, color: Colors.grey),
                                onPressed: () {
                                  searchController.clear();
                                  setSheetState(() => filtered = List.from(availableMenus));
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (val) {
                        setSheetState(() {
                          filtered = availableMenus
                              .where((m) => (m['name'] as String)
                                  .toLowerCase()
                                  .contains(val.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  // List menu
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('Tidak ada menu ditemukan',
                                style: TextStyle(color: Colors.grey)),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final menu = filtered[i];
                              final price = menu['price'] as int;
                              final priceStr = 'Rp ${price.toString().replaceAllMapped(
                                RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                                (m) => '${m[1]}.',
                              )}';
                              return ListTile(
                                leading: Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: menu['image_url'] != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(menu['image_url'],
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const Icon(Icons.restaurant,
                                                      color: Colors.orange, size: 18)),
                                        )
                                      : const Icon(Icons.restaurant,
                                          color: Colors.orange, size: 18),
                                ),
                                title: Text(menu['name'],
                                    style: const TextStyle(fontWeight: FontWeight.w500)),
                                subtitle: Text(priceStr,
                                    style: const TextStyle(
                                        color: Colors.orange, fontSize: 12)),
                                onTap: () {
                                  setDialogState(() {
                                    selectedMenuId = menu['id'] as String;
                                    selectedMenuName = menu['name'] as String;
                                  });
                                  Navigator.pop(sheetCtx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Jadwalkan Menu - ${_getDayName(date.weekday)} ${date.day}/${date.month}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Field pilih menu → buka bottom sheet
              GestureDetector(
                onTap: () => showMenuPicker(setDialogState),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedMenuName ?? 'Pilih Menu',
                          style: TextStyle(
                            color: selectedMenuName != null
                                ? Colors.black87
                                : Colors.grey.shade500,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxQtyController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Maks. Porsi',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                if (selectedMenuId == null) return;
                await Supabase.instance.client.from('menu_schedules').insert({
                  'menu_id': selectedMenuId,
                  'scheduled_date': date.toIso8601String().split('T')[0],
                  'max_qty': int.tryParse(maxQtyController.text) ?? 50,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _loadSchedules();
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Tambah', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSchedule(String scheduleId) async {
    await Supabase.instance.client.from('menu_schedules').delete().eq('id', scheduleId);
    _loadSchedules();
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.orange))
        : Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _selectedWeekStart.isAfter(
                              _getWeekStart(DateTime.now().subtract(const Duration(days: 90))))
                          ? () {
                              setState(() => _selectedWeekStart =
                                  _selectedWeekStart.subtract(const Duration(days: 7)));
                              _loadSchedules();
                            }
                          : null,
                    ),
                    Text(
                      '${_selectedWeekStart.day}/${_selectedWeekStart.month} - ${_selectedWeekStart.add(const Duration(days: 6)).day}/${_selectedWeekStart.add(const Duration(days: 6)).month}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () {
                        setState(() => _selectedWeekStart =
                            _selectedWeekStart.add(const Duration(days: 7)));
                        _loadSchedules();
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: 7,
                  itemBuilder: (context, index) {
                    final date = _selectedWeekStart.add(Duration(days: index));
                    final daySchedules = _getSchedulesForDate(date);
                    final today = DateTime.now();
                    final isToday = date.day == today.day &&
                        date.month == today.month &&
                        date.year == today.year;
                    final isPast = date.isBefore(DateTime(today.year, today.month, today.day));

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isPast ? Colors.grey.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: isToday ? Border.all(color: Colors.orange, width: 2) : null,
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            title: Row(
                              children: [
                                Text(
                                  _getDayName(date.weekday),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isPast
                                        ? Colors.grey
                                        : isToday
                                            ? Colors.orange
                                            : Colors.black,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('${date.day}/${date.month}',
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                                if (isToday) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.orange,
                                        borderRadius: BorderRadius.circular(20)),
                                    child: const Text('Hari Ini',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                                if (isPast) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(20)),
                                    child: Text('Lewat',
                                        style: TextStyle(
                                            color: Colors.grey.shade500,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ],
                            ),
                            trailing: isPast
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.add_circle_outline, color: Colors.orange),
                                    onPressed: () => _addSchedule(date),
                                  ),
                          ),
                          if (daySchedules.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, bottom: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 14, color: Colors.grey.shade400),
                                  const SizedBox(width: 4),
                                  Text('Belum ada menu dijadwalkan',
                                      style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                                ],
                              ),
                            )
                          else
                            ...daySchedules.map((schedule) {
                              final menu = schedule['menus'] as Map<String, dynamic>;
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(
                                    color: isPast
                                        ? Colors.grey.withOpacity(0.1)
                                        : Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.restaurant,
                                      color: isPast ? Colors.grey : Colors.orange, size: 16),
                                ),
                                title: Text(menu['name'],
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: isPast ? Colors.grey : Colors.black87)),
                                subtitle: Text('Maks. ${schedule['max_qty']} porsi',
                                    style: const TextStyle(fontSize: 11)),
                                trailing: isPast
                                    ? null
                                    : IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.red, size: 18),
                                        onPressed: () => _deleteSchedule(schedule['id']),
                                      ),
                              );
                            }),
                          const SizedBox(height: 4),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
  }
}
