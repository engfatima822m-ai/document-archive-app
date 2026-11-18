import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
class PrintService {
  static Future<void> printPdf(
    BuildContext context, {
    required Uint8List bytes,
    required String name,
  }) async {
    final printers = await Printing.listPrinters();
    if (!context.mounted) return;

    if (printers.isEmpty) {
      throw Exception('لم يعثر ويندوز على طابعات مثبتة لحساب المستخدم الحالي.');
    }

    var selected = printers.firstWhere(
      (printer) => printer.isDefault,
      orElse: () => printers.first,
    );

    final printer = await showDialog<Printer>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('اختيار الطابعة'),
          content: SizedBox(
            width: 440,
            child: DropdownButton<Printer>(
              isExpanded: true,
              value: selected,
              items: [
                for (final printer in printers)
                  DropdownMenuItem(
                    value: printer,
                    child: Text(
                      printer.isAvailable
                          ? printer.name
                          : '${printer.name} (غير جاهزة)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (printer) {
                if (printer != null) {
                  setState(() => selected = printer);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: const Text('طباعة'),
            ),
          ],
        ),
      ),
    );

    if (printer == null || !context.mounted) return;

    final printed = await Printing.directPrintPdf(
      printer: printer,
      name: name,
      usePrinterSettings: true,
      onLayout: (_) async => bytes,
    );
    if (!printed) throw Exception('لم تكتمل عملية الطباعة.');
  }

  static Future<void> printWithDialog(List<String> imagePaths) async {
    if (imagePaths.isEmpty) {
      throw Exception('لا توجد صور للطباعة');
    }

    final pdf = pw.Document();

    for (final path in imagePaths) {
      final file = File(path);

      if (!await file.exists()) continue;

      final Uint8List bytes = await file.readAsBytes();
      final image = pw.MemoryImage(bytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }
}