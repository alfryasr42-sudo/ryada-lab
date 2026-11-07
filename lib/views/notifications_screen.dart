import 'package:flutter/material.dart';

import '../models/notification_model.dart';
import '../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = <AppNotification>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final items = await ApiService.instance.fetchNotifications(limit: 100);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      _error = items.isEmpty ? null : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: <Widget>[
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'تحديث',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => _tile(_items[index]),
                  ),
                ),
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.notifications_none_rounded,
                size: 46, color: Color(0xFF94A3B8)),
            const SizedBox(height: 10),
            Text(
              _error ?? 'لا توجد إشعارات سابقة.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(AppNotification item) {
    final style = _styleFor(item.kind);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, size: 20, color: style.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (item.body.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    item.body,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
                const SizedBox(height: 5),
                Text(
                  <String>[
                    if (item.username.trim().isNotEmpty) item.username,
                    _formatTime(item.createdAt),
                  ].where((part) => part.isNotEmpty).join(' • '),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _NoticeStyle _styleFor(String kind) {
    switch (kind) {
      case 'critical_result':
        return const _NoticeStyle(
            Icons.warning_amber_rounded, Color(0xFFDC2626));
      case 'critical_print':
        return const _NoticeStyle(Icons.print_rounded, Color(0xFFEA580C));
      case 'discount':
        return const _NoticeStyle(Icons.percent_rounded, Color(0xFF7C3AED));
      case 'web_open':
      case 'app_open':
        return const _NoticeStyle(Icons.login_rounded, Color(0xFF0F766E));
      case 'web_close':
      case 'app_close':
        return const _NoticeStyle(Icons.logout_rounded, Color(0xFF64748B));
      case 'tag':
        return const _NoticeStyle(
            Icons.alternate_email_rounded, Color(0xFF7C3AED));
      case 'tag_response':
        return const _NoticeStyle(Icons.reply_rounded, Color(0xFF0F766E));
      case 'forbidden':
        return const _NoticeStyle(Icons.block_rounded, Color(0xFFB91C1C));
      case 'bridge_up':
        return const _NoticeStyle(Icons.cloud_done_rounded, Color(0xFF0EA5E9));
      case 'bridge_down':
        return const _NoticeStyle(Icons.cloud_off_rounded, Color(0xFFDC2626));
      case 'update':
        return const _NoticeStyle(
            Icons.system_update_rounded, Color(0xFF2563EB));
      default:
        return const _NoticeStyle(
            Icons.notifications_rounded, Color(0xFF0F766E));
    }
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final text = local.toString();
    return text.length >= 16 ? text.substring(0, 16) : text;
  }
}

class _NoticeStyle {
  final IconData icon;
  final Color color;

  const _NoticeStyle(this.icon, this.color);
}
