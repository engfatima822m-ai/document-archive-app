import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/print_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() =>
      _RemindersScreenState();
}

class _RemindersScreenState
    extends State<RemindersScreen> {
  final List<ReminderItem> _reminders = [];
  final Set<String> _clearingItems = {};

  bool _isLoading = true;
  bool _isOpeningPdf = false;

  String? _errorMessage;

  int _currentPage = 1;
  int _totalPages = 1;
  int _totalItems = 0;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  Future<void> _loadReminders({
    int page = 1,
    bool showLoading = true,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await ApiService.getJson(
        'get_reminders.php',
        queryParameters: {
          'page': page.toString(),
          'per_page': '25',
        },
      );

      final rawReminders = response['reminders'];
      final pagination = response['pagination'];

      final reminders = <ReminderItem>[];

      if (rawReminders is List) {
        for (final item in rawReminders) {
          if (item is Map) {
            reminders.add(
              ReminderItem.fromJson(
                Map<String, dynamic>.from(item),
              ),
            );
          }
        }
      }

      var currentPage = page;
      var totalPages = 1;
      var totalItems = reminders.length;

      if (pagination is Map) {
        final paginationMap =
            Map<String, dynamic>.from(pagination);

        currentPage = _parseInt(
          paginationMap['page'],
          fallback: page,
        );

        totalPages = _parseInt(
          paginationMap['total_pages'],
          fallback: 1,
        );

        totalItems = _parseInt(
          paginationMap['total_items'],
          fallback: reminders.length,
        );
      }

      if (!mounted) return;

      setState(() {
        _reminders
          ..clear()
          ..addAll(reminders);

        _currentPage = currentPage;
        _totalPages = totalPages < 1 ? 1 : totalPages;
        _totalItems = totalItems;
        _isLoading = false;
        _errorMessage = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage =
            'تعذر تحميل التنبيهات. تأكد من تشغيل XAMPP ثم حاول مجددًا.';
      });
    }
  }

  Future<void> _refresh() async {
    await _loadReminders(
      page: _currentPage,
      showLoading: false,
    );
  }

  Future<void> _openPdf(
    ReminderItem reminder,
  ) async {
    if (!reminder.hasPdf || _isOpeningPdf) {
      return;
    }

    setState(() {
      _isOpeningPdf = true;
    });

    try {
      final Uint8List pdfBytes =
          await ApiService.getPdfBytes(
        id: reminder.id,
        recordType: reminder.recordType,
      );

      if (!mounted) return;
      await PrintService.printPdf(
        context,
        bytes: pdfBytes,
        name: '${reminder.documentNumber}.pdf',
      );
    } on ApiException catch (error) {
      _showMessage(
        error.message,
        isError: true,
      );
    } catch (_) {
      _showMessage(
        'تعذر تنفيذ الطباعة.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningPdf = false;
        });
      }
    }
  }

  Future<void> _clearReminder(
    ReminderItem reminder,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('إنهاء التنبيه'),
          content: Text(
            'هل تريد إزالة التنبيه الخاص بالملف '
            '"${reminder.documentNumber}"؟\n\n'
            'لن يتم حذف الملف أو بياناته، وإنما سيتم حذف التنبيه فقط.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text('إزالة التنبيه'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final itemKey = reminder.itemKey;

    if (_clearingItems.contains(itemKey)) {
      return;
    }

    setState(() {
      _clearingItems.add(itemKey);
    });

    try {
      await ApiService.postJson(
        'clear_reminder.php',
        {
          'id': reminder.id,
          'record_type': reminder.recordType,
          'version': reminder.version,
        },
      );

      _showMessage(
        'تم إنهاء التنبيه بنجاح.',
      );

      final targetPage =
          _reminders.length == 1 &&
                  _currentPage > 1
              ? _currentPage - 1
              : _currentPage;

      await _loadReminders(
        page: targetPage,
        showLoading: false,
      );
    } on ApiException catch (error) {
      _showMessage(
        error.message,
        isError: true,
      );
    } catch (_) {
      _showMessage(
        'تعذر إنهاء التنبيه.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _clearingItems.remove(itemKey);
        });
      }
    }
  }

  void _showReminderDetails(
    ReminderItem reminder,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            reminder.documentTitle,
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 520,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailRow(
                    'نوع السجل',
                    reminder.isAttachment
                        ? 'كتاب تابع'
                        : 'ملف رئيسي',
                  ),
                  _detailRow(
                    'رقم الملف',
                    reminder.documentNumber,
                  ),
                  _detailRow(
                    'تاريخ الملف',
                    reminder.documentDate,
                  ),
                  _detailRow(
                    'حالة الملف',
                    reminder.status,
                  ),
                  _detailRow(
                    'تاريخ التنبيه',
                    reminder.reminderDate,
                  ),
                  if (reminder
                      .reminderNote.isNotEmpty)
                    _detailRow(
                      'ملاحظة التنبيه',
                      reminder.reminderNote,
                    ),
                  if (reminder.notes.isNotEmpty)
                    _detailRow(
                      'ملاحظات الملف',
                      reminder.notes,
                    ),
                  if (reminder
                      .parentNumber.isNotEmpty)
                    _detailRow(
                      'رقم الملف الرئيسي',
                      reminder.parentNumber,
                    ),
                  if (reminder
                      .parentTitle.isNotEmpty)
                    _detailRow(
                      'اسم الملف الرئيسي',
                      reminder.parentTitle,
                    ),
                  if (reminder.pageCount > 0)
                    _detailRow(
                      'عدد صفحات PDF',
                      reminder.pageCount.toString(),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text('إغلاق'),
            ),
            if (reminder.hasPdf)
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );

                  _openPdf(reminder);
                },
                icon: const Icon(
                  Icons.picture_as_pdf,
                ),
                label: const Text('طباعة PDF'),
              ),
          ],
        );
      },
    );
  }

  Widget _detailRow(
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF475569),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value.isEmpty ? '—' : value,
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? const Color(0xFFB91C1C)
              : const Color(0xFF047857),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('التنبيهات'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed:
                _isLoading ? null : _refresh,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          Expanded(
            child: _buildBody(),
          ),
          if (!_isLoading &&
              _errorMessage == null &&
              _totalPages > 1)
            _buildPagination(),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        8,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor:
                Color(0xFFDBEAFE),
            child: Icon(
              Icons.notifications_active_outlined,
              color: Color(0xFF1D4ED8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _totalItems == 0
                  ? 'لا توجد تنبيهات حالية'
                  : 'عدد التنبيهات الحالية: $_totalItems',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A8A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 100),
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Color(0xFFB91C1C),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF7F1D1D),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: FilledButton.icon(
                onPressed: () {
                  _loadReminders(
                    page: _currentPage,
                  );
                },
                icon: const Icon(
                  Icons.refresh,
                ),
                label: const Text(
                  'إعادة المحاولة',
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_reminders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 100),
            Icon(
              Icons.notifications_none,
              size: 72,
              color: Color(0xFF64748B),
            ),
            SizedBox(height: 16),
            Text(
              'لا توجد تنبيهات مسجلة حاليًا',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF334155),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'ستظهر هنا الملفات التي تمت إضافة تاريخ تنبيه لها.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          8,
          16,
          20,
        ),
        itemCount: _reminders.length,
        separatorBuilder: (_, _) =>
            const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return _buildReminderCard(
            _reminders[index],
          );
        },
      ),
    );
  }

  Widget _buildReminderCard(
    ReminderItem reminder,
  ) {
    final isClearing = _clearingItems
        .contains(reminder.itemKey);

    final badgeColor = reminder.isOverdue
        ? const Color(0xFFB91C1C)
        : reminder.isDueToday
            ? const Color(0xFFD97706)
            : const Color(0xFF2563EB);

    final badgeBackground =
        reminder.isOverdue
            ? const Color(0xFFFEE2E2)
            : reminder.isDueToday
                ? const Color(0xFFFEF3C7)
                : const Color(0xFFDBEAFE);

    final badgeText = reminder.isOverdue
        ? 'متأخر'
        : reminder.isDueToday
            ? 'اليوم'
            : 'قادم';

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(14),
        side: BorderSide(
          color: reminder.isOverdue
              ? const Color(0xFFFCA5A5)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(14),
        onTap: () {
          _showReminderDetails(
            reminder,
          );
        },
        child: Padding(
          padding:
              const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor:
                        badgeBackground,
                    child: Icon(
                      reminder.isAttachment
                          ? Icons.attachment
                          : Icons
                              .description_outlined,
                      color: badgeColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                          reminder
                              .documentTitle,
                          maxLines: 2,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.bold,
                            color: Color(
                              0xFF0F172A,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        Text(
                          'رقم الملف: ${reminder.documentNumber}',
                          style:
                              const TextStyle(
                            color: Color(
                              0xFF475569,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: badgeBackground,
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        color: badgeColor,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _informationItem(
                    Icons
                        .calendar_today_outlined,
                    'تاريخ الملف: ${reminder.documentDate}',
                  ),
                  _informationItem(
                    Icons.alarm_outlined,
                    'تاريخ التنبيه: ${reminder.reminderDate}',
                  ),
                  _informationItem(
                    reminder.isAttachment
                        ? Icons.attachment
                        : Icons.folder_outlined,
                    reminder.isAttachment
                        ? 'كتاب تابع'
                        : 'ملف رئيسي',
                  ),
                ],
              ),
              if (reminder
                  .parentNumber.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'تابع للملف رقم: ${reminder.parentNumber}',
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
              if (reminder
                  .reminderNote.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(
                    12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFFF8FAFC,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      10,
                    ),
                  ),
                  child: Text(
                    reminder.reminderNote,
                    style: const TextStyle(
                      color: Color(
                        0xFF334155,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      _showReminderDetails(
                        reminder,
                      );
                    },
                    icon: const Icon(
                      Icons
                          .visibility_outlined,
                    ),
                    label:
                        const Text('التفاصيل'),
                  ),
                  if (reminder.hasPdf)
                    OutlinedButton.icon(
                      onPressed: _isOpeningPdf
                          ? null
                          : () {
                              _openPdf(
                                reminder,
                              );
                            },
                      icon: const Icon(
                        Icons
                            .picture_as_pdf_outlined,
                      ),
                      label: const Text(
                        'طباعة PDF',
                      ),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: isClearing
                        ? null
                        : () {
                            _clearReminder(
                              reminder,
                            );
                          },
                    icon: isClearing
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons
                                .notifications_off_outlined,
                          ),
                    label: const Text(
                      'إنهاء التنبيه',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _informationItem(
    IconData icon,
    String text,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color: const Color(0xFF64748B),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF475569),
          ),
        ),
      ],
    );
  }

  Widget _buildPagination() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(
              color: Color(0xFFE2E8F0),
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: _currentPage > 1
                  ? () {
                      _loadReminders(
                        page: _currentPage - 1,
                      );
                    }
                  : null,
              icon: const Icon(
                Icons.arrow_forward,
              ),
              label: const Text('السابق'),
            ),
            Text(
              'الصفحة $_currentPage من $_totalPages',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF334155),
              ),
            ),
            OutlinedButton.icon(
              onPressed:
                  _currentPage < _totalPages
                      ? () {
                          _loadReminders(
                            page:
                                _currentPage +
                                    1,
                          );
                        }
                      : null,
              icon: const Icon(
                Icons.arrow_back,
              ),
              label: const Text('التالي'),
            ),
          ],
        ),
      ),
    );
  }
}

class ReminderItem {
  final int id;
  final String recordType;
  final String documentNumber;
  final String documentDate;
  final String documentTitle;
  final String notes;
  final String status;
  final String reminderDate;
  final String reminderNote;
  final bool isOverdue;
  final bool isDueToday;
  final bool hasPdf;
  final int pageCount;
  final int pdfSizeBytes;
  final int version;
  final String parentNumber;
  final String parentTitle;

  const ReminderItem({
    required this.id,
    required this.recordType,
    required this.documentNumber,
    required this.documentDate,
    required this.documentTitle,
    required this.notes,
    required this.status,
    required this.reminderDate,
    required this.reminderNote,
    required this.isOverdue,
    required this.isDueToday,
    required this.hasPdf,
    required this.pageCount,
    required this.pdfSizeBytes,
    required this.version,
    required this.parentNumber,
    required this.parentTitle,
  });

  bool get isAttachment =>
      recordType == 'attachment';

  String get itemKey =>
      '$recordType-$id';

  factory ReminderItem.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawParent = json['parent'];

    String parentNumber = '';
    String parentTitle = '';

    if (rawParent is Map) {
      final parent =
          Map<String, dynamic>.from(
        rawParent,
      );

      parentNumber =
          (parent['document_number'] ?? '')
              .toString();

      parentTitle =
          (parent['document_title'] ?? '')
              .toString();
    }

