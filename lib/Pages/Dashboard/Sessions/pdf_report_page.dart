import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:qcur_evaluation/Services/app_cache.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class PdfReportPage extends StatefulWidget {
  final String sessionId;
  final String sessionName;

  const PdfReportPage({
    super.key,
    required this.sessionId,
    required this.sessionName,
  });

  @override
  State<PdfReportPage> createState() => _PdfReportPageState();
}

class _PdfReportPageState extends State<PdfReportPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _activities = [];
  bool _isLoading = true;
  bool _isGenerating = false;

  // activityId → selected
  final Map<String, bool> _selected = {};

  @override
  void initState() {
    super.initState();
    _fetchActivities();
  }

  Future<void> _fetchActivities() async {
    setState(() => _isLoading = true);
    try {
      final key = 'acts:${widget.sessionId}';
      final cached = AppCache.instance.get<List<dynamic>>(key);
      final data = cached ??
          await _supabase
              .from('activities')
              .select('*')
              .eq('session_id', widget.sessionId)
              .order('order_index');
      if (cached == null) AppCache.instance.set(key, data);

      final list = List<Map<String, dynamic>>.from(data);
      for (final a in list) { _selected[a['id'] as String] = true; }
      setState(() {
        _activities = list;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  List<Map<String, dynamic>> get _parents =>
      _activities.where((a) => a['parent_id'] == null).toList();

  List<Map<String, dynamic>> _subsFor(String pid) =>
      _activities.where((a) => a['parent_id'] == pid).toList();

  bool get _hasSelection => _selected.values.any((v) => v);

  int get _selectedCount => _selected.values.where((v) => v).length;

  void _toggleParent(String pid, bool value) => setState(() {
        _selected[pid] = value;
        for (final s in _subsFor(pid)) { _selected[s['id'] as String] = value; }
      });

  Future<void> _generate() async {
    setState(() => _isGenerating = true);
    Uint8List? bytes;
    String? filename;
    try {
      bytes = await _buildPdfBytes();
      filename = '${widget.sessionName.replaceAll(RegExp(r'\s+'), '_')}_report.pdf';
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error generating PDF: $e')));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }

    if (bytes != null && filename != null && mounted) {
      _showExportSheet(bytes, filename);
    }
  }

  Future<Uint8List?> _buildPdfBytes() async {
    // Fetch all session trainees with their roles
    final stData = await _supabase
        .from('session_trainees')
        .select('trainees!inner(*, trainee_roles(role_id))')
        .eq('session_id', widget.sessionId);
    final allTrainees = (stData as List)
        .map((m) => m['trainees'] as Map<String, dynamic>)
        .toList()
      ..sort((a, b) => a['full_name'].toString().compareTo(b['full_name'].toString()));

    // Collect which activity IDs to fetch scores for
    final idsToFetch = <String>[];
    for (final p in _parents) {
      final pid = p['id'] as String;
      final subs = _subsFor(pid);
      if (subs.isEmpty) {
        if (_selected[pid] == true) idsToFetch.add(pid);
      } else {
        for (final s in subs) {
          if (_selected[s['id'] as String] == true) idsToFetch.add(s['id'] as String);
        }
      }
    }
    if (idsToFetch.isEmpty) return null;

    final resultsData = await _supabase
        .from('activity_results')
        .select('activity_id, trainee_id, score')
        .inFilter('activity_id', idsToFetch);

    final scoreMap = <String, Map<String, num>>{};
    for (final r in resultsData as List) {
      final aid = r['activity_id'] as String;
      final tid = r['trainee_id'] as String;
      final score = r['score'];
      if (score != null) {
        scoreMap[aid] ??= {};
        scoreMap[aid]![tid] = score as num;
      }
    }

    final sections = <_PdfSection>[];
    for (final p in _parents) {
      final pid = p['id'] as String;
      final subs = _subsFor(pid);
      final selectedSubs = subs.where((s) => _selected[s['id'] as String] == true).toList();
      final parentDirectlySelected = _selected[pid] == true;

      if (subs.isEmpty && !parentDirectlySelected) continue;
      if (subs.isNotEmpty && selectedSubs.isEmpty) continue;

      final roleId = p['target_role_id'] as String?;
      final trainees = roleId == null
          ? allTrainees
          : allTrainees.where((t) {
              final roles = (t['trainee_roles'] as List?) ?? [];
              return roles.any((r) => r['role_id'] == roleId);
            }).toList();

      sections.add(_PdfSection(
        parent: p,
        subs: selectedSubs,
        trainees: trainees,
        scoreMap: scoreMap,
      ));
    }

    if (sections.isEmpty) return null;

    final maxCols = sections.fold(0, (m, s) => s.subs.length > m ? s.subs.length : m);
    final pageFormat = maxCols > 4 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => _buildPdfHeader(),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
        ),
      ),
      build: (ctx) {
        final widgets = <pw.Widget>[];
        for (int i = 0; i < sections.length; i++) {
          if (i > 0) widgets.add(pw.SizedBox(height: 18));
          widgets.add(sections[i].build());
        }
        return widgets;
      },
    ));

    return doc.save();
  }

  void _showExportSheet(Uint8List bytes, String filename) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadius)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(kPadding, 16, kPadding, kPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kForegroundDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(kRadiusSmall),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: kAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('PDF Ready', style: AppTypography.h3),
                        Text(filename, style: AppTypography.caption.copyWith(fontSize: 11, color: kForegroundMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1, color: kBorder),
              const SizedBox(height: 16),
              _exportOption(
                icon: Icons.download_rounded,
                label: 'Download',
                subtitle: 'Save PDF to your device',
                color: kInfo,
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _exportPdf(bytes, filename, isDownload: true);
                },
              ),
              const SizedBox(height: 10),
              _exportOption(
                icon: Icons.share_rounded,
                label: 'Share',
                subtitle: 'Send via apps or email',
                color: kAccent,
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  _exportPdf(bytes, filename, isDownload: false);
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _exportOption({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(kRadius),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(kRadiusSmall),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 14, color: color)),
                  Text(subtitle, style: AppTypography.caption.copyWith(fontSize: 11, color: kForegroundMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf(Uint8List bytes, String filename, {required bool isDownload}) async {
    try {
      if (isDownload) {
        // saveAs opens the system "Save to..." picker so the file lands in a
        // user-visible location (Downloads, Documents, Drive, etc.) and returns
        // the chosen path. saveFile() would write to app-private external
        // storage (Android/data/...) which file managers hide — so we avoid it.
        final path = await FileSaver.instance.saveAs(
          name: filename.replaceAll('.pdf', ''),
          bytes: bytes,
          ext: 'pdf',
          mimeType: MimeType.pdf,
        );
        // Null/empty means the user cancelled the picker — stay silent.
        if (path == null || path.isEmpty) return;
        if (mounted) _showSuccessDialog(isDownload: true, path: path);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: filename);
        if (mounted) _showSuccessDialog(isDownload: false);
      }
    } catch (e, stackTrace) {
      await Sentry.captureException(e, stackTrace: stackTrace);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  void _showSuccessDialog({required bool isDownload, String? path}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: kAccent, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              isDownload ? 'Download Complete' : 'Shared Successfully',
              style: AppTypography.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isDownload
                  ? 'Your PDF report has been saved to your device.'
                  : 'Your PDF report has been shared.',
              style: AppTypography.body.copyWith(color: kForegroundMuted, height: 1.5),
              textAlign: TextAlign.center,
            ),
            if (isDownload && path != null && path.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: kSurfaceElevated.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(kRadiusSmall),
                  border: Border.all(color: kBorder.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SAVED TO', style: AppTypography.label.copyWith(fontSize: 9, color: kAccent)),
                    const SizedBox(height: 4),
                    Text(
                      path,
                      style: AppTypography.caption.copyWith(fontSize: 10, color: kForegroundMuted),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            AppButton(
              label: 'Done',
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildPdfHeader() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              widget.sessionName,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Score Report',
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Generated ${DateFormat('MMM d, y · h:mm a').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        pw.SizedBox(height: 4),
      ],
    );
  }

  // ---------- Flutter UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: kPadding,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.sessionName.toUpperCase(), style: AppTypography.overline.copyWith(color: kForegroundMuted)),
            const Text('Generate PDF Report', style: AppTypography.h3),
          ],
        ),
      ),
      body: Stack(
        children: [
          const TechnicalGridBackground(),
          if (_isLoading)
            const AppLoader()
          else
            SafeArea(
              child: ResponsiveContainer(
                maxWidth: kMaxWidthContent,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(kPadding),
                        children: [
                          _buildSelectionHeader(),
                          const SizedBox(height: 12),
                          if (_activities.isEmpty)
                            const AppEmptyState(
                              icon: Icons.assignment_outlined,
                              title: 'No Activities',
                              message: 'This session has no activities to report on yet.',
                            )
                          else
                            ..._parents.map(_buildParentItem),
                        ],
                      ),
                    ),
                    if (_activities.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(kPadding),
                        child: AppButton(
                          label: 'Generate & Share PDF',
                          icon: Icons.picture_as_pdf_rounded,
                          isLoading: _isGenerating,
                          onTap: (_hasSelection && !_isGenerating) ? _generate : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionHeader() {
    final total = _activities.length;
    final sel = _selectedCount;
    final allSelected = sel == total && total > 0;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(kRadiusSmall),
            ),
            child: const Icon(Icons.picture_as_pdf_outlined, size: 16, color: kAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select items to include', style: AppTypography.body.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('$sel of $total selected', style: AppTypography.caption.copyWith(fontSize: 11, color: kForegroundMuted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              for (final a in _activities) { _selected[a['id'] as String] = !allSelected; }
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: kAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(kRadiusSmall),
                border: Border.all(color: kAccent.withValues(alpha: 0.3)),
              ),
              child: Text(
                allSelected ? 'Deselect All' : 'Select All',
                style: const TextStyle(color: kAccent, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentItem(Map<String, dynamic> parent) {
    final pid = parent['id'] as String;
    final subs = _subsFor(pid);
    final hasSubs = subs.isNotEmpty;
    final pSelected = _selected[pid] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          color: pSelected ? kAccent.withValues(alpha: 0.05) : kSurface,
          border: Border.all(color: pSelected ? kAccent.withValues(alpha: 0.2) : kBorder.withValues(alpha: 0.4)),
          child: InkWell(
            onTap: () => _toggleParent(pid, !pSelected),
            borderRadius: BorderRadius.circular(kRadius),
            splashColor: kAccent.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _Checkbox(checked: pSelected, size: 20),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.folder_outlined, size: 12, color: kAccent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      parent['name'].toString(),
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: pSelected ? kForeground : kForegroundMuted,
                      ),
                    ),
                  ),
                  if (hasSubs) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: kSurfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${subs.length} sub',
                        style: AppTypography.caption.copyWith(fontSize: 10, color: kForegroundDisabled),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (hasSubs)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 4),
            child: Column(
              children: subs.map((sub) {
                final sid = sub['id'] as String;
                final sSelected = _selected[sid] == true;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    color: sSelected ? kAccent.withValues(alpha: 0.03) : kSurface,
                    border: Border.all(
                      color: sSelected ? kAccent.withValues(alpha: 0.15) : kBorder.withValues(alpha: 0.3),
                    ),
                    child: InkWell(
                      onTap: () => setState(() => _selected[sid] = !sSelected),
                      borderRadius: BorderRadius.circular(kRadius),
                      splashColor: kAccent.withValues(alpha: 0.06),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            _Checkbox(checked: sSelected, size: 18),
                            const SizedBox(width: 10),
                            const Icon(Icons.subdirectory_arrow_right_rounded, size: 13, color: kForegroundDisabled),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                sub['name'].toString(),
                                style: AppTypography.body.copyWith(
                                  fontSize: 12,
                                  color: sSelected ? kForeground : kForegroundMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ---------- Animated checkbox ----------

class _Checkbox extends StatelessWidget {
  final bool checked;
  final double size;

  const _Checkbox({required this.checked, required this.size});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: checked ? kAccent : Colors.transparent,
        borderRadius: BorderRadius.circular(size * 0.2),
        border: Border.all(color: checked ? kAccent : kBorder, width: 1.5),
      ),
      child: checked
          ? Icon(Icons.check_rounded, size: size * 0.65, color: Colors.white)
          : null,
    );
  }
}

// ---------- PDF section model ----------

class _PdfSection {
  final Map<String, dynamic> parent;
  final List<Map<String, dynamic>> subs;
  final List<Map<String, dynamic>> trainees;
  final Map<String, Map<String, num>> scoreMap;

  const _PdfSection({
    required this.parent,
    required this.subs,
    required this.trainees,
    required this.scoreMap,
  });

  pw.Widget build() {
    final hasSubs = subs.isNotEmpty;
    final parentId = parent['id'] as String;
    final direction = parent['scoring_direction'] as String? ?? 'higher_is_better';
    final dirLabel = hasSubs
        ? 'Aggregate (raw sub-scores)'
        : (direction == 'higher_is_better' ? 'Higher is Better' : 'Lower is Better');

    // Sort trainees by rank — scored first, then unscored alphabetically
    final ranked = List<Map<String, dynamic>>.from(trainees);
    if (hasSubs) {
      ranked.sort((a, b) {
        final aid = a['id'] as String;
        final bid = b['id'] as String;
        final aHas = subs.any((s) => scoreMap[s['id'] as String]?.containsKey(aid) == true);
        final bHas = subs.any((s) => scoreMap[s['id'] as String]?.containsKey(bid) == true);
        if (!aHas && !bHas) return a['full_name'].toString().compareTo(b['full_name'].toString());
        if (!aHas) return 1;
        if (!bHas) return -1;
        final aSum = subs.fold<double>(0, (s, sub) => s + (scoreMap[sub['id'] as String]?[aid]?.toDouble() ?? 0));
        final bSum = subs.fold<double>(0, (s, sub) => s + (scoreMap[sub['id'] as String]?[bid]?.toDouble() ?? 0));
        return bSum.compareTo(aSum); // higher raw sum = better rank
      });
    } else {
      ranked.sort((a, b) {
        final aScore = scoreMap[parentId]?[a['id'] as String];
        final bScore = scoreMap[parentId]?[b['id'] as String];
        if (aScore == null && bScore == null) return a['full_name'].toString().compareTo(b['full_name'].toString());
        if (aScore == null) return 1;
        if (bScore == null) return -1;
        return direction == 'higher_is_better'
            ? bScore.compareTo(aScore)
            : aScore.compareTo(bScore);
      });
    }

    final headers = <String>['#', 'Trainee Name'];
    if (hasSubs) {
      headers.addAll(subs.map((s) => s['name'].toString()));
    } else {
      headers.add('Score');
    }

    final rows = ranked.asMap().entries.map((e) {
      final t = e.value;
      final tid = t['id'] as String;
      final row = <String>['${e.key + 1}', t['full_name'].toString()];
      if (hasSubs) {
        for (final s in subs) {
          final score = scoreMap[s['id'] as String]?[tid];
          row.add(score != null ? _fmt(score) : '—');
        }
      } else {
        final score = scoreMap[parentId]?[tid];
        row.add(score != null ? _fmt(score) : '—');
      }
      return row;
    }).toList();

    final colCount = headers.length;
    // Column widths: # narrow, Name wide, score cols equal
    final flexes = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(24),
      1: const pw.FlexColumnWidth(3),
      for (int i = 2; i < colCount; i++) i: pw.FlexColumnWidth(hasSubs ? 1.6 : 2),
    };

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey200,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  parent['name'].toString(),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(dirLabel, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          columnWidths: flexes,
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: headers
                  .map((h) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                        child: pw.Text(
                          h,
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                          maxLines: 3,
                        ),
                      ))
                  .toList(),
            ),
            ...rows.asMap().entries.map(
                  (entry) => pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: entry.key % 2 == 0 ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: entry.value
                        .map((cell) => pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                              child: pw.Text(cell, style: const pw.TextStyle(fontSize: 8)),
                            ))
                        .toList(),
                  ),
                ),
          ],
        ),
      ],
    );
  }

  String _fmt(num n) {
    if (n == n.truncate()) return n.toInt().toString();
    return n.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }
}
