import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';


class PrintService {
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