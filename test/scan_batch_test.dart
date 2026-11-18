import 'dart:io';

import 'package:document_archive_standard/services/document_storage_service.dart';
import 'package:document_archive_standard/services/scan_batch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('imports only new and overwritten pages in filename order', () async {
    final folder = await Directory.systemTemp.createTemp('archive-scan-test-');
    final old = File(p.join(folder.path, 'old.jpg'));
    final reused = File(p.join(folder.path, 'page_001.jpg'));
    final newPage = File(p.join(folder.path, 'page_002.png'));
    final empty = File(p.join(folder.path, 'page_003.jpg'));
    final pdf = File(p.join(folder.path, 'page_004.pdf'));
    addTearDown(() async {
      for (final file in [old, reused, newPage, empty, pdf]) {
        if (await file.exists()) await file.delete();
      }
      await folder.delete();
    });

    await old.writeAsString('old scan');
    await reused.writeAsString('previous page');
    final batch = await ScanBatch.start(folder);
    expect(await batch.changedImages(), isEmpty);

    await newPage.writeAsString('new page');
    await reused.writeAsString('overwritten page');
    await empty.create();
    await pdf.writeAsString('not an image');

    expect(await batch.changedImages(), [reused.path, newPage.path]);
    expect(await old.readAsString(), 'old scan');
    final nextBatch = await ScanBatch.start(folder);
    expect(await nextBatch.changedImages(), isEmpty);
  });

  test('assigns a distinct archive folder to every book', () {
    String mainFolder() => DocumentStorageService.buildMainRelativeFolder(
      documentNumber: '12',
      documentDate: '2026-11-12',
    );
    String attachmentFolder() =>
        DocumentStorageService.buildAttachmentRelativeFolder(
          parentDocumentId: 42,
          parentDocumentNumber: '6/أ',
          subDocumentNumber: '12',
          subDocumentDate: '2026-11-12',
        );

    final main = mainFolder();
    final attachment = attachmentFolder();
    expect(main, startsWith('documents/2026/11/'));
    expect(attachment, startsWith('attachments/كتاب رئيسي 6_أ (42)/2026/11/'));
    expect(mainFolder(), isNot(main));
    expect(attachmentFolder(), isNot(attachment));
  });
}
