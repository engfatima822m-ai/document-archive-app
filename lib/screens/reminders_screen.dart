import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/document_model.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _isLoading = false;
  bool _hasChanges = false;

  List<DocumentModel> _dueReminders = [];

  final Color bgColor = const Color(0xFFEAF6FF);
  final Color cardColor = const Color(0xFFFFFFFF);
  final Color accentColor = const Color(0xFF1976D2);
  final Color accentLightColor = const Color(0xFF5CB6FF);
  final Color accentDarkColor = const Color(0xFF0D47A1);
  final Color darkColor = const Color(0xFF0D47A1);
  final Color softTextColor = const Color(0xFF5F7FA6);
  final Color borderColor = const Color(0xFFB8D9F7);

  String get _apiBaseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2/document_api';
    }
    return 'http://localhost/document_api';
  }

  LinearGradient get _mainGradient => LinearGradient(
        colors: [accentColor, accentLightColor],
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
      );

  LinearGradient get _softGradient => const LinearGradient(
        colors: [
          Color(0xFFF8FCFF),
          Color(0xFFEAF6FF),
        ],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      );

  @override
  void initState() {
    super.initState();
    _loadDueReminders();
  }

  bool _isReminderDue(String? reminderDateStr) {
    if (reminderDateStr == null || reminderDateStr.trim().isEmpty) {
      return false;
    }

    final reminderDate = DateTime.tryParse(reminderDateStr.trim());
    if (reminderDate == null) {
      return false;
    }

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final reminderOnly =
        DateTime(reminderDate.year, reminderDate.month, reminderDate.day);

    return !reminderOnly.isAfter(todayOnly);
  }

  Future<void> _loadDueReminders() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final uri = Uri.parse('$_apiBaseUrl/get_documents.php');
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('فشل الاتصال بالخادم');
      }

      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'فشل جلب التنبيهات');
      }

      final List docs = data['documents'] ?? [];

      final allDocuments = docs
          .map((item) => DocumentModel.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList();

      final dueReminders = allDocuments.where((doc) {
        return _isReminderDue(doc.reminderDate);
      }).toList();

      dueReminders.sort((a, b) {
        final aDate =
            DateTime.tryParse(a.reminderDate ?? '') ?? DateTime(2100, 1, 1);
        final bDate =
            DateTime.tryParse(b.reminderDate ?? '') ?? DateTime(2100, 1, 1);
        return aDate.compareTo(bDate);
      });

      if (!mounted) return;

      setState(() {
        _dueReminders = dueReminders;
      });
    } catch (e) {
      if (!mounted) return;
      _showMessage('حدث خطأ أثناء تحميل التنبيهات: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _clearReminder(DocumentModel doc) async {
    if (doc.id == null) {
      _showMessage('لا يمكن إخفاء التنبيه لأن رقم السجل غير موجود',
          isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final uri = Uri.parse('$_apiBaseUrl/clear_reminder.php');

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'id': doc.id,
          'record_type': doc.recordType,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('فشل الاتصال بالخادم');
      }

      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'فشل إخفاء التنبيه');
      }

      _hasChanges = true;

      setState(() {
        _dueReminders.removeWhere(
          (item) => item.id == doc.id && item.recordType == doc.recordType,
        );
      });

      _showMessage('تمت المتابعة وإخفاء التنبيه بنجاح');
    } catch (e) {
      _showMessage('حدث خطأ أثناء إخفاء التنبيه: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _openDocumentDetails(DocumentModel doc) {
    Navigator.pop(context, {
      'changed': _hasChanges,
      'document': doc,
    });
  }

  void _goBack() {
    Navigator.pop(context, {
      'changed': _hasChanges,
      'document': null,
    });
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.right),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      decoration: BoxDecoration(
        gradient: _softGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'رجوع',
            onPressed: _goBack,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.92),
              foregroundColor: accentColor,
              padding: const EdgeInsets.all(12),
            ),
            icon: const Icon(Icons.arrow_back_rounded, size: 26),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'تحديث التنبيهات',
            onPressed: _isLoading ? null : _loadDueReminders,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.92),
              foregroundColor: accentColor,
              padding: const EdgeInsets.all(12),
            ),
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded, size: 26),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'لوحة التنبيهات',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: darkColor,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _dueReminders.isEmpty
                    ? 'لا توجد تذكيرات مستحقة حاليًا'
                    : 'عدد التذكيرات المستحقة: ${_dueReminders.length}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: softTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: _mainGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.notifications_active_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none_rounded,
                size: 76,
                color: accentColor.withOpacity(0.7),
              ),
              const SizedBox(height: 16),
              Text(
                'لا توجد تنبيهات حاليًا',
                style: TextStyle(
                  color: darkColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'كل الملفات المتابعة لا تحتوي تذكيرات مستحقة اليوم.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: softTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReminderCard(DocumentModel doc) {
    final isAttachment = doc.status.trim() == 'كتاب تابع';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.05),
            blurRadius: 7,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              gradient: _mainGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isAttachment
                  ? Icons.attach_file_rounded
                  : Icons.folder_copy_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isAttachment
                      ? 'كتاب تابع رقم ${doc.documentNumber}'
                      : 'ملف رقم ${doc.documentNumber}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: darkColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  doc.documentTitle,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: darkColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if ((doc.reminderNote ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    doc.reminderNote!,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: softTextColor,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () => _openDocumentDetails(doc),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('فتح التفاصيل'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accentDarkColor,
                          side: BorderSide(color: borderColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            _isLoading ? null : () => _clearReminder(doc),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('تمت المتابعة'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF7FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  doc.reminderDate ?? '-',
                  style: TextStyle(
                    color: accentDarkColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isAttachment
                      ? const Color(0xFFFFF7E6)
                      : const Color(0xFFEAF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isAttachment ? 'كتاب تابع' : 'ملف رئيسي',
                  style: TextStyle(
                    color: darkColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRemindersList() {
    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 16),
        itemCount: _dueReminders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return _buildReminderCard(_dueReminders[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: WillPopScope(
        onWillPop: () async {
          _goBack();
          return false;
        },
        child: Scaffold(
          backgroundColor: bgColor,
          body: SafeArea(
            child: Container(
              width: double.infinity,
              height: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    bgColor,
                    const Color(0xFFF8FCFF),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
              ),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 14),
                  if (_isLoading && _dueReminders.isEmpty)
                    Expanded(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: accentColor,
                        ),
                      ),
                    )
                  else if (_dueReminders.isEmpty)
                    _buildEmptyState()
                  else
                    _buildRemindersList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}