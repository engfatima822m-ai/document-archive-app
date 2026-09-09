import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/document_model.dart';
import 'notification_service.dart';

class ReminderService {
  ReminderService({String? apiBaseUrl})
      : apiBaseUrl = apiBaseUrl ?? _defaultApiBaseUrl;

  final String apiBaseUrl;

  // منع تكرار الإشعار خلال جلسة التشغيل نفسها.
  final Set<String> _notifiedThisSession = <String>{};

  static String get _defaultApiBaseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2/document_api';
    }

    // نفس الرابط المستخدم حاليًا في التطبيق.
    return 'http://localhost/document_api';
  }

  Future<List<DocumentModel>> getDueReminders() async {
    final uri = Uri.parse('$apiBaseUrl/get_documents.php');

    final response = await http.get(uri).timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
        'فشل الاتصال بالخادم، رمز الخطأ: ${response.statusCode}',
      );
    }

    final dynamic decodedData = jsonDecode(response.body);

    if (decodedData is! Map<String, dynamic>) {
      throw Exception('استجابة الخادم غير صحيحة');
    }

    if (decodedData['success'] != true) {
      throw Exception(
        decodedData['message']?.toString() ?? 'فشل جلب التذكيرات',
      );
    }

    final dynamic documentsData = decodedData['documents'];

    if (documentsData is! List) {
      return [];
    }

    final allDocuments = documentsData
        .whereType<Map>()
        .map(
          (item) => DocumentModel.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();

    final dueReminders = allDocuments.where((document) {
      return isReminderDue(document.reminderDate);
    }).toList();

    dueReminders.sort((first, second) {
      final firstDate = _parseDate(first.reminderDate);
      final secondDate = _parseDate(second.reminderDate);

      return firstDate.compareTo(secondDate);
    });

    return dueReminders;
  }

  /// يجلب التذكيرات المستحقة ويرسلها إلى إشعارات Windows.
  Future<int> showDueReminderNotifications() async {
    if (!Platform.isWindows) {
      return 0;
    }

    final dueReminders = await getDueReminders();
    final notificationLog = await _readNotificationLog();
    final todayKey = _formatDate(DateTime.now());

    int shownNotifications = 0;

    for (final document in dueReminders) {
      final reminderKey = _createReminderKey(document);

      // لا نكرر الإشعار خلال جلسة التشغيل نفسها.
      if (_notifiedThisSession.contains(reminderKey)) {
        continue;
      }

      // لا نكرر إشعار الملف نفسه أكثر من مرة في اليوم.
      if (notificationLog[reminderKey] == todayKey) {
        _notifiedThisSession.add(reminderKey);
        continue;
      }

      await NotificationService.instance.showReminderNotification(
        id: _createNotificationId(reminderKey),
        documentNumber: document.documentNumber,
        documentTitle: document.documentTitle,
        reminderNote: document.reminderNote,
      );

      _notifiedThisSession.add(reminderKey);
      notificationLog[reminderKey] = todayKey;
      shownNotifications++;
    }

    if (shownNotifications > 0) {
      await _saveNotificationLog(notificationLog);
    }

    return shownNotifications;
  }

  bool isReminderDue(String? reminderDateValue) {
    if (reminderDateValue == null ||
        reminderDateValue.trim().isEmpty) {
      return false;
    }

    final reminderDate = DateTime.tryParse(
      reminderDateValue.trim(),
    );

    if (reminderDate == null) {
      return false;
    }

    final now = DateTime.now();

    final todayOnly = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final reminderOnly = DateTime(
      reminderDate.year,
      reminderDate.month,
      reminderDate.day,
    );

    // التذكير مستحق إذا كان تاريخه اليوم أو تاريخًا سابقًا.
    return !reminderOnly.isAfter(todayOnly);
  }

  DateTime _parseDate(String? dateValue) {
    if (dateValue == null || dateValue.trim().isEmpty) {
      return DateTime(2100);
    }

    return DateTime.tryParse(dateValue.trim()) ?? DateTime(2100);
  }

  String _createReminderKey(DocumentModel document) {
    final documentId = document.id?.toString() ??
        document.documentNumber.trim();

    return '${document.recordType}_$documentId';
  }

  int _createNotificationId(String value) {
    int hash = 0;

    for (final codeUnit in value.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }

    // الرقم 1 مستخدم للإشعار التجريبي.
    return hash == 0 || hash == 1 ? hash + 2 : hash;
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  File _getNotificationLogFile() {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final basePath = localAppData != null && localAppData.isNotEmpty
        ? localAppData
        : Directory.systemTemp.path;

    final directory = Directory(
      '$basePath${Platform.pathSeparator}DocumentArchive',
    );

    return File(
      '${directory.path}${Platform.pathSeparator}'
      'reminder_notification_log.json',
    );
  }

  Future<Map<String, String>> _readNotificationLog() async {
    try {
      final file = _getNotificationLogFile();

      if (!await file.exists()) {
        return <String, String>{};
      }

      final decodedData = jsonDecode(await file.readAsString());

      if (decodedData is! Map) {
        return <String, String>{};
      }

      return decodedData.map(
        (key, value) => MapEntry(
          key.toString(),
          value.toString(),
        ),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _saveNotificationLog(
    Map<String, String> notificationLog,
  ) async {
    try {
      final file = _getNotificationLogFile();

      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(notificationLog),
        flush: true,
      );
    } catch (_) {
      // فشل حفظ سجل منع التكرار لا يوقف التطبيق.
    }
  }
}