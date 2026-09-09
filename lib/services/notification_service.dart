import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || !Platform.isWindows) return;

    final windowsSettings = WindowsInitializationSettings(
      appName: 'نظام أرشفة الملفات',
      appUserModelId: 'Iraq.OPDC.DocumentArchive',
      guid: '6d64ba82-52b8-4f44-92eb-10cc68c76847',
    );

    final initializationSettings = InitializationSettings(
      windows: windowsSettings,
    );

    await _notifications.initialize(
      settings: initializationSettings,
    );

    _initialized = true;
  }

  Future<void> showTestNotification() async {
    if (!Platform.isWindows) return;

    await initialize();

    const notificationDetails = NotificationDetails(
      windows: WindowsNotificationDetails(
        subtitle: 'اختبار نظام التنبيهات',
      ),
    );
await _notifications.show(
  id: 1,
  title: 'نظام أرشفة الملفات',
  body: 'تم تفعيل إشعارات التذكير بنجاح',
  notificationDetails: notificationDetails,
);
  }

  Future<void> showReminderNotification({
    required int id,
    required String documentNumber,
    required String documentTitle,
    String? reminderNote,
  }) async {
    if (!Platform.isWindows) return;

    await initialize();

    const notificationDetails = NotificationDetails(
      windows: WindowsNotificationDetails(
        subtitle: 'تذكير بمتابعة ملف',
      ),
    );

    final note = reminderNote?.trim();

    final body = [
      'رقم الملف: $documentNumber',
      'العنوان: $documentTitle',
      if (note != null && note.isNotEmpty) 'الملاحظة: $note',
    ].join('\n');

   await _notifications.show(
  id: id,
  title: 'تذكير مستحق',
  body: body,
  notificationDetails: notificationDetails,
  payload: id.toString(),
);
  }
}