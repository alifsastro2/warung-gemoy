import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  List<Map<String, dynamic>> _broadcasts = [];
  Set<String> _readIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBroadcasts();
  }

  Future<void> _loadBroadcasts() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser!;

      final broadcasts = await Supabase.instance.client
          .from('broadcast_messages')
          .select()
          .order('created_at', ascending: false);

      final reads = await Supabase.instance.client
          .from('broadcast_reads')
          .select('broadcast_id')
          .eq('user_id', user.id);

      setState(() {
        _broadcasts = List<Map<String, dynamic>>.from(broadcasts);
        _readIds = Set<String>.from(
          (reads as List).map((r) => r['broadcast_id'] as String),
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(String broadcastId) async {
    if (_readIds.contains(broadcastId)) return;

    try {
      final user = Supabase.instance.client.auth.currentUser!;
      await Supabase.instance.client.from('broadcast_reads').insert({
        'user_id': user.id,
        'broadcast_id': broadcastId,
      });
      setState(() => _readIds.add(broadcastId));
    } catch (e) {
      // ignore duplicate
    }
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return '-';
    final date = DateTime.parse(dateStr).toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F0),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: const Text(
          'Pengumuman',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _broadcasts.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined,
                size: 60, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'Belum ada pengumuman',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadBroadcasts,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _broadcasts.length,
          itemBuilder: (context, index) {
            final broadcast = _broadcasts[index];
            final isRead = _readIds.contains(broadcast['id']);

            return GestureDetector(
              onTap: () => _markAsRead(broadcast['id']),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isRead ? Colors.white : Colors.orange.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isRead
                        ? Colors.transparent
                        : Colors.orange.withOpacity(0.3),
                    width: isRead ? 0 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isRead
                            ? Colors.grey.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.campaign,
                        color: isRead ? Colors.grey : Colors.orange,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  broadcast['title'],
                                  style: TextStyle(
                                    fontWeight: isRead
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                    fontSize: 15,
                                    color: isRead
                                        ? Colors.black54
                                        : Colors.black,
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            broadcast['body'],
                            style: TextStyle(
                              color: isRead
                                  ? Colors.grey
                                  : Colors.black87,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatDateTime(broadcast['created_at']),
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 11,
                            ),
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
    );
  }
}