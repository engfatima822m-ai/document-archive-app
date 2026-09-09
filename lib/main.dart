import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login_screen.dart';
import 'services/notification_service.dart';
import 'services/reminder_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // تشغيل التطبيق أولًا حتى لا يتأثر بأي مشكلة في الاتصال أو الإشعارات.
  runApp(const DocumentArchiveApp());

  // تشغيل الإشعارات وفحص التذكيرات المستحقة بصورة آمنة.
  _startNotificationsSafely();
}

Future<void> _startNotificationsSafely() async {
  try {
    // تهيئة إشعارات Windows.
    await NotificationService.instance.initialize();

    // جلب التذكيرات المستحقة وإظهار إشعاراتها.
    final shownNotifications =
        await ReminderService().showDueReminderNotifications();

    debugPrint(
      'عدد إشعارات التذكير التي ظهرت: $shownNotifications',
    );
  } catch (e) {
    // إذا فشلت الإشعارات أو الاتصال، يستمر التطبيق بالعمل طبيعيًا.
    debugPrint('تعذر تشغيل إشعارات التذكير: $e');
  }
}

class DocumentArchiveApp extends StatelessWidget {
  const DocumentArchiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Document Archive App',
      locale: const Locale('ar'),
      supportedLocales: const [
        Locale('ar'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
      ),

      // فوتر ثابت يظهر في جميع صفحات التطبيق.
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              Expanded(
                child: child ?? const SizedBox.shrink(),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF173F70),
                  border: Border(
                    top: BorderSide(
                      color: Color(0xFF2F7FF7),
                      width: 1,
                    ),
                  ),
                ),
                child: const Text(
                  'شعبة تقنية المعلومات / وحدة البرمجة | تصميم وتطوير المهندسة فاطمة زعيان | © 2026',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        );
      },

      home: const LoginScreen(),
    );
  }
}