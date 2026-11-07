import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/ai_provider.dart';
import '../models/patient_model.dart';
import '../models/result_model.dart';
import '../models/update_model.dart';
import '../services/activation_service.dart';
import '../services/api_service.dart';
import '../services/connection_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/reception_offline_service.dart';
import '../services/update_service.dart';
import '../utils/app_format.dart';
import 'critical_screen.dart';
import 'finance_screen.dart';
import 'notifications_screen.dart';
import 'reception_screen.dart';
import 'review_screen.dart';
import 'scan_screen.dart';
import 'store_screen.dart';
import 'tags_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  DateTime _date = DateTime.now();
  List<Patient> _patients = <Patient>[];
  LocalStats _stats = const LocalStats();
  bool _loading = true;
  bool _syncing = false;
  bool _sendingPending = false;
  String? _error;
  String _query = '';
  bool? _serverOnline;
  bool? _apiOnline;
  bool? _aiOnline;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await Future.wait(<Future<void>>[
        DatabaseService.instance.init(),
        ApiService.instance.init(),
      ]);
    } catch (_) {
      // قاعدة البيانات ستُعاد المحاولة عند التحميل التالي.
    }
    await _load();
    unawaited(ApiService.instance.syncBridge());
    unawaited(ReceptionOfflineService.flushPending());
    unawaited(_checkConnections());
    unawaited(_checkUpdate());
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (showSpinner && mounted) {
      setState(() => _loading = true);
    }
    try {
      final patients = await DatabaseService.instance.getPatients(date: _date);
      final stats = await DatabaseService.instance.getStats(_date);
      if (!mounted) return;
      setState(() {
        _patients = patients;
        _stats = stats;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل البيانات المحلية.';
      });
    }
  }

  Future<void> _checkConnections() async {
    final results = await Future.wait<bool>(<Future<bool>>[
      ConnectionService.server(),
      ConnectionService.api(),
      ConnectionService.ai(),
    ]);
    if (!mounted) return;
    setState(() {
      _serverOnline = results[0];
      _apiOnline = results[1];
      _aiOnline = results[2];
    });
  }

  Future<void> _checkUpdate({bool manual = false}) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (manual) {
        _snack('تحديثات iPhone تُثبّت عبر TestFlight أو App Store.');
      }
      return;
    }
    try {
      final update = await UpdateService.instance.check();
      if (!mounted) return;
      if (update == null) {
        if (manual) _snack('التطبيق محدّث بالفعل.');
        return;
      }
      if (!manual) {
        // مع FCM يصل إشعار التحديث من السيرفر حتى والتطبيق مغلق.
        if (!PushService.instance.ready) {
          unawaited(NotificationService.instance.updateAvailable(update.version));
        }
        return;
      }
      await _showUpdateDialog(update);
    } catch (error) {
      if (manual && mounted) _snack(error.toString(), isError: true);
    }
  }

  Future<void> _showUpdateDialog(MobileUpdate update) async {
    final notes = update.notes.trim();
    final size = update.sizeLabel;
    final start = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('تحديث جديد ${update.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (size.isNotEmpty)
              Text(
                'حجم الملف: $size',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            if (notes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                notes,
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'سيُغلق التطبيق مؤقتاً أثناء التثبيت.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لاحقاً'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تحديث الآن'),
          ),
        ],
      ),
    );
    if (start != true || !mounted) return;

    final progress = ValueNotifier<double>(0);
    var dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('جارٍ تنزيل التحديث'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinearProgressIndicator(value: value <= 0 ? null : value),
              const SizedBox(height: 8),
              Text('${(value * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    ).whenComplete(() => dialogOpen = false);

    String? errorMessage;
    try {
      await UpdateService.instance.downloadAndInstall(
        update,
        onProgress: (value) => progress.value = value,
      );
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
    }
    if (errorMessage != null && mounted) {
      _snack(errorMessage, isError: true);
    }
  }

  List<Patient> get _filteredPatients {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return _patients;
    return _patients.where((patient) {
      return patient.name.toLowerCase().contains(needle) ||
          patient.barcode.toLowerCase().contains(needle) ||
          patient.phone.toLowerCase().contains(needle);
    }).toList();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      locale: const Locale('ar'),
      helpText: 'اختر يوم الزيارة',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (picked == null) return;
    setState(() => _date = picked);
    await _load(showSpinner: true);
  }

  Future<void> _openTags() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TagsScreen()),
    );
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
    );
  }

  Future<void> _openSettings() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _SettingsSheet(),
    );
    if (saved == true && mounted) {
      _snack('تم حفظ إعدادات السيرفر.');
      unawaited(_checkConnections());
    }
  }

  Future<void> _openFinance() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const FinanceScreen()),
    );
  }

  Future<void> _openReception() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReceptionScreen()),
    );
  }

  Future<void> _openCritical() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CriticalScreen()),
    );
  }

  Future<void> _openStore() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const StoreScreen()),
    );
  }

  Future<void> _sync() async {
    if (!ApiService.instance.isConfigured) {
      await _openSettings();
    }
    if (!ApiService.instance.isConfigured) {
      if (mounted) _snack('اضبط عنوان السيرفر أولاً.', isError: true);
      return;
    }

    setState(() => _syncing = true);
    try {
      final remote = await ApiService.instance.fetchPatients(_date);
      final saved = await DatabaseService.instance.upsertPatients(remote);
      await _load();
      if (mounted) {
        _snack(saved == 0
            ? 'لا يوجد مرضى جدد في هذا اليوم.'
            : 'تمت مزامنة $saved مريض بنجاح.');
      }
    } catch (error) {
      if (mounted) _snack(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _sendPending() async {
    if (!ApiService.instance.isConfigured) {
      await _openSettings();
    }
    if (!ApiService.instance.isConfigured) {
      if (mounted) _snack('اضبط عنوان السيرفر أولاً.', isError: true);
      return;
    }

    setState(() => _sendingPending = true);
    try {
      final total = _stats.unsynced;
      final sent = await ApiService.instance.sendPendingResults();
      if (sent > 0) {
        unawaited(NotificationService.instance.resultsSent(sent));
      }
      await _load();
      if (mounted) {
        _snack(sent == total
            ? 'تم إرسال $sent نتيجة بنجاح.'
            : 'أُرسلت $sent من $total. الباقي محفوظ للمحاولة لاحقاً.',
            isError: sent != total);
      }
    } catch (error) {
      if (mounted) _snack(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _sendingPending = false);
    }
  }

  Future<void> _seedDemo() async {
    try {
      final count = await DatabaseService.instance.seedDemoPatients();
      await _load(showSpinner: true);
      if (mounted) {
        _snack(count == 0
            ? 'توجد بيانات لهذا اليوم بالفعل.'
            : 'تم إنشاء $count مرضى تجريبيين.');
      }
    } catch (_) {
      if (mounted) _snack('تعذر إنشاء البيانات التجريبية.', isError: true);
    }
  }

  Future<void> _openPatient(Patient patient) async {
    if (!patient.status.isFinished) {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ScanScreen(patient: patient),
        ),
      );
      if (changed == true) await _load();
      return;
    }

    final saved = await DatabaseService.instance.getResultForPatient(patient.id);
    if (!mounted) return;
    if (saved == null) {
      if (patient.status == PatientStatus.synced) {
        _snack('لا توجد نتيجة محفوظة محلياً لهذا المريض.', isError: true);
        return;
      }
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ReviewScreen(
            patient: patient,
            initialResults: const <TestResult>[],
            initialNotes: patient.notes,
          ),
        ),
      );
      if (changed == true) await _load();
      return;
    }

    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ReviewScreen(
          patient: patient,
          initialResults: saved.results,
          imagePath: saved.imagePath,
          initialNotes: saved.notes,
          readOnly: patient.status == PatientStatus.synced,
        ),
      ),
    );
    await _load();
  }

  Future<void> _startScan() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const ScanScreen()),
    );
    if (changed == true) await _load();
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFB91C1C) : const Color(0xFF0F172A),
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPatients;
    final showInitialLoader = _loading && _patients.isEmpty;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 66,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('مختبر ريادة'),
            SizedBox(height: 2),
            Text(
              'المندوب الميداني',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          if (ActivationService.instance.hasPermission('finance'))
            IconButton(
              onPressed: _openFinance,
              tooltip: 'الملخص المالي',
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
          if (ActivationService.instance.hasPermission('store'))
            IconButton(
              onPressed: _openStore,
              tooltip: 'المخزن',
              icon: const Icon(Icons.inventory_2_outlined),
            ),
          if (ActivationService.instance.hasPermission('critical'))
            IconButton(
              onPressed: _openCritical,
              tooltip: 'المرضى الحرجة',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.monitor_heart_outlined),
            ),
          if (ActivationService.instance.hasPermission('reception'))
            IconButton(
              onPressed: _openReception,
              tooltip: 'الاستقبال',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.support_agent_rounded),
            ),
          IconButton(
            onPressed: _openTags,
            tooltip: 'التاكات',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.alternate_email_rounded),
          ),
          IconButton(
            onPressed: _openNotifications,
            tooltip: 'الإشعارات',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.notifications_outlined),
          ),
          IconButton(
            onPressed: () => _checkUpdate(manual: true),
            tooltip: 'تحديث التطبيق',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.system_update_rounded),
          ),
          IconButton(
            onPressed: _openSettings,
            tooltip: 'إعدادات السيرفر',
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: showInitialLoader
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _load(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
                children: <Widget>[
                  _SyncHeader(
                    date: _date,
                    total: _stats.total,
                    syncing: _syncing,
                    onSync: _sync,
                    onPickDate: _pickDate,
                    serverOnline: _serverOnline,
                    apiOnline: _apiOnline,
                    aiOnline: _aiOnline,
                  ),
                  const SizedBox(height: 12),
                  _StatsCard(stats: _stats),
                  if (_stats.unsynced > 0) ...<Widget>[
                    const SizedBox(height: 12),
                    _PendingBanner(
                      count: _stats.unsynced,
                      sending: _sendingPending,
                      onSend: _sendPending,
                    ),
                  ],
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _ErrorBanner(onRetry: () => _load(showSpinner: true)),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'ابحث بالاسم أو الباركود أو الجوال',
                      prefixIcon: const Icon(Icons.search_rounded, size: 21),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'مسح',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Text(
                        'مرضى ${dayLabel(_date)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F766E).withOpacity(0.09),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${filtered.length}',
                          style: const TextStyle(
                            color: Color(0xFF0F766E),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (_loading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (filtered.isEmpty)
                    _EmptyPatients(
                      hasQuery: _query.trim().isNotEmpty,
                      onClearQuery: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      onSync: _sync,
                      onSeed: _seedDemo,
                    )
                  else
                    ...filtered.map(
                      (patient) => _PatientCard(
                        patient: patient,
                        onTap: () => _openPatient(patient),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startScan,
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner_rounded),
        label: const Text(
          'مسح الباركود',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SyncHeader extends StatelessWidget {
  final DateTime date;
  final int total;
  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback onPickDate;
  final bool? serverOnline;
  final bool? apiOnline;
  final bool? aiOnline;

  const _SyncHeader({
    required this.date,
    required this.total,
    required this.syncing,
    required this.onSync,
    required this.onPickDate,
    this.serverOnline,
    this.apiOnline,
    this.aiOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF0F766E), Color(0xFF0D9488)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF0F766E).withOpacity(0.24),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.biotech_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: GestureDetector(
                  onTap: onPickDate,
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        formatFullDate(date),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dayLabel(date),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusDot(
                icon: Icons.dns_rounded,
                label: 'السيرفر',
                online: serverOnline,
              ),
              const SizedBox(width: 5),
              _StatusDot(
                icon: Icons.api_rounded,
                label: 'API',
                online: apiOnline,
              ),
              const SizedBox(width: 5),
              _StatusDot(
                icon: Icons.psychology_rounded,
                label: 'الذكاء (OCR)',
                online: aiOnline,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '$total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'إجمالي مرضى اليوم',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.74),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 138,
                child: FilledButton.icon(
                  onPressed: syncing ? null : onSync,
                  icon: syncing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: Text(syncing ? 'جارٍ المزامنة' : 'مزامنة اليوم'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.16),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white.withOpacity(0.10),
                    disabledForegroundColor: Colors.white70,
                    minimumSize: const Size(0, 46),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: BorderSide(color: Colors.white.withOpacity(0.26)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final LocalStats stats;

  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Row(
        children: <Widget>[
          _StatCell(value: stats.pending, label: 'بالانتظار', color: const Color(0xFFD97706)),
          const _StatDivider(),
          _StatCell(value: stats.inProgress, label: 'قيد العمل', color: const Color(0xFF0284C7)),
          const _StatDivider(),
          _StatCell(value: stats.completed, label: 'جاهز', color: const Color(0xFF7C3AED)),
          const _StatDivider(),
          _StatCell(value: stats.synced, label: 'مُرسل', color: const Color(0xFF059669)),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final int value;
  final String label;
  final Color color;

  const _StatCell({
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            '$value',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: color,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      color: const Color(0xFFEDF2F1),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  final int count;
  final bool sending;
  final VoidCallback onSend;

  const _PendingBanner({
    required this.count,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 8, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_upload_outlined,
              color: Color(0xFFB45309), size: 21),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'لديك $count نتيجة محفوظة بانتظار الإرسال',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: sending ? null : onSend,
            child: sending
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('إرسال الكل',
                    style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorBanner({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFB91C1C), size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'تعذر تحميل البيانات المحلية.',
              style: TextStyle(fontSize: 12, color: Color(0xFF991B1B)),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  final Patient patient;
  final VoidCallback onTap;

  const _PatientCard({required this.patient, required this.onTap});

  Color get _statusColor {
    switch (patient.status) {
      case PatientStatus.pending:
        return const Color(0xFFD97706);
      case PatientStatus.inProgress:
        return const Color(0xFF0284C7);
      case PatientStatus.completed:
        return const Color(0xFF7C3AED);
      case PatientStatus.synced:
        return const Color(0xFF059669);
    }
  }

  String get _testsSummary {
    if (patient.tests.isEmpty) return 'لا توجد تحاليل محددة';
    final names = patient.tests.take(3).map((test) => test.name).join(' • ');
    if (patient.tests.length <= 3) return names;
    return '$names +${patient.tests.length - 3}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE5ECEA)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: <Widget>[
                Container(
                  width: 47,
                  height: 47,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _statusColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    patient.initials,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              patient.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: _statusColor.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              patient.status.label,
                              style: TextStyle(
                                color: _statusColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.qr_code_2_rounded,
                              size: 13, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              patient.barcode.isEmpty ? '—' : patient.barcode,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          if (patient.detailsLabel.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 9),
                            Text(
                              patient.detailsLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _testsSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_left_rounded,
                    color: Color(0xFFCBD5E1), size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyPatients extends StatelessWidget {
  final bool hasQuery;
  final VoidCallback onClearQuery;
  final VoidCallback onSync;
  final VoidCallback onSeed;

  const _EmptyPatients({
    required this.hasQuery,
    required this.onClearQuery,
    required this.onSync,
    required this.onSeed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E).withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasQuery ? Icons.search_off_rounded : Icons.inbox_outlined,
              color: const Color(0xFF0F766E),
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasQuery ? 'لا توجد نتائج مطابقة' : 'لا يوجد مرضى لهذا اليوم',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            hasQuery
                ? 'جرّب اسماً أو باركوداً آخر.'
                : 'ابدأ بمزامنة مرضى اليوم من السيرفر، أو استخدم بيانات تجريبية للتجربة.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF64748B),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          if (hasQuery)
            OutlinedButton.icon(
              onPressed: onClearQuery,
              icon: const Icon(Icons.close_rounded, size: 17),
              label: const Text('مسح البحث'),
            )
          else
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSync,
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('مزامنة'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 46),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSeed,
                    icon: const Icon(Icons.science_outlined, size: 17),
                    label: const Text('بيانات تجريبية'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool? online;

  const _StatusDot({
    required this.icon,
    required this.label,
    this.online,
  });

  @override
  Widget build(BuildContext context) {
    final color = online == null
        ? Colors.white54
        : (online! ? const Color(0xFF4ADE80) : const Color(0xFFF87171));
    final state = online == null ? 'غير معروف' : (online! ? 'متصل' : 'غير متصل');
    return Tooltip(
      message: '$label: $state',
      child: Icon(icon, size: 14, color: color),
    );
  }
}

class _TestResult extends StatelessWidget {
  final String label;
  final bool ok;

  const _TestResult({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    final color = ok ? const Color(0xFF059669) : const Color(0xFFB91C1C);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ${ok ? "متصل" : "غير متصل"}',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _urlController;
  late final TextEditingController _globalController;
  late final TextEditingController _keyController;
  late final TextEditingController _aiUrlController;
  late final TextEditingController _aiKeyController;
  late final TextEditingController _aiModelController;
  late final TextEditingController _labController;
  late final TextEditingController _operatorController;
  bool _saving = false;
  bool _testingServer = false;
  bool _testingApi = false;
  bool _checkingLicense = false;
  bool _notificationsEnabled = true;
  String _aiProviderId = 'openai';
  bool? _serverOk;
  bool? _apiOk;
  String? _error;

  @override
  void initState() {
    super.initState();
    final api = ApiService.instance;
    _urlController = TextEditingController(text: api.localUrl);
    _globalController = TextEditingController(text: api.globalUrl);
    _keyController = TextEditingController(text: api.apiKey);
    _aiUrlController = TextEditingController(text: api.aiBaseUrl);
    _aiKeyController = TextEditingController(text: api.aiApiKey);
    _aiModelController = TextEditingController(text: api.aiModel);
    _labController = TextEditingController(text: api.labId);
    _operatorController = TextEditingController(text: api.operatorName);
    _notificationsEnabled = NotificationService.instance.enabled;
    _aiProviderId = api.aiProvider;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _globalController.dispose();
    _keyController.dispose();
    _aiUrlController.dispose();
    _aiKeyController.dispose();
    _aiModelController.dispose();
    _labController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  Widget _buildModeRow() {
    final api = ApiService.instance;
    final active = api.usingGlobal ? 'العام' : 'المحلي';
    return Row(
      children: <Widget>[
        Text(
          'يبدأ بالمحلي وينتقل للعام تلقائياً عند فشله • الحالي: $active',
          style: const TextStyle(fontSize: 9.5, color: Color(0xFF94A3B8)),
        ),
        const Spacer(),
        TextButton(
          onPressed: () {
            api.useLocal();
            setState(() {});
          },
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('محلي', style: TextStyle(fontSize: 10.5)),
        ),
        TextButton(
          onPressed: () {
            api.useGlobal();
            setState(() {});
          },
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 28),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text('عام', style: TextStyle(fontSize: 10.5)),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ApiService.instance.saveSettings(
        baseUrl: _urlController.text,
        apiKey: _keyController.text,
        labId: _labController.text,
        operatorName: _operatorController.text,
        globalUrl: _globalController.text,
        aiBaseUrl: _aiUrlController.text,
        aiApiKey: _aiKeyController.text,
        aiModel: _aiModelController.text,
        aiProvider: _aiProviderId,
      );
      if (!mounted) return;
      unawaited(PushService.instance.registerCurrentToken());
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _testServer() async {
    if (_urlController.text.trim().isEmpty) {
      setState(() => _error = 'أدخل عنوان السيرفر أولاً.');
      return;
    }
    setState(() {
      _testingServer = true;
      _serverOk = null;
      _error = null;
    });
    final ok = await ConnectionService.server(
      baseUrl: _urlController.text,
      apiKey: _keyController.text,
    );
    if (!mounted) return;
    setState(() {
      _testingServer = false;
      _serverOk = ok;
    });
  }

  Future<void> _testApi() async {
    if (_urlController.text.trim().isEmpty) {
      setState(() => _error = 'أدخل عنوان السيرفر أولاً.');
      return;
    }
    setState(() {
      _testingApi = true;
      _apiOk = null;
      _error = null;
    });
    final ok = await ConnectionService.api(
      baseUrl: _urlController.text,
      apiKey: _keyController.text,
    );
    if (!mounted) return;
    setState(() {
      _testingApi = false;
      _apiOk = ok;
    });
  }

  Widget _buildLicenseCard() {
    final activation = ActivationService.instance;
    final statusLabel = switch (activation.status) {
      'approved' => 'معتمد',
      'pending' => 'بانتظار الموافقة',
      'rejected' => 'مرفوض',
      'revoked' => 'ملغى',
      _ => 'غير مفعّل',
    };
    final statusColor = activation.status == 'approved'
        ? const Color(0xFF059669)
        : activation.status == 'pending'
            ? const Color(0xFFB45309)
            : activation.status == 'none'
                ? const Color(0xFF64748B)
                : const Color(0xFFDC2626);
    const labels = <String, String>{
      'sync': 'المزامنة',
      'finance': 'المالية',
      'store': 'المخزن',
      'critical': 'الحرجة',
      'reception': 'الاستقبال',
    };
    final granted = activation.permissions
        .map((key) => labels[key] ?? key)
        .join('، ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5ECEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.verified_user_outlined,
                  size: 18, color: Color(0xFF0F766E)),
              const SizedBox(width: 7),
              const Text(
                'ترخيص النسخة',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'كود الطلب: ${activation.requestCode}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF334155),
            ),
          ),
          if (granted.isNotEmpty)
            Text(
              'النوافذ: $granted',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF64748B),
              ),
            ),
          if (activation.approvedBy.isNotEmpty)
            Text(
              'اعتمده: ${activation.approvedBy}',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF64748B),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _checkingLicense ? null : _checkLicense,
              icon: _checkingLicense
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded, size: 16),
              label: const Text('تحقق من الترخيص',
                  style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkLicense() async {
    setState(() {
      _checkingLicense = true;
      _error = null;
    });
    try {
      await ApiService.instance.saveSettings(
        baseUrl: _urlController.text,
        apiKey: _keyController.text,
        labId: _labController.text,
        operatorName: _operatorController.text,
        globalUrl: _globalController.text,
        aiBaseUrl: _aiUrlController.text,
        aiApiKey: _aiKeyController.text,
        aiModel: _aiModelController.text,
        aiProvider: _aiProviderId,
      );
      final status = await ActivationService.instance.refreshStatus();
      if (!mounted) return;
      setState(() {
        _checkingLicense = false;
        _error = status == 'approved'
            ? null
            : status == 'pending'
                ? 'الترخيص ما زال بانتظار موافقة المدير.'
                : status == 'rejected'
                    ? 'تم رفض طلب الترخيص.'
                    : status == 'revoked'
                        ? 'تم إلغاء ترخيص هذه النسخة.'
                        : 'لا يوجد طلب ترخيص.';
      });
      if (status == 'approved') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الترخيص معتمد.'),
            backgroundColor: Color(0xFF0F766E),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingLicense = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'إعدادات السيرفر',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'تُحفظ هذه الإعدادات على الجهاز فقط.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'عنوان السيرفر المحلي',
                  hintText: 'http://192.168.1.10:8080',
                  prefixIcon: Icon(Icons.dns_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _globalController,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'عنوان API العام (نفق/سحابي)',
                  hintText: 'https://xxxx.trycloudflare.com',
                  prefixIcon: Icon(Icons.public_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 4),
              _buildModeRow(),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _labController,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'معرّف المختبر',
                        hintText: 'LAB-01',
                        prefixIcon: Icon(Icons.biotech_outlined, size: 19),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _operatorController,
                      decoration: const InputDecoration(
                        labelText: 'اسم المندوب / المستخدم',
                        hintText: 'مطابق لاسم المستخدم في النظام',
                        prefixIcon: Icon(Icons.person_outline, size: 19),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _keyController,
                textDirection: TextDirection.ltr,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'مفتاح الـ API (اختياري)',
                  hintText: 'X-API-Key',
                  prefixIcon: Icon(Icons.key_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'الذكاء الاصطناعي (OCR)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'تُرسل الصورة إلى مزود الذكاء الاصطناعي. استخدم مفتاحًا خاصًا بالمختبر.',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey<String>(_aiProviderId),
                initialValue: _aiProviderId,
                decoration: const InputDecoration(
                  labelText: 'مزود الذكاء الاصطناعي',
                  prefixIcon: Icon(Icons.auto_awesome_rounded, size: 20),
                ),
                items: AiProvider.all
                    .map(
                      (provider) => DropdownMenuItem<String>(
                        value: provider.id,
                        child: Text(provider.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  final provider = AiProvider.byId(value);
                  setState(() {
                    _aiProviderId = value;
                    if (provider.baseUrl.isNotEmpty) {
                      _aiUrlController.text = provider.baseUrl;
                    }
                    if (provider.model.isNotEmpty) {
                      _aiModelController.text = provider.model;
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _aiUrlController,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'عنوان مزود الذكاء الاصطناعي',
                  hintText: 'https://api.openai.com/v1',
                  prefixIcon: Icon(Icons.auto_awesome_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _aiKeyController,
                textDirection: TextDirection.ltr,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'مفتاح API للذكاء الاصطناعي',
                  hintText: 'sk-...',
                  prefixIcon: Icon(Icons.vpn_key_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _aiModelController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'موديل الذكاء الاصطناعي',
                  hintText: 'gpt-4o-mini',
                  prefixIcon: Icon(Icons.memory_rounded, size: 20),
                ),
              ),
              SwitchListTile(
                value: _notificationsEnabled,
                onChanged: (value) async {
                  setState(() => _notificationsEnabled = value);
                  await NotificationService.instance.setEnabled(value);
                },
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'الإشعارات',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'تنبيه عند وصول نتائج جديدة أو إرسال الطابور',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(height: 12),
              if (ActivationService.required) _buildLicenseCard(),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testingServer ? null : _testServer,
                      icon: _testingServer
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _serverOk == null
                                  ? Icons.wifi_tethering_rounded
                                  : (_serverOk!
                                      ? Icons.check_circle_rounded
                                      : Icons.error_rounded),
                              size: 18,
                            ),
                      label: const Text('فحص السيرفر'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testingApi ? null : _testApi,
                      icon: _testingApi
                          ? const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _apiOk == null
                                  ? Icons.api_rounded
                                  : (_apiOk!
                                      ? Icons.check_circle_rounded
                                      : Icons.error_rounded),
                              size: 18,
                            ),
                      label: const Text('فحص API'),
                    ),
                  ),
                ],
              ),
              if (_serverOk != null || _apiOk != null) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: <Widget>[
                    if (_serverOk != null)
                      _TestResult(label: 'السيرفر', ok: _serverOk!),
                    if (_apiOk != null)
                      _TestResult(label: 'API', ok: _apiOk!),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Text(
                  'GET  {base}/api/patients?date=yyyy-MM-dd\nPOST {base}/api/results',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: Color(0xFF475569),
                    height: 1.6,
                  ),
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('حفظ الإعدادات'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
