import 'package:flutter/material.dart';

import '../models/tag_model.dart';
import '../services/api_service.dart';

class TagsScreen extends StatefulWidget {
  const TagsScreen({super.key});

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends State<TagsScreen> {
  List<ResultTagItem> _tags = <ResultTagItem>[];
  bool _loading = true;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final tags = await ApiService.instance.fetchTags();
    if (!mounted) return;
    tags.sort((a, b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      return b.id.compareTo(a.id);
    });
    setState(() {
      _tags = tags;
      _loading = false;
    });
  }

  Future<void> _respond(ResultTagItem tag, String action) async {
    setState(() => _busyId = tag.id);
    final ok = await ApiService.instance.respondTag(tag.id, action);
    if (!mounted) return;
    setState(() => _busyId = null);
    if (ok) {
      _snack(action == 'approved' ? 'تمت الموافقة على التاك.' : 'تم رفض التاك.');
      await _load();
    } else {
      _snack('تعذر تنفيذ الإجراء. تحقق من الاتصال.', isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFB91C1C) : const Color(0xFF0F766E),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        title: const Text('التاكات'),
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
          : _tags.isEmpty
              ? _empty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
                    itemCount: _tags.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => _card(_tags[index]),
                  ),
                ),
    );
  }

  Widget _empty() {
    final missingName = ApiService.instance.operatorName.trim().isEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.alternate_email_rounded,
                size: 46, color: Color(0xFF94A3B8)),
            const SizedBox(height: 10),
            Text(
              missingName
                  ? 'اضبط «اسم المندوب / المستخدم» في الإعدادات ليطابق اسمك في النظام حتى تصلك التاكات.'
                  : 'لا توجد تاكات موجهة إليك.',
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

  Widget _card(ResultTagItem tag) {
    final pending = tag.isPending;
    final color = pending
        ? const Color(0xFFB45309)
        : (tag.status == 'approved'
            ? const Color(0xFF0F766E)
            : const Color(0xFFB91C1C));
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: pending ? const Color(0xFFFDE68A) : const Color(0xFFE5ECEA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.alternate_email_rounded, size: 19, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  tag.patient.isEmpty ? 'مريض' : tag.patient,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  pending
                      ? 'بانتظارك'
                      : (tag.status == 'approved' ? 'تمت الموافقة' : 'مرفوض'),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${tag.testName.isEmpty ? tag.testCode : tag.testName}: '
            '${tag.value} ${tag.flag.isNotEmpty ? '(${tag.flag})' : ''}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'من: ${tag.fromName.isEmpty ? tag.fromUsername : tag.fromName}',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          ),
          if (tag.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              'ملاحظة: ${tag.note}',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
            ),
          ],
          if (!pending && tag.responseNote.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              'رد: ${tag.responseNote}',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
            ),
          ],
          if (pending) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busyId == tag.id
                        ? null
                        : () => _respond(tag, 'approved'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      minimumSize: const Size(0, 38),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text('موافقة'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busyId == tag.id
                        ? null
                        : () => _respond(tag, 'rejected'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                      minimumSize: const Size(0, 38),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 17),
                    label: const Text('رفض'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