    return ReminderItem(
      id: _parseInt(json['id']),
      recordType:
          (json['record_type'] ?? 'main')
              .toString(),
      documentNumber:
          (json['document_number'] ?? '')
              .toString(),
      documentDate:
          (json['document_date'] ?? '')
              .toString(),
      documentTitle:
          (json['document_title'] ?? '')
              .toString(),
      notes:
          (json['notes'] ?? '').toString(),
      status:
          (json['status'] ?? 'قيد الإنجاز')
              .toString(),
      reminderDate:
          (json['reminder_date'] ?? '')
              .toString(),
      reminderNote:
          (json['reminder_note'] ?? '')
              .toString(),
      isOverdue:
          _parseBool(json['is_overdue']),
      isDueToday:
          _parseBool(json['is_due_today']),
      hasPdf: _parseBool(json['has_pdf']),
      pageCount:
          _parseInt(json['page_count']),
      pdfSizeBytes:
          _parseInt(json['pdf_size_bytes']),
      version: _parseInt(
        json['version'],
        fallback: 1,
      ),
      parentNumber: parentNumber,
      parentTitle: parentTitle,
    );
  }
}

int _parseInt(
  dynamic value, {
  int fallback = 0,
}) {
  if (value is int) {
    return value;
  }

  return int.tryParse(
        value?.toString() ?? '',
      ) ??
      fallback;
}

bool _parseBool(dynamic value) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final normalized = value
      ?.toString()
      .trim()
      .toLowerCase();

  return normalized == 'true' ||
      normalized == '1' ||
      normalized == 'yes';
}