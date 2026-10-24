
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/login_screen.dart';

void main() {
  runApp(const DocumentArchiveApp());
}

class DocumentArchiveApp extends StatelessWidget {
  const DocumentArchiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'نظام أرشفة المستندات',

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

      /*
       * هذا الجزء يضيف الفوتر بصورة ثابتة
       * إلى جميع صفحات التطبيق.
       */
      builder: (context, child) {
        return Column(
          children: [
            Expanded(
              child: child ?? const SizedBox.shrink(),
            ),

            const AppFooter(),
          ],
        );
      },

      home: const LoginScreen(),
    );
  }
}

/*
 * الفوتر الرسمي الثابت للتطبيق.
 */
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 9,
          ),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(
                color: Color(0xFFDDE6F2),
                width: 1,
              ),
            ),
          ),
          child: const Text(
            ' شعبة تقنية المعلومات / وحدة البرمجة — تصميم وتطوير المهندسة فاطمة زعيان | © 2026',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF65758B),
            ),
          ),
        ),
      ),
    );
  }
}