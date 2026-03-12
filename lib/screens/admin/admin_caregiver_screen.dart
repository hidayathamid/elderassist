import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui_tokens.dart';
import '../../widgets/default_profile_avatar.dart';
import '../../widgets/standard_app_bar.dart';
import '../user/activity/activity_screen.dart'
    show activityBackgroundColor, activityButtonYellow;
import 'admin_ui.dart';

const Color _profileDarkText = Color(0xFF1B1D29);
const Color _primaryBlue = Color(0xFF00A8A7);
const double _panelMaxExtent = 0.96;
const List<BoxShadow> _cardShadow = [
  BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
];

final DateFormat _monthLabelFormat = DateFormat('MMM yyyy');
final DateFormat _dateFormat = DateFormat('MMM d, yyyy • h:mm a');

enum _CaregiverStatusFilter { all, verified, unverified }

class AdminCaregiverScreen extends StatefulWidget {
  const AdminCaregiverScreen({super.key});

  @override
  State<AdminCaregiverScreen> createState() => _AdminCaregiverScreenState();
}

class _AdminCaregiverScreenState extends State<AdminCaregiverScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  bool _modalSheetScrimVisible = false;

  late final AnimationController _panelController;
  final ScrollController _panelScrollController = ScrollController();
  bool _panelSeeded = false;
  bool _panelUserInteracted = false;
  double? _pendingPanelSeedValue;

  late DateTime _selectedMonth;
  _CaregiverStatusFilter _statusFilter = _CaregiverStatusFilter.all;

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  @override
  void initState() {
    super.initState();
    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _panelController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _searchText = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _panelController.dispose();
    _panelScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onPanelHandleDragUpdate(double deltaY, double dragRangePx) {
    _panelUserInteracted = true;
    final next = (_panelController.value - (deltaY / dragRangePx)).clamp(
      0.0,
      1.0,
    );
    _panelController.value = next;
  }

  void _onPanelHandleDragEnd(double velocity) {
    _panelUserInteracted = true;
    if (velocity.abs() > 500) {
      if (velocity < 0) {
        _panelController.animateTo(1.0, curve: Curves.easeOutCubic);
      } else {
        _panelController.animateTo(0.0, curve: Curves.easeOutCubic);
      }
      return;
    }
    final snapTarget = _panelController.value >= 0.5 ? 1.0 : 0.0;
    _panelController.animateTo(snapTarget, curve: Curves.easeOutCubic);
  }

  Future<void> _deleteApplication(_CaregiverApplicationEntry entry) async {
    final uid = entry.uid.trim();
    if (uid.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        backgroundColor: activityBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete this application?',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'This will remove it from this list.',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.only(bottom: 12),
        actions: [
          SizedBox(
            width: 120,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: BorderSide(color: Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: activityButtonYellow,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await FirebaseFirestore.instance.collection('waitinglist').doc(uid).set({
      'hidden': true,
      'hiddenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Application removed.')));
  }

  void _shiftMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  ({DateTime start, DateTime end}) _monthRange(DateTime month) {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return (start: start, end: end);
  }

  String _monthLabel(DateTime month) => _monthLabelFormat.format(month);

  Future<void> _generateMonthlyCaregiverVerificationsReport() async {
    final month = _selectedMonth;
    const pdfType = XTypeGroup(label: 'pdf', extensions: ['pdf']);

    BuildContext? loadingDialogContext;
    var loadingOpen = true;

    void closeLoadingIfOpen() {
      if (!loadingOpen) return;
      final ctx = loadingDialogContext;
      if (ctx == null) return;
      final nav = Navigator.of(ctx, rootNavigator: true);
      if (nav.canPop()) nav.pop();
      loadingOpen = false;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        loadingDialogContext = dialogContext;
        return const AlertDialog(
          backgroundColor: Colors.white,
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Generating report...',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final callable = _functions.httpsCallable(
        'generateAdminCaregiverVerificationsReport',
      );
      final result = await callable.call(<String, dynamic>{
        'year': month.year,
        'month': month.month,
      });

      closeLoadingIfOpen();

      final data = (result.data as Map).cast<String, dynamic>();
      final pdfBase64 = (data['pdfBase64'] as String?) ?? '';
      final fileName =
          (data['fileName'] as String?) ?? 'caregiver-verifications.pdf';
      if (pdfBase64.trim().isEmpty) {
        throw FirebaseFunctionsException(
          code: 'missing-pdf',
          message: 'No PDF returned from server.',
        );
      }

      final bytes = base64Decode(pdfBase64);
      final suggested = fileName.trim().isNotEmpty
          ? fileName.trim()
          : 'caregiver-report.pdf';

      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/$suggested';
        final file = File(path);
        await file.writeAsBytes(bytes, flush: true);
        await OpenFilex.open(path);
        return;
      }

      final savePath = await getSaveLocation(
        suggestedName: suggested,
        acceptedTypeGroups: [pdfType],
      );
      if (savePath == null) return;
      final file = File(savePath.path);
      await file.writeAsBytes(bytes, flush: true);
      await OpenFilex.open(savePath.path);
    } catch (e) {
      closeLoadingIfOpen();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate report: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final month = _selectedMonth;
    final monthLabel = _monthLabel(month);
    final range = _monthRange(month);

    final monthAppsStream = FirebaseFirestore.instance
        .collection('waitinglist')
        .where('createdAt', isGreaterThanOrEqualTo: range.start)
        .where('createdAt', isLessThan: range.end)
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots();

    final waitingStream = FirebaseFirestore.instance
        .collection('waitinglist')
        .orderBy('createdAt', descending: true)
        .limit(400)
        .snapshots();

    final pendingDocsStream = FirebaseFirestore.instance
        .collection('documents')
        .where('status', isEqualTo: false)
        .snapshots();

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final panelBackdropAlpha =
        (lerpDouble(0.0, 0.08, _panelController.value) ?? 0.0)
            .clamp(0.0, 0.12)
            .toDouble();

    return Scaffold(
      backgroundColor: activityBackgroundColor,
      appBar: buildProfileStyleAppBar(
        title: 'Caregiver verifications',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _CaregiversAnalyticsCard(
                monthLabel: monthLabel,
                onPrev: () => _shiftMonth(-1),
                onNext: () => _shiftMonth(1),
                onGenerateReport: _generateMonthlyCaregiverVerificationsReport,
                monthDocsStream: monthAppsStream,
              ),
            ],
          ),
          if (panelBackdropAlpha > 0.001)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  color: Colors.black.withValues(alpha: panelBackdropAlpha),
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final screenHeight = constraints.maxHeight;
              const estimatedHeaderHeight = 280.0;
              const desiredTopGap = 12.0;
              final panelMinExtent =
                  ((screenHeight - (estimatedHeaderHeight + desiredTopGap)) /
                          screenHeight)
                      .clamp(0.30, 0.70)
                      .toDouble();

              final denom = (_panelMaxExtent - panelMinExtent).clamp(0.0, 1.0);
              const desiredInitialT = 0.0;

              if (!_panelSeeded ||
                  (!_panelUserInteracted &&
                      (_panelController.value - desiredInitialT).abs() >
                          0.001)) {
                _panelSeeded = true;
                _pendingPanelSeedValue = desiredInitialT;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (_panelUserInteracted) return;
                  final seed = _pendingPanelSeedValue;
                  if (seed == null) return;
                  _panelController.value = seed;
                });
              }

              final extentBase =
                  panelMinExtent + (denom * _panelController.value);
              final t = denom <= 0 ? 0.0 : _panelController.value;
              final panelHeight = (extentBase * screenHeight)
                  .clamp(0.0, screenHeight)
                  .toDouble();
              final dragRangePx = (denom.abs() * screenHeight)
                  .clamp(1.0, double.infinity)
                  .toDouble();

              return Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  width: double.infinity,
                  height: panelHeight,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      border: Border.all(
                        color: Colors.black.withValues(
                          alpha: (lerpDouble(0.05, 0.07, t) ?? 0.06).clamp(
                            0.0,
                            1.0,
                          ),
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: (lerpDouble(0.14, 0.22, t) ?? 0.14).clamp(
                              0.0,
                              1.0,
                            ),
                          ),
                          blurRadius: (lerpDouble(18, 26, t) ?? 22).clamp(
                            0.0,
                            double.infinity,
                          ),
                          offset: Offset(
                            0,
                            -((lerpDouble(6, 10, t) ?? 8).clamp(
                              0.0,
                              double.infinity,
                            )),
                          ),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          dragStartBehavior: DragStartBehavior.down,
                          onVerticalDragUpdate: (details) =>
                              _onPanelHandleDragUpdate(
                                details.delta.dy,
                                dragRangePx,
                              ),
                          onVerticalDragEnd: (details) => _onPanelHandleDragEnd(
                            details.primaryVelocity ?? 0,
                          ),
                          onVerticalDragCancel: () => _onPanelHandleDragEnd(0),
                          child: SizedBox(
                            height: 44,
                            width: double.infinity,
                            child: Center(
                              child: Container(
                                width: 44,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: Colors.black.withValues(alpha: 0.06),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: ListView(
                            controller: _panelScrollController,
                            padding: EdgeInsets.only(
                              bottom: (bottomInset + 24).clamp(24.0, 64.0),
                            ),
                            physics: const ClampingScrollPhysics(),
                            children: [
                              _SearchField(controller: _searchController),
                              const SizedBox(height: 12),
                              _CaregiverFilterBar(
                                selected: _statusFilter,
                                onSelected: (f) =>
                                    setState(() => _statusFilter = f),
                              ),
                              const SizedBox(height: 10),
                              _ApplicationsList(
                                waitingStream: waitingStream,
                                pendingDocsStream: pendingDocsStream,
                                statusFilter: _statusFilter,
                                searchText: _searchText,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                onOpenSheet: (entry, editable) async {
                                  setState(
                                    () => _modalSheetScrimVisible = true,
                                  );
                                  try {
                                    await showModalBottomSheet<void>(
                                      context: context,
                                      isScrollControlled: true,
                                      barrierColor: Colors.transparent,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => editable
                                          ? _CaregiverVerificationEditSheet(
                                              entry: entry,
                                            )
                                          : _CaregiverVerificationViewSheet(
                                              entry: entry,
                                            ),
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(
                                        () => _modalSheetScrimVisible = false,
                                      );
                                    }
                                  }
                                },
                                onDelete: (entry) => _deleteApplication(entry),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                opacity: _modalSheetScrimVisible ? 1 : 0,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.54),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: _profileDarkText,
      ),
      decoration: InputDecoration(
        hintText: 'Search caregiver',
        hintStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.35),
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          size: 18,
          color: Colors.black.withValues(alpha: 0.50),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: _primaryBlue.withValues(alpha: 0.35)),
        ),
      ),
    );
  }
}

class _CaregiverFilterBar extends StatelessWidget {
  const _CaregiverFilterBar({required this.selected, required this.onSelected});

  final _CaregiverStatusFilter selected;
  final ValueChanged<_CaregiverStatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final label = selected == _CaregiverStatusFilter.verified
        ? 'Verified caregivers'
        : selected == _CaregiverStatusFilter.unverified
        ? 'Unverified caregivers'
        : 'All caregivers';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: 30,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: selected == _CaregiverStatusFilter.all,
                    onTap: () => onSelected(_CaregiverStatusFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Verified',
                    selected: selected == _CaregiverStatusFilter.verified,
                    onTap: () => onSelected(_CaregiverStatusFilter.verified),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Unverified',
                    selected: selected == _CaregiverStatusFilter.unverified,
                    onTap: () => onSelected(_CaregiverStatusFilter.unverified),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            color: _profileDarkText,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _primaryBlue : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black12.withValues(alpha: 0.08)),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : _profileDarkText,
          ),
        ),
      ),
    );
  }
}

class _CaregiverApplicationEntry {
  const _CaregiverApplicationEntry({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.createdAt,
    required this.verified,
    required this.pendingDocs,
  });

  final String uid;
  final String name;
  final String email;
  final String phone;
  final Timestamp? createdAt;
  final bool verified;
  final int pendingDocs;
}

class _ApplicationsList extends StatelessWidget {
  const _ApplicationsList({
    required this.waitingStream,
    required this.pendingDocsStream,
    required this.statusFilter,
    required this.searchText,
    this.shrinkWrap = false,
    this.physics,
    required this.onOpenSheet,
    required this.onDelete,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>> waitingStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>> pendingDocsStream;
  final _CaregiverStatusFilter statusFilter;
  final String searchText;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final Future<void> Function(_CaregiverApplicationEntry entry, bool editable)
  onOpenSheet;
  final Future<void> Function(_CaregiverApplicationEntry entry) onDelete;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: waitingStream,
      builder: (context, waitingSnap) {
        if (waitingSnap.hasError) {
          return buildAdminEmptyState(
            icon: Icons.verified_user_outlined,
            title: 'Unable to load verifications',
            subtitle: 'Please try again.',
          );
        }
        if (!waitingSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final waitingDocs = waitingSnap.data?.docs ?? const [];
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: pendingDocsStream,
          builder: (context, docsSnap) {
            final pendingDocs = docsSnap.data?.docs ?? const [];
            final pendingCounts = <String, int>{};
            for (final d in pendingDocs) {
              final id = ((d.data()['caregiverId'] as String?) ?? '').trim();
              if (id.isEmpty) continue;
              pendingCounts[id] = (pendingCounts[id] ?? 0) + 1;
            }

            final search = searchText.trim().toLowerCase();
            final entries =
                waitingDocs
                    .map((doc) {
                      final data = doc.data();
                      final uid = doc.id.trim();
                      if ((data['hidden'] as bool?) == true) {
                        return null;
                      }
                      final verified = (data['verified'] as bool?) == true;
                      return _CaregiverApplicationEntry(
                        uid: uid,
                        name: (data['name'] as String?)?.trim() ?? '',
                        email: (data['email'] as String?)?.trim() ?? '',
                        phone: (data['phone'] as String?)?.trim() ?? '',
                        createdAt: data['createdAt'] as Timestamp?,
                        verified: verified,
                        pendingDocs: pendingCounts[uid] ?? 0,
                      );
                    })
                    .whereType<_CaregiverApplicationEntry>()
                    .where((e) {
                      if (statusFilter == _CaregiverStatusFilter.verified &&
                          !e.verified) {
                        return false;
                      }
                      if (statusFilter == _CaregiverStatusFilter.unverified &&
                          e.verified) {
                        return false;
                      }
                      if (search.isEmpty) return true;
                      final hay = '${e.uid} ${e.name} ${e.email} ${e.phone}'
                          .toLowerCase();
                      return hay.contains(search);
                    })
                    .toList()
                  ..sort((a, b) {
                    final aTs = a.createdAt?.millisecondsSinceEpoch ?? 0;
                    final bTs = b.createdAt?.millisecondsSinceEpoch ?? 0;
                    return bTs.compareTo(aTs);
                  });

            if (entries.isEmpty) {
              return buildAdminEmptyState(
                icon: Icons.search_off_outlined,
                title: waitingDocs.isEmpty
                    ? 'No caregiver applications'
                    : 'No results',
                subtitle: waitingDocs.isEmpty
                    ? 'Caregiver applications will appear once users register as caregivers.'
                    : 'Try a different keyword.',
              );
            }

            return ListView.separated(
              shrinkWrap: shrinkWrap,
              physics: physics ?? const BouncingScrollPhysics(),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _CaregiverApplicationCard(
                  indexNumber: index + 1,
                  entry: entry,
                  onView: () => onOpenSheet(entry, false),
                  onEdit: () => onOpenSheet(entry, true),
                  onDelete: () => onDelete(entry),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CaregiverApplicationCard extends StatelessWidget {
  const _CaregiverApplicationCard({
    required this.indexNumber,
    required this.entry,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final int indexNumber;
  final _CaregiverApplicationEntry entry;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final displayName = entry.name.isNotEmpty
        ? entry.name
        : (entry.uid.isNotEmpty ? entry.uid : 'Caregiver');
    final appliedAt = entry.createdAt?.toDate();
    final appliedValue = appliedAt == null
        ? '-'
        : _dateFormat.format(appliedAt);

    final borderColor = Colors.grey.shade300;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(color: borderColor, width: 1.1),
        boxShadow: _cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  DefaultProfileAvatar(
                    radius: 22,
                    photoUrl: null,
                    label: displayName,
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryBlue,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x24000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        indexNumber.toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: _profileDarkText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _StatusMenuChip(verified: entry.verified),
                            if (entry.pendingDocs > 0) ...[
                              const SizedBox(height: 6),
                              _PendingDocsChip(count: entry.pendingDocs),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1, color: Color(0x14000000)),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x14000000))),
            ),
            child: _InfoRow(label: 'Email', value: entry.email),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x14000000))),
            ),
            child: _InfoRow(label: 'Phone', value: entry.phone),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _InfoRow(label: 'Applied', value: appliedValue),
          ),
          const Divider(height: 24, thickness: 1, color: Color(0x14000000)),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.remove_red_eye,
                  label: 'View',
                  onTap: onView,
                  primary: true,
                ),
              ),
              const SizedBox(width: UiTokens.s8),
              Expanded(
                child: _ActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  onTap: onEdit,
                ),
              ),
              const SizedBox(width: UiTokens.s8),
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.delete_outlined,
                    size: UiTokens.icon20,
                    color: Colors.red,
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

class _PendingDocsChip extends StatelessWidget {
  const _PendingDocsChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 pending' : '$count pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.hourglass_bottom_rounded,
            size: 9,
            color: Color(0xFFF4B63D),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 7.5,
              color: Colors.black.withValues(alpha: 0.80),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = primary ? _primaryBlue : Colors.white;
    final borderColor = primary ? _primaryBlue : Colors.grey.shade300;
    final foreground = primary ? Colors.white : _profileDarkText;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: UiTokens.icon20, color: foreground),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityStyleTabs extends StatelessWidget {
  const _ActivityStyleTabs({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = selectedIndex == index;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: 148,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFF4B63D) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFF4B63D)
                        : Colors.black.withValues(alpha: 0.12),
                    width: 1.1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    labels[index],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? Colors.black
                          : Colors.black.withValues(alpha: 0.65),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusMenuChip extends StatelessWidget {
  const _StatusMenuChip({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final label = verified ? 'Verified' : 'Unverified';
    final dotColor = verified ? Colors.green.shade700 : const Color(0xFFF4B63D);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            height: 3,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 7.5,
              color: Colors.black.withValues(alpha: 0.80),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ActivityBookingStyleCaregiverDetailsTab extends StatelessWidget {
  const _ActivityBookingStyleCaregiverDetailsTab({
    required this.caregiverData,
    required this.documentsStream,
  });

  final Map<String, dynamic> caregiverData;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? documentsStream;

  static const Color _cardBorder = Color(0xFFEBEDF0);
  static const Color _accentGreen = Color(0xFF00A8A7);
  static const Color _cardShadow = Color(0x1A0B0C10);
  static const Color _cardBorderStrong = Color(0xFFE1E4EA);
  static const double _cardRadius = 18;
  static const Color _mutedText = Color(0xFF6B7280);

  static const TextStyle _sectionHeaderTextStyle = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 14,
    color: _profileDarkText,
    letterSpacing: -0.15,
  );

  static const TextStyle _fieldLabelTextStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: _mutedText,
  );

  static const TextStyle _fieldValueTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: _profileDarkText,
    height: 1.25,
  );

  BoxDecoration _premiumCardDecoration({double radius = _cardRadius}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _cardBorderStrong),
      boxShadow: const [
        BoxShadow(color: _cardShadow, blurRadius: 12, offset: Offset(0, 6)),
      ],
    );
  }

  String _normalize(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    return value.toString().trim();
  }

  List<String> _extractServicePreferences(dynamic raw) {
    if (raw is Iterable) {
      return raw
          .map((e) => _normalize(e))
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    final asString = _normalize(raw);
    return asString.isEmpty ? const <String>[] : <String>[asString];
  }

  Widget _buildSectionHeader({required String title, String? hint}) {
    final trimmedHint = (hint ?? '').trim();
    return Row(
      children: [
        Expanded(child: Text(title, style: _sectionHeaderTextStyle)),
        if (trimmedHint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
      ],
    );
  }

  Widget _centerAvatar(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        children: [
          DefaultProfileAvatar(radius: 34, photoUrl: null, label: label),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: _profileDarkText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(List<Widget> children) {
    return Container(
      decoration: _premiumCardDecoration(),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    bool showBorder = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBorder
              ? const BorderSide(color: _cardBorder)
              : BorderSide.none,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: _accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _fieldLabelTextStyle),
                const SizedBox(height: 2),
                Text(value, style: _fieldValueTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listRow({
    required IconData icon,
    required String value,
    required bool showBorder,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBorder
              ? const BorderSide(color: _cardBorder)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _accentGreen),
          const SizedBox(width: 10),
          Expanded(child: Text(value, style: _fieldValueTextStyle)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final caregiverName = _normalize(caregiverData['name']).isNotEmpty
        ? _normalize(caregiverData['name'])
        : 'Caregiver';
    final caregiverLocation =
        _normalize(caregiverData['defaultAddress']).isNotEmpty
        ? _normalize(caregiverData['defaultAddress'])
        : (_normalize(caregiverData['address']).isNotEmpty
              ? _normalize(caregiverData['address'])
              : 'Location not provided');

    final bioRaw = _normalize(caregiverData['bio']);
    final servicesList = _extractServicePreferences(
      caregiverData['servicePreferences'] ?? caregiverData['services'],
    );

    final stream =
        documentsStream ??
        const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final verifiedDocs = snapshot.hasData
            ? snapshot.data!.docs
                  .where((d) => (d.data()['status'] as bool?) == true)
                  .toList(growable: false)
            : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        final certificateNames = verifiedDocs
            .map((d) => (d.data()['name'] as String?)?.trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(
              title: 'Caregiver details',
              hint: 'Profile info from this caregiver.',
            ),
            const SizedBox(height: 4),
            _centerAvatar(caregiverName),
            _buildTabContent([
              _buildInfoRow(
                icon: Icons.person,
                title: 'Name',
                value: caregiverName,
              ),
              _buildInfoRow(
                icon: Icons.info_outline_rounded,
                title: 'Bio',
                value: bioRaw.isNotEmpty ? bioRaw : 'Unavailable',
              ),
              _buildInfoRow(
                icon: Icons.location_on_outlined,
                title: 'Location',
                value: caregiverLocation,
                showBorder: false,
              ),
            ]),
            const SizedBox(height: 14),
            _buildSectionHeader(title: 'Services provided'),
            if (servicesList.isEmpty)
              _buildTabContent([
                _listRow(
                  icon: Icons.medical_services_outlined,
                  value: 'Services unavailable',
                  showBorder: false,
                ),
              ])
            else
              _buildTabContent([
                for (var i = 0; i < servicesList.length; i++)
                  _listRow(
                    icon: Icons.medical_services_outlined,
                    value: servicesList[i],
                    showBorder: i != servicesList.length - 1,
                  ),
              ]),
            const SizedBox(height: 14),
            _buildSectionHeader(title: 'Certificates'),
            if (!snapshot.hasData)
              _buildTabContent([
                _listRow(
                  icon: Icons.verified_outlined,
                  value: 'Loading certificates...',
                  showBorder: false,
                ),
              ])
            else if (certificateNames.isEmpty)
              _buildTabContent([
                _listRow(
                  icon: Icons.verified_outlined,
                  value: 'Certificates unavailable',
                  showBorder: false,
                ),
              ])
            else
              _buildTabContent([
                for (var i = 0; i < certificateNames.length; i++)
                  _listRow(
                    icon: Icons.verified_outlined,
                    value: certificateNames[i],
                    showBorder: i != certificateNames.length - 1,
                  ),
              ]),
          ],
        );
      },
    );
  }
}

class _CaregiversAnalyticsCard extends StatelessWidget {
  const _CaregiversAnalyticsCard({
    required this.monthLabel,
    required this.onPrev,
    required this.onNext,
    required this.onGenerateReport,
    required this.monthDocsStream,
  });

  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onGenerateReport;
  final Stream<QuerySnapshot<Map<String, dynamic>>> monthDocsStream;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: monthDocsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const SizedBox.shrink();
          }
          final docs = snapshot.data?.docs ?? const [];
          var verified = 0;
          var pending = 0;
          for (final d in docs) {
            final data = d.data();
            if (data['hidden'] == true) continue;
            if (data['verified'] == true) {
              verified += 1;
            } else {
              pending += 1;
            }
          }
          final total = pending + verified;
          final segments = <_DonutSegment>[
            _DonutSegment(
              label: 'Pending',
              count: pending,
              color: const Color(0xFFF4B63D),
            ),
            _DonutSegment(
              label: 'Verified',
              count: verified,
              color: _primaryBlue,
            ),
          ];

          return Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: onPrev,
                    icon: const Icon(Icons.chevron_left),
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      monthLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: _profileDarkText,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onNext,
                    icon: const Icon(Icons.chevron_right),
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 4,
                    child: _DonutChart(total: total, segments: segments),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LegendRow(
                            color: Colors.black.withValues(alpha: 0.22),
                            label: 'Total activity',
                            value: total,
                          ),
                        ),
                        for (final s in segments) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _LegendRow(
                              color: s.color,
                              label: s.label,
                              value: s.count,
                            ),
                          ),
                          if (s.label == 'Verified')
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: onGenerateReport,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: activityButtonYellow,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Generate report',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DonutSegment {
  const _DonutSegment({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;
}

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.total, required this.segments});

  final int total;
  final List<_DonutSegment> segments;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(140, 140),
            painter: _DonutPainter(total: total, segments: segments),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                total.toString(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _profileDarkText,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'This month',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.total, required this.segments});

  final int total;
  final List<_DonutSegment> segments;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final strokeWidth = 14.0;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth);

    final basePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, math.pi * 2, false, basePaint);

    if (total <= 0) return;
    var startAngle = -math.pi / 2;
    for (final s in segments) {
      if (s.count <= 0) continue;
      final sweep = (s.count / total) * math.pi * 2;
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.total != total || oldDelegate.segments != segments;
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _profileDarkText,
            ),
          ),
        ),
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: _profileDarkText,
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _CaregiverVerificationDetailsSheet extends StatelessWidget {
  const _CaregiverVerificationDetailsSheet({
    required this.entry,
    required this.editable,
  });

  final _CaregiverApplicationEntry entry;
  final bool editable;

  Widget _cardShell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: _profileDarkText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final uid = entry.uid.trim();

    final waitingRef = uid.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('waitinglist').doc(uid);
    final documentsStream = uid.isEmpty
        ? null
        : FirebaseFirestore.instance
              .collection('documents')
              .where('caregiverId', isEqualTo: uid)
              .snapshots();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Container(
        color: activityBackgroundColor,
        padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottomInset),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: waitingRef?.snapshots(),
              builder: (context, waitingSnap) {
                final data =
                    waitingSnap.data?.data() ?? const <String, dynamic>{};
                final name = ((data['name'] as String?) ?? '').trim();
                final email = ((data['email'] as String?) ?? '').trim();
                final phone = ((data['phone'] as String?) ?? '').trim();
                final address = ((data['defaultAddress'] as String?) ?? '')
                    .trim();
                final verified = (data['verified'] as bool?) == true;
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

                final displayName = name.isNotEmpty
                    ? name
                    : (uid.isNotEmpty ? uid : 'Caregiver');
                final subtitleParts = <String>[];
                if (email.isNotEmpty) subtitleParts.add(email);
                if (phone.isNotEmpty) subtitleParts.add(phone);
                final subtitle = subtitleParts.join(' • ');

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            editable
                                ? 'Edit verification'
                                : 'Verification details',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: _profileDarkText,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (false) ...[
                      _sectionTitle('Application'),
                      _cardShell(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  DefaultProfileAvatar(
                                    radius: 22,
                                    photoUrl: null,
                                    label: displayName,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w900,
                                            color: _profileDarkText,
                                          ),
                                        ),
                                        if (subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            subtitle,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.black.withValues(
                                                alpha: 0.55,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: _InfoRow(
                                      label: 'User ID',
                                      value: uid,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: _InfoRow(
                                      label: 'Status',
                                      value: verified
                                          ? 'Verified'
                                          : 'Unverified',
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: _InfoRow(
                                      label: 'Applied at',
                                      value: createdAt == null
                                          ? '-'
                                          : _dateFormat.format(createdAt),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: _InfoRow(
                                      label: 'Address',
                                      value: address.isNotEmpty ? address : '-',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _sectionTitle('Documents'),
                    _DocumentsCard(
                      stream: documentsStream,
                      caregiverId: uid,
                      canVerify: editable && !verified,
                      wrapInCard: false,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminBookingsStyleUserDetailsTab extends StatelessWidget {
  const _AdminBookingsStyleUserDetailsTab({
    required this.uid,
    required this.name,
    required this.photoUrl,
    required this.email,
    required this.phone,
    required this.address,
    required this.createdAt,
    required this.verified,
  });

  final String uid;
  final String name;
  final String? photoUrl;
  final String email;
  final String phone;
  final String address;
  final DateTime? createdAt;
  final bool verified;

  static const Color _cardBorder = Color(0xFFEBEDF0);
  static const Color _accentGreen = Color(0xFF00A8A7);
  static const Color _cardShadow = Color(0x1A0B0C10);
  static const Color _cardBorderStrong = Color(0xFFE1E4EA);
  static const double _cardRadius = 18;
  static const Color _mutedText = Color(0xFF6B7280);
  static const Color _avatarOutlineColor = Colors.white;

  static const TextStyle _sectionHeaderTextStyle = TextStyle(
    fontWeight: FontWeight.w800,
    fontSize: 14,
    color: _profileDarkText,
    letterSpacing: -0.15,
  );

  static const TextStyle _fieldLabelTextStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: _mutedText,
  );

  static const TextStyle _fieldValueTextStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: _profileDarkText,
    height: 1.25,
  );

  BoxDecoration _premiumCardDecoration({double radius = _cardRadius}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _cardBorderStrong),
      boxShadow: const [
        BoxShadow(color: _cardShadow, blurRadius: 12, offset: Offset(0, 6)),
      ],
    );
  }

  Widget _buildSectionHeader({required String title, String? hint}) {
    final trimmedHint = (hint ?? '').trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: _sectionHeaderTextStyle)),
              if (trimmedHint.isNotEmpty) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.black.withValues(alpha: 0.45),
                ),
              ],
            ],
          ),
          if (trimmedHint.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              trimmedHint,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.black.withValues(alpha: 0.50),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _centerAvatar(String label, String? photoUrl, {double radius = 34}) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _avatarOutlineColor, width: 3.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 12,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: DefaultProfileAvatar(
          radius: radius,
          photoUrl: (photoUrl?.trim().isNotEmpty == true)
              ? photoUrl!.trim()
              : null,
          label: label,
        ),
      ),
    );
  }

  Widget _buildTabContent(List<Widget> children) {
    return Container(
      decoration: _premiumCardDecoration(),
      margin: const EdgeInsets.only(top: 6),
      child: Column(children: children),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String value,
    bool showBorder = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: showBorder
              ? const BorderSide(color: _cardBorder)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: _accentGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _fieldLabelTextStyle),
                const SizedBox(height: 4),
                Text(value, style: _fieldValueTextStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isNotEmpty
        ? name.trim()
        : (uid.trim().isNotEmpty ? uid.trim() : 'User');
    final appliedAtLabel = createdAt == null
        ? '—'
        : _dateFormat.format(createdAt!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: 'User details'),
        const SizedBox(height: 4),
        _centerAvatar(displayName, photoUrl),
        _buildTabContent([
          if (uid.trim().isNotEmpty)
            _buildInfoRow(
              icon: Icons.badge_outlined,
              title: 'User ID',
              value: uid.trim(),
            ),
          _buildInfoRow(
            icon: Icons.person,
            title: 'Full name',
            value: displayName,
          ),
          _buildInfoRow(
            icon: Icons.email_outlined,
            title: 'Email',
            value: email.trim().isNotEmpty ? email.trim() : '—',
          ),
          _buildInfoRow(
            icon: Icons.phone_android,
            title: 'Contact',
            value: phone.trim().isNotEmpty ? phone.trim() : '—',
          ),
          _buildInfoRow(
            icon: Icons.home,
            title: 'Address',
            value: address.trim().isNotEmpty ? address.trim() : '—',
          ),
          _buildInfoRow(
            icon: Icons.schedule_rounded,
            title: 'Applied at',
            value: appliedAtLabel,
          ),
          _buildInfoRow(
            icon: verified
                ? Icons.verified_rounded
                : Icons.pending_actions_rounded,
            title: 'Verification status',
            value: verified ? 'Verified' : 'Unverified',
            showBorder: false,
          ),
        ]),
      ],
    );
  }
}

class _CaregiverVerificationViewSheet extends StatefulWidget {
  const _CaregiverVerificationViewSheet({required this.entry});

  final _CaregiverApplicationEntry entry;

  @override
  State<_CaregiverVerificationViewSheet> createState() =>
      _CaregiverVerificationViewSheetState();
}

class _CaregiverVerificationViewSheetState
    extends State<_CaregiverVerificationViewSheet> {
  int _selectedTabIndex = 0;

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: _profileDarkText,
        ),
      ),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0B0C10),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final uid = widget.entry.uid.trim();

    final waitingRef = uid.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('waitinglist').doc(uid);
    final documentsStream = uid.isEmpty
        ? null
        : FirebaseFirestore.instance
              .collection('documents')
              .where('caregiverId', isEqualTo: uid)
              .snapshots();

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.52,
        maxChildSize: 0.96,
        builder: (sheetContext, controller) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Verification details',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: _profileDarkText,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        splashRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ActivityStyleTabs(
                    labels: const ['User details', 'Verification details'],
                    selectedIndex: _selectedTabIndex,
                    onSelected: (index) =>
                        setState(() => _selectedTabIndex = index),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: waitingRef?.snapshots(),
                    builder: (context, waitingSnap) {
                      final data =
                          waitingSnap.data?.data() ?? const <String, dynamic>{};
                      final name = ((data['name'] as String?) ?? '').trim();
                      final email = ((data['email'] as String?) ?? '').trim();
                      final phone = ((data['phone'] as String?) ?? '').trim();
                      final address =
                          ((data['defaultAddress'] as String?) ?? '').trim();
                      final verified = (data['verified'] as bool?) == true;
                      final createdAt = (data['createdAt'] as Timestamp?)
                          ?.toDate();

                      if (_selectedTabIndex == 0) {
                        return _AdminBookingsStyleUserDetailsTab(
                          uid: uid,
                          name: name,
                          photoUrl: (data['photoUrl'] as String?)?.trim(),
                          email: email,
                          phone: phone,
                          address: address,
                          createdAt: createdAt,
                          verified: verified,
                        );
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (false) ...[
                            _sectionTitle('Application'),
                            _cardShell(
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      12,
                                      14,
                                      12,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        DefaultProfileAvatar(
                                          radius: 22,
                                          photoUrl: null,
                                          label: name.isNotEmpty
                                              ? name
                                              : (uid.isNotEmpty
                                                    ? uid
                                                    : 'Caregiver'),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name.isNotEmpty
                                                    ? name
                                                    : (uid.isNotEmpty
                                                          ? uid
                                                          : 'Caregiver'),
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w900,
                                                  color: _profileDarkText,
                                                ),
                                              ),
                                              if (email.isNotEmpty ||
                                                  phone.isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  [
                                                    if (email.isNotEmpty) email,
                                                    if (phone.isNotEmpty) phone,
                                                  ].join(' â€¢ '),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.55,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: Colors.black.withValues(alpha: 0.06),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.black.withValues(
                                                  alpha: 0.06,
                                                ),
                                              ),
                                            ),
                                          ),
                                          child: _InfoRow(
                                            label: 'User ID',
                                            value: uid,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.black.withValues(
                                                  alpha: 0.06,
                                                ),
                                              ),
                                            ),
                                          ),
                                          child: _InfoRow(
                                            label: 'Status',
                                            value: verified
                                                ? 'Verified'
                                                : 'Unverified',
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Colors.black.withValues(
                                                  alpha: 0.06,
                                                ),
                                              ),
                                            ),
                                          ),
                                          child: _InfoRow(
                                            label: 'Applied at',
                                            value: createdAt == null
                                                ? '-'
                                                : _dateFormat.format(createdAt),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                          child: _InfoRow(
                                            label: 'Address',
                                            value: address.isNotEmpty
                                                ? address
                                                : '-',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          _sectionTitle('Documents'),
                          _DocumentsCard(
                            stream: documentsStream,
                            caregiverId: uid,
                            canVerify: false,
                            wrapInCard: false,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CaregiverVerificationEditSheet extends StatefulWidget {
  const _CaregiverVerificationEditSheet({required this.entry});

  final _CaregiverApplicationEntry entry;

  @override
  State<_CaregiverVerificationEditSheet> createState() =>
      _CaregiverVerificationEditSheetState();
}

class _CaregiverVerificationEditSheetState
    extends State<_CaregiverVerificationEditSheet> {
  bool _seeded = false;
  bool _verified = false;
  bool _saving = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _toggleVerified(String uid, Map<String, dynamic> data) async {
    if (_saving) return;
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return;

    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final waitingRef = db.collection('waitinglist').doc(trimmed);
      final caregiverRef = db.collection('caregivers').doc(trimmed);
      final userRef = db.collection('users').doc(trimmed);
      final nextVerified = !_verified;

      if (nextVerified) {
        final pendingDocs = await db
            .collection('documents')
            .where('caregiverId', isEqualTo: trimmed)
            .where('status', isEqualTo: false)
            .get();
        if (pendingDocs.docs.isNotEmpty) {
          final batch = db.batch();
          for (final doc in pendingDocs.docs) {
            batch.set(doc.reference, {
              'status': true,
              'verifiedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
          await batch.commit();
        }

        double? safeDouble(dynamic value) {
          if (value is num) return value.toDouble();
          if (value is String && value.trim().isNotEmpty) {
            return double.tryParse(value.trim());
          }
          return null;
        }

        final userSnap = await userRef.get();
        final userData = userSnap.data();

        String? resolveDefaultAddress() {
          String pick(dynamic v) => (v?.toString() ?? '').trim();
          final waiting = pick(data['defaultAddress']);
          if (waiting.isNotEmpty) return waiting;
          final fromUser = pick(userData?['defaultAddress']);
          if (fromUser.isNotEmpty) return fromUser;
          final addressList = userData?['address'];
          if (addressList is List) {
            Map<String, dynamic>? best;
            for (final entry in addressList) {
              if (entry is! Map) continue;
              final map = Map<String, dynamic>.from(entry);
              best ??= map;
              if (map['isDefault'] == true) {
                best = map;
                break;
              }
            }
            final fromList = best == null ? '' : pick(best['address']);
            if (fromList.isNotEmpty) return fromList;
          }
          final fromUserAlt = pick(userData?['address']);
          if (fromUserAlt.isNotEmpty) return fromUserAlt;
          return null;
        }

        final resolvedDefaultAddress = resolveDefaultAddress();
        final caregiverPayload = <String, dynamic>{
          'caregiverId': trimmed,
          'role': 'caregiver',
          'name': (data['name'] as String?)?.trim() ?? '',
          'email':
              (data['email'] as String?)?.trim() ??
              (userData?['email'] as String?)?.toString().trim() ??
              '',
          'phone':
              (data['phone'] as String?)?.trim() ??
              (userData?['phone'] as String?)?.toString().trim() ??
              '',
          'defaultAddress': resolvedDefaultAddress,
          if (safeDouble(data['lat']) != null) 'lat': safeDouble(data['lat']),
          if (safeDouble(data['lng']) != null) 'lng': safeDouble(data['lng']),
          'servicePreferences': data['servicePreferences'] ?? const [],
          'photoUrl':
              ((userData?['photoUrl'] as String?) ?? '').trim().isNotEmpty
              ? ((userData?['photoUrl'] as String?) ?? '').trim()
              : '',
          'bio': (userData?['bio'] as String?)?.toString() ?? '',
          'certifications': userData?['certifications'] ?? const [],
          'rating': (userData?['rating'] as num?)?.toDouble() ?? 0.0,
          'jobsCompleted': (userData?['jobsCompleted'] as num?)?.toInt() ?? 0,
          'availability': (userData?['availability'] as bool?) ?? false,
          'created_at': FieldValue.serverTimestamp(),
          'verifiedAt': FieldValue.serverTimestamp(),
          'forceLogoutAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        final paymentDetails = userData?['paymentDetails'];
        if (paymentDetails is Map)
          caregiverPayload['paymentDetails'] = paymentDetails;
        final fcmToken = (userData?['fcmToken'] as String?)?.trim();
        if (fcmToken != null && fcmToken.isNotEmpty) {
          caregiverPayload['fcmToken'] = fcmToken;
        }

        final batch = db.batch();
        batch.set(caregiverRef, caregiverPayload, SetOptions(merge: true));
        batch.set(waitingRef, {
          'verified': true,
          'verifiedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        batch.delete(userRef);
        await batch.commit();
      } else {
        final caregiverSnap = await caregiverRef.get();
        final caregiverData = caregiverSnap.data();

        final approvedDocs = await db
            .collection('documents')
            .where('caregiverId', isEqualTo: trimmed)
            .where('status', isEqualTo: true)
            .get();
        if (approvedDocs.docs.isNotEmpty) {
          final batch = db.batch();
          for (final doc in approvedDocs.docs) {
            batch.set(doc.reference, {
              'status': false,
              'verifiedAt': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
          await batch.commit();
        }

        final userPayload = <String, dynamic>{
          'role': 'user',
          'name':
              (caregiverData?['name'] as String?)?.trim() ??
              (data['name'] as String?)?.trim() ??
              '',
          'email':
              (caregiverData?['email'] as String?)?.trim() ??
              (data['email'] as String?)?.trim() ??
              '',
          'phone':
              (caregiverData?['phone'] as String?)?.trim() ??
              (data['phone'] as String?)?.trim() ??
              '',
          'defaultAddress':
              (caregiverData?['defaultAddress'] as String?)?.trim() ??
              (data['defaultAddress'] as String?)?.trim() ??
              '',
          if (caregiverData?['paymentDetails'] is Map)
            'paymentDetails': caregiverData?['paymentDetails'],
          if ((caregiverData?['photoUrl'] as String?)?.trim().isNotEmpty ==
              true)
            'photoUrl': (caregiverData?['photoUrl'] as String?)!.trim(),
          if ((caregiverData?['fcmToken'] as String?)?.trim().isNotEmpty ==
              true)
            'fcmToken': (caregiverData?['fcmToken'] as String?)!.trim(),
          'forceLogoutAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        final batch = db.batch();
        batch.set(userRef, userPayload, SetOptions(merge: true));
        batch.set(waitingRef, {
          'verified': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        batch.delete(caregiverRef);
        await batch.commit();
      }

      if (!mounted) return;
      setState(() => _verified = nextVerified);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextVerified
                ? 'Caregiver verified. Documents marked as verified.'
                : 'Caregiver marked as unverified. Documents marked as unverified.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('StateError: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final uid = widget.entry.uid.trim();

    final waitingRef = uid.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('waitinglist').doc(uid);
    final caregiverRef = uid.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('caregivers').doc(uid);
    final userRef = uid.isEmpty
        ? null
        : FirebaseFirestore.instance.collection('users').doc(uid);

    Future<Map<String, dynamic>> loadProfile() async {
      if (uid.isEmpty) return const <String, dynamic>{};
      try {
        final caregiverSnap = await caregiverRef?.get();
        final userSnap = await userRef?.get();
        return <String, dynamic>{
          ...(caregiverSnap?.data() ?? const <String, dynamic>{}),
          ...(userSnap?.data() ?? const <String, dynamic>{}),
        };
      } catch (_) {
        return const <String, dynamic>{};
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.52,
        maxChildSize: 0.96,
        builder: (sheetContext, controller) {
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(26),
              ),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(0, -10),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: ListView(
                controller: controller,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: waitingRef?.snapshots(),
                    builder: (context, snap) {
                      final data =
                          snap.data?.data() ?? const <String, dynamic>{};
                      final waitingExists = snap.data?.exists == true;
                      final nameWaiting = ((data['name'] as String?) ?? '')
                          .trim();
                      final emailWaiting = ((data['email'] as String?) ?? '')
                          .trim();
                      final phoneWaiting = ((data['phone'] as String?) ?? '')
                          .trim();
                      final addressWaiting =
                          ((data['defaultAddress'] as String?) ?? '').trim();

                      InputDecoration inputDecoration({
                        required String labelText,
                        Widget? suffixIcon,
                      }) {
                        return InputDecoration(
                          labelText: labelText,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                            borderSide: BorderSide(
                              color: _profileDarkText,
                              width: 1.1,
                            ),
                          ),
                          suffixIcon: suffixIcon,
                        );
                      }

                      return FutureBuilder<Map<String, dynamic>>(
                        future: loadProfile(),
                        builder: (context, profileSnap) {
                          final profile =
                              profileSnap.data ?? const <String, dynamic>{};

                          String pickText(Iterable<dynamic> candidates) {
                            for (final c in candidates) {
                              final v = c?.toString().trim() ?? '';
                              if (v.isNotEmpty) return v;
                            }
                            return '';
                          }

                          String resolveAddressLikeUserDetails(dynamic value) {
                            final v = value;
                            if (v == null) return '';
                            if (v is String) return v.trim();
                            if (v is List) {
                              Map<String, dynamic>? best;
                              for (final entry in v) {
                                if (entry is! Map) continue;
                                final map = Map<String, dynamic>.from(entry);
                                best ??= map;
                                if (map['isDefault'] == true) {
                                  best = map;
                                  break;
                                }
                              }
                              final addr =
                                  best?['address']?.toString().trim() ?? '';
                              return addr;
                            }
                            return v.toString().trim();
                          }

                          final name = pickText([
                            nameWaiting,
                            profile['name'],
                            widget.entry.name,
                          ]);
                          final email = pickText([
                            emailWaiting,
                            data['userEmail'],
                            profile['email'],
                            profile['userEmail'],
                            widget.entry.email,
                          ]);
                          final phone = pickText([
                            phoneWaiting,
                            data['contact'],
                            profile['phone'],
                            profile['contact'],
                            widget.entry.phone,
                          ]);
                          final address = pickText([
                            addressWaiting,
                            resolveAddressLikeUserDetails(
                              data['defaultAddress'],
                            ),
                            resolveAddressLikeUserDetails(data['address']),
                            resolveAddressLikeUserDetails(data['area']),
                            resolveAddressLikeUserDetails(data['location']),
                            resolveAddressLikeUserDetails(
                              profile['defaultAddress'],
                            ),
                            resolveAddressLikeUserDetails(profile['address']),
                            resolveAddressLikeUserDetails(profile['area']),
                            resolveAddressLikeUserDetails(profile['location']),
                          ]);

                          final verified =
                              (data['verified'] as bool?) == true ||
                              profile['verifiedAt'] != null;
                          if (!_seeded) {
                            _seeded = true;
                            _verified = verified;
                          }

                          final displayName = name.isNotEmpty
                              ? name
                              : (uid.isNotEmpty ? uid : 'Caregiver');

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  width: 44,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Edit verification',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: _profileDarkText,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _saving
                                        ? null
                                        : () => Navigator.of(context).pop(),
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 20,
                                    ),
                                    splashRadius: 18,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Column(
                                children: [
                                  DefaultProfileAvatar(
                                    radius: 34,
                                    photoUrl: null,
                                    label: displayName.isNotEmpty
                                        ? displayName
                                        : '?',
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: _profileDarkText,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (uid.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      uid,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                initialValue: uid,
                                readOnly: true,
                                showCursor: false,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _profileDarkText,
                                ),
                                decoration: inputDecoration(
                                  labelText: 'User ID',
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'Verification details',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: _profileDarkText,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                initialValue: email.isNotEmpty
                                    ? email
                                    : 'Unavailable',
                                readOnly: true,
                                showCursor: false,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _profileDarkText,
                                ),
                                decoration: inputDecoration(labelText: 'Email'),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                initialValue: phone.isNotEmpty
                                    ? phone
                                    : 'Unavailable',
                                readOnly: true,
                                showCursor: false,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _profileDarkText,
                                ),
                                decoration: inputDecoration(
                                  labelText: 'Contact',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                initialValue: address.isNotEmpty
                                    ? address
                                    : 'Unavailable',
                                readOnly: true,
                                showCursor: false,
                                maxLines: 2,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _profileDarkText,
                                ),
                                decoration: inputDecoration(
                                  labelText: 'Address',
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _saving || !waitingExists
                                      ? null
                                      : () => _toggleVerified(uid, data),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: activityButtonYellow,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          _verified
                                              ? 'Unverify caregiver'
                                              : 'Verify caregiver',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VerifiedOption {
  const _VerifiedOption({required this.label, required this.value});

  final String label;
  final bool value;
}

// ignore: unused_element
class _EditableDocumentsSection extends StatelessWidget {
  const _EditableDocumentsSection({
    required this.caregiverId,
    required this.disabled,
  });

  final String caregiverId;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final uid = caregiverId.trim();
    if (uid.isEmpty) {
      return const SizedBox.shrink();
    }

    final stream = FirebaseFirestore.instance
        .collection('documents')
        .where('caregiverId', isEqualTo: uid)
        .snapshots();

    const requiredDocs = <String>[
      'Selfie with identification card',
      'Identification card (Front)',
      'Identification card (Back)',
    ];

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final byName = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final d in docs) {
          final name = ((d.data()['name'] as String?) ?? '').trim();
          if (name.isEmpty) continue;
          byName[name] = d;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final name in requiredDocs) ...[
              _EditableDocumentField(
                title: name,
                document: byName[name],
                disabled: disabled,
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _EditableDocumentField extends StatefulWidget {
  const _EditableDocumentField({
    required this.title,
    required this.document,
    required this.disabled,
  });

  final String title;
  final DocumentSnapshot<Map<String, dynamic>>? document;
  final bool disabled;

  @override
  State<_EditableDocumentField> createState() => _EditableDocumentFieldState();
}

class _EditableDocumentFieldState extends State<_EditableDocumentField> {
  final LayerLink _verifiedFieldLink = LayerLink();
  final GlobalKey _verifiedFieldKey = GlobalKey();
  OverlayEntry? _verifiedOverlayEntry;
  final TextEditingController _verifiedFieldController =
      TextEditingController();

  bool _seeded = false;
  bool _verified = false;

  @override
  void dispose() {
    _closeVerifiedMenu();
    _verifiedFieldController.dispose();
    super.dispose();
  }

  void _toggleVerifiedMenu() {
    if (_verifiedOverlayEntry == null) {
      _openVerifiedMenu();
    } else {
      _closeVerifiedMenu();
    }
  }

  void _openVerifiedMenu() {
    if (widget.disabled) return;
    if (widget.document == null) return;
    _closeVerifiedMenu();
    final overlay = Overlay.of(context);

    final box =
        _verifiedFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;

    const options = [
      _VerifiedOption(label: 'Verified', value: true),
      _VerifiedOption(label: 'Unverified', value: false),
    ];

    _verifiedOverlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _closeVerifiedMenu,
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: _verifiedFieldLink,
                  showWhenUnlinked: false,
                  offset: Offset(0, size.height + 6),
                  child: Material(
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: size.width,
                        maxWidth: size.width,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 18,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: options
                              .map(
                                (option) => InkWell(
                                  onTap: () => _selectVerified(option),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: option.value
                                                ? const Color(0xFF2BB673)
                                                : const Color(0xFFF4B63D),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            option.label,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: _profileDarkText,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(_verifiedOverlayEntry!);
  }

  void _closeVerifiedMenu() {
    _verifiedOverlayEntry?.remove();
    _verifiedOverlayEntry = null;
  }

  Future<void> _selectVerified(_VerifiedOption option) async {
    if (widget.disabled) return;
    final doc = widget.document;
    if (doc == null) return;

    setState(() {
      _verified = option.value;
      _verifiedFieldController.text = option.label;
    });
    _closeVerifiedMenu();

    try {
      await doc.reference.set({
        'status': option.value,
        if (option.value) 'verifiedAt': FieldValue.serverTimestamp(),
        if (!option.value) 'verifiedAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update document status.')),
      );
    }
  }

  Future<void> _openDoc() async {
    final doc = widget.document;
    if (doc == null) return;
    final data = doc.data() ?? const <String, dynamic>{};
    final url = ((data['fileUrl'] as String?) ?? '').trim();
    if (url.isEmpty) return;

    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the document.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final data = doc?.data() ?? const <String, dynamic>{};
    final fileName = ((data['fileName'] as String?) ?? '').trim();
    final url = ((data['fileUrl'] as String?) ?? '').trim();
    final canOpen = url.isNotEmpty;

    final verifiedNow = (data['status'] as bool?) == true;
    if (!_seeded) {
      _seeded = true;
      _verified = verifiedNow;
      _verifiedFieldController.text = _verified ? 'Verified' : 'Unverified';
    }

    InputDecoration inputDecoration({
      required String labelText,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: labelText,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.black.withValues(alpha: 0.55),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: _profileDarkText, width: 1.1),
        ),
        suffixIcon: suffixIcon,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            initialValue: widget.title,
            readOnly: true,
            showCursor: false,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _profileDarkText,
            ),
            decoration: inputDecoration(labelText: 'Document'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: fileName.isNotEmpty ? fileName : 'Unavailable',
            readOnly: true,
            showCursor: false,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _profileDarkText,
            ),
            decoration: inputDecoration(labelText: 'File name'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: canOpen ? _openDoc : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activityButtonYellow,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CompositedTransformTarget(
                  link: _verifiedFieldLink,
                  child: TextFormField(
                    key: _verifiedFieldKey,
                    controller: _verifiedFieldController,
                    readOnly: true,
                    showCursor: false,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _profileDarkText,
                    ),
                    decoration: inputDecoration(
                      labelText: 'Verified',
                      suffixIcon: const Icon(Icons.expand_more, size: 18),
                    ),
                    onTap: (widget.disabled || doc == null)
                        ? null
                        : _toggleVerifiedMenu,
                  ),
                ),
              ),
            ],
          ),
          if (doc != null && verifiedNow != _verified) const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.black.withValues(alpha: 0.50),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value.trim().isNotEmpty ? value.trim() : '-',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _profileDarkText,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard({
    required this.stream,
    required this.caregiverId,
    required this.canVerify,
    this.wrapInCard = true,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>>? stream;
  final String caregiverId;
  final bool canVerify;
  final bool wrapInCard;

  Widget _shell({required Widget child}) {
    if (!wrapInCard) return child;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Future<void> _openDocument(BuildContext context, String url) async {
    if (url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No document link available.')),
      );
      return;
    }
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the document.')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the document.')),
      );
    }
  }

  Future<void> _verifyDocument(
    BuildContext context,
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      await ref.set({
        'status': true,
        'verifiedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _maybeApproveCaregiver(caregiverId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Document verified.')));
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to verify document. Please try again.'),
        ),
      );
    }
  }

  Future<void> _maybeApproveCaregiver(String caregiverId) async {
    final uid = caregiverId.trim();
    if (uid.isEmpty) return;
    final db = FirebaseFirestore.instance;

    double? safeDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String && value.trim().isNotEmpty) {
        return double.tryParse(value.trim());
      }
      return null;
    }

    final pending = await db
        .collection('documents')
        .where('caregiverId', isEqualTo: uid)
        .where('status', isEqualTo: false)
        .limit(1)
        .get();
    if (pending.docs.isNotEmpty) return;

    final waitingRef = db.collection('waitinglist').doc(uid);
    final waitingSnap = await waitingRef.get();
    final waitingData = waitingSnap.data();
    if (!waitingSnap.exists || waitingData == null) return;
    if ((waitingData['verified'] as bool?) == true) {
      // Already migrated once. Ensure the caregiver doc exists and role is correct.
      await db.collection('caregivers').doc(uid).set({
        'forceLogoutAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await waitingRef.delete().catchError((_) {});
      await db.collection('users').doc(uid).delete().catchError((_) {});
      return;
    }

    final caregiverRef = db.collection('caregivers').doc(uid);
    final userRef = db.collection('users').doc(uid);
    final userSnap = await userRef.get();
    final userData = userSnap.data();
    final caregiverPayload = <String, dynamic>{
      'caregiverId': uid,
      'role': 'caregiver',
      'name': (waitingData['name'] as String?)?.trim() ?? '',
      'email':
          (waitingData['email'] as String?)?.trim() ??
          (userData?['email'] as String?)?.toString().trim() ??
          '',
      'phone':
          (waitingData['phone'] as String?)?.trim() ??
          (userData?['phone'] as String?)?.toString().trim() ??
          '',
      'defaultAddress': (waitingData['defaultAddress'] as String?)?.trim(),
      if (safeDouble(waitingData['lat']) != null)
        'lat': safeDouble(waitingData['lat']),
      if (safeDouble(waitingData['lng']) != null)
        'lng': safeDouble(waitingData['lng']),
      'servicePreferences': waitingData['servicePreferences'] ?? const [],
      'photoUrl': ((userData?['photoUrl'] as String?) ?? '').trim().isNotEmpty
          ? ((userData?['photoUrl'] as String?) ?? '').trim()
          : '',
      'bio': '',
      'certifications': const [],
      'rating': 0.0,
      'jobsCompleted': 0,
      'availability': false,
      'created_at': FieldValue.serverTimestamp(),
      'verifiedAt': FieldValue.serverTimestamp(),
      'forceLogoutAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final paymentDetails = userData?['paymentDetails'];
    if (paymentDetails is Map) {
      caregiverPayload['paymentDetails'] = paymentDetails;
    }
    final fcmToken = (userData?['fcmToken'] as String?)?.trim();
    if (fcmToken != null && fcmToken.isNotEmpty) {
      caregiverPayload['fcmToken'] = fcmToken;
    }
    final lastSeen = userData?['lastSeenPaymentHistoryAt'];
    if (lastSeen is Timestamp) {
      caregiverPayload['lastSeenPaymentHistoryAt'] = lastSeen;
    }
    final dismissed = userData?['dismissedPaymentHistoryNotices'];
    if (dismissed is Iterable) {
      caregiverPayload['dismissedPaymentHistoryNotices'] = dismissed.toList();
    }

    // Avoid redundant data: once approved, remove from waitinglist and keep only
    // the canonical caregiver document (plus the user document for app access).
    final batch = db.batch();
    batch.set(caregiverRef, caregiverPayload, SetOptions(merge: true));
    batch.delete(waitingRef);
    batch.delete(userRef);
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    if (stream == null) {
      return _shell(
        child: const Padding(
          padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Text(
            'No documents found.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _profileDarkText,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                'Unable to load documents.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _profileDarkText,
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? const [];
        if (docs.isEmpty) {
          return _shell(
            child: const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                'No documents uploaded yet.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _profileDarkText,
                ),
              ),
            ),
          );
        }

        const requiredNames = <String>[
          'Selfie with identification card',
          'Identification card (Front)',
          'Identification card (Back)',
        ];
        final byName = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final d in docs) {
          final name = ((d.data()['name'] as String?) ?? '').trim();
          if (name.isEmpty) continue;
          byName[name] = d;
        }
        final orderedDocs = <DocumentSnapshot<Map<String, dynamic>>>[
          for (final name in requiredNames)
            if (byName[name] != null) byName[name]!,
        ];

        Widget docItem(DocumentSnapshot<Map<String, dynamic>> doc) {
          final Map<String, dynamic> docData =
              doc.data() ?? const <String, dynamic>{};
          final url = ((docData['fileUrl'] as String?) ?? '').trim();
          final updatedAtTs = docData['updatedAt'] as Timestamp?;
          return Column(
            children: [
              _DocumentRow(
                title: ((docData['name'] as String?) ?? 'Document').trim(),
                fileName: ((docData['fileName'] as String?) ?? '').trim(),
                updatedAt: updatedAtTs == null
                    ? ''
                    : _dateFormat.format(updatedAtTs.toDate()),
                verified: (docData['status'] as bool?) == true,
                onOpen: url.isEmpty ? null : () => _openDocument(context, url),
                onVerify: (!canVerify || (docData['status'] as bool?) == true)
                    ? null
                    : () => _verifyDocument(context, doc.reference),
              ),
              const SizedBox(height: 10),
            ],
          );
        }

        return _shell(
          child: Padding(
            padding: wrapInCard
                ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
                : EdgeInsets.zero,
            child: Column(
              children: [for (final doc in orderedDocs) docItem(doc)],
            ),
          ),
        );
      },
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.title,
    required this.fileName,
    required this.updatedAt,
    required this.verified,
    required this.onOpen,
    required this.onVerify,
  });

  final String title;
  final String fileName;
  final String updatedAt;
  final bool verified;
  final VoidCallback? onOpen;
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    final statusLabel = verified ? 'Verified' : 'Pending';
    final statusColor = verified ? _primaryBlue : const Color(0xFFF4B63D);
    final statusIcon = verified
        ? Icons.check_circle_rounded
        : Icons.pending_actions_rounded;

    IconData leadingIcon() {
      final t = title.toLowerCase();
      if (t.contains('selfie')) return Icons.camera_alt_outlined;
      if (t.contains('front')) return Icons.credit_card_outlined;
      if (t.contains('back')) return Icons.credit_card_rounded;
      return Icons.description_outlined;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  leadingIcon(),
                  size: 18,
                  color: Colors.black.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: _profileDarkText,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade400),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 5),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        color: Colors.black.withValues(alpha: 0.80),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            ),
            child: Column(
              children: [
                _InfoRow(label: 'File name', value: fileName),
                Divider(
                  height: 14,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
                _InfoRow(label: 'Updated at', value: updatedAt),
                Divider(
                  height: 14,
                  thickness: 1,
                  color: Colors.black.withValues(alpha: 0.06),
                ),
                _InfoRow(label: 'Status', value: statusLabel),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onOpen,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: activityButtonYellow,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
              if (onVerify != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onVerify,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    child: const Text('Verify'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
