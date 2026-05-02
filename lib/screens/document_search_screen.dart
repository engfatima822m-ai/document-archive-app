import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/document_model.dart';

class DocumentSearchScreen extends StatefulWidget {
  const DocumentSearchScreen({super.key});

  @override
  State<DocumentSearchScreen> createState() => _DocumentSearchScreenState();
}

class _DocumentSearchScreenState extends State<DocumentSearchScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isSearching = false;
  bool _isPrinting = false;

  DocumentModel? _searchedDocument;
  List<DocumentModel> _searchResults = [];
  List<DocumentModel> _searchedAttachments = [];
  List<String> _previewImages = [];
  int _currentPreviewIndex = 0;

  final Map<String, String> _attachmentParentTitles = {};
  final Map<String, String> _attachmentParentNumbers = {};

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
        colors: [Color(0xFFF8FCFF), Color(0xFFEAF6FF)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      );

  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.tif') ||
        lower.endsWith('.tiff') ||
        lower.endsWith('.webp');
  }

  List<String> _imagePathsFromJson(dynamic rawImagePaths) {
    if (rawImagePaths is List) {
      return rawImagePaths.map((e) => e.toString()).toList();
    }

    if (rawImagePaths is String && rawImagePaths.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawImagePaths);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return [];
  }

  bool _isAttachmentMap(Map<String, dynamic> map) {
    final type = (map['type'] ?? map['record_type'] ?? '').toString().trim();
    final status = (map['status'] ?? '').toString().trim();

    return type == 'attachment' ||
        type == 'كتاب تابع' ||
        status == 'كتاب تابع' ||
        map.containsKey('sub_document_number') ||
        map.containsKey('sub_document_title') ||
        map.containsKey('parent_document_number');
  }

  String _documentKey(DocumentModel document) {
    return '${document.id ?? ''}|${document.status}|${document.documentNumber}|${document.documentDate}|${document.documentTitle}|${document.folderPath}';
  }

  String _parentTitleFor(DocumentModel document) {
    return _attachmentParentTitles[_documentKey(document)] ?? '';
  }

  String _parentNumberFor(DocumentModel document) {
    return _attachmentParentNumbers[_documentKey(document)] ?? '';
  }

  void _rememberAttachmentParent(DocumentModel attachment, Map<String, dynamic> map) {
    final key = _documentKey(attachment);
    final parentTitle = (map['parent_document_title'] ?? '').toString().trim();
    final parentNumber = (map['parent_document_number'] ?? '').toString().trim();

    if (parentTitle.isNotEmpty) {
      _attachmentParentTitles[key] = parentTitle;
    }
    if (parentNumber.isNotEmpty) {
      _attachmentParentNumbers[key] = parentNumber;
    }
  }

  DocumentModel _documentFromJson(Map<String, dynamic> map) {
    final imagePaths = _imagePathsFromJson(map['image_paths']);

    return DocumentModel(
      id: map['id'] is int ? map['id'] : int.tryParse('${map['id']}'),
      documentNumber: (map['document_number'] ?? '').toString(),
      documentDate: (map['document_date'] ?? '').toString(),
      documentTitle: (map['document_title'] ?? '').toString(),
      notes: (map['notes'] ?? '').toString(),
      status: (map['status'] ?? 'قيد الإنجاز').toString(),
      reminderDate: map['reminder_date']?.toString(),
      reminderNote: map['reminder_note']?.toString(),
      folderPath: (map['folder_path'] ?? '').toString(),
      imagePaths: imagePaths,
    );
  }

  DocumentModel _attachmentFromJson(Map<String, dynamic> map) {
    final imagePaths = _imagePathsFromJson(map['image_paths']);

    final attachment = DocumentModel(
      id: map['id'] is int ? map['id'] : int.tryParse('${map['id']}'),
      documentNumber: (map['sub_document_number'] ?? map['document_number'] ?? '').toString(),
      documentDate: (map['sub_document_date'] ?? map['document_date'] ?? '').toString(),
      documentTitle: (map['sub_document_title'] ?? map['document_title'] ?? '').toString(),
      notes: (map['notes'] ?? '').toString(),
      status: 'كتاب تابع',
      reminderDate: map['reminder_date']?.toString(),
      reminderNote: map['reminder_note']?.toString(),
      folderPath: (map['folder_path'] ?? '').toString(),
      imagePaths: imagePaths,
    );

    _rememberAttachmentParent(attachment, map);
    return attachment;
  }

  Future<List<DocumentModel>> _fetchAllDocumentsFromApi() async {
    final uri = Uri.parse('$_apiBaseUrl/get_documents.php');
    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('فشل الاتصال بالخادم أثناء جلب الملفات');
    }

    final data = jsonDecode(response.body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'فشل جلب الملفات');
    }

    final List docs = data['documents'] ?? [];
    return docs
        .map((item) => _documentFromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  Future<Map<String, dynamic>?> _fetchDocumentWithAttachmentsFromApi(
    String documentNumber,
  ) async {
    final uri = Uri.parse('$_apiBaseUrl/get_document_by_number.php').replace(
      queryParameters: {'document_number': documentNumber},
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('فشل الاتصال بالخادم أثناء البحث');
    }

    final data = jsonDecode(response.body);
    if (data['success'] == true && data['document'] != null) {
      final type = (data['type'] ?? '').toString();
      final documentMap = Map<String, dynamic>.from(data['document']);
      final document = type == 'attachment'
          ? _documentFromJson(documentMap).copyWith(status: 'كتاب تابع')
          : _documentFromJson(documentMap);

      final List attachmentsJson = data['attachments'] ?? [];
      final attachments = attachmentsJson
          .map((item) => _attachmentFromJson(Map<String, dynamic>.from(item)))
          .toList();

      return {'document': document, 'attachments': attachments, 'type': type};
    }

    return null;
  }

  Future<List<DocumentModel>> _searchDocumentsInApi(String query) async {
    final allDocuments = await _fetchAllDocumentsFromApi();
    final lowerQuery = query.toLowerCase();

    final results = allDocuments.where((doc) {
      return doc.documentNumber.toLowerCase().contains(lowerQuery) ||
          doc.documentTitle.toLowerCase().contains(lowerQuery) ||
          doc.notes.toLowerCase().contains(lowerQuery) ||
          doc.status.toLowerCase().contains(lowerQuery);
    }).toList();

    results.sort((a, b) => b.documentDate.compareTo(a.documentDate));
    return results;
  }

  bool _sameDocumentIdentity(DocumentModel a, DocumentModel b) {
    return a.documentNumber == b.documentNumber &&
        a.documentDate == b.documentDate &&
        a.documentTitle == b.documentTitle &&
        a.folderPath == b.folderPath &&
        a.status == b.status;
  }

  bool _isAttachmentForParent(DocumentModel attachment, DocumentModel parent) {
    if (attachment.status.trim() != 'كتاب تابع') return false;

    final savedParentNumber = _parentNumberFor(attachment);
    final savedParentTitle = _parentTitleFor(attachment);

    if (savedParentNumber.isNotEmpty || savedParentTitle.isNotEmpty) {
      final numberOk = savedParentNumber.isEmpty || savedParentNumber == parent.documentNumber;
      final titleOk = savedParentTitle.isEmpty || savedParentTitle == parent.documentTitle;
      return numberOk && titleOk;
    }

    final parentRoot = _resolveDocumentRootFolderPath(parent.folderPath);
    final attachmentRoot = _resolveDocumentRootFolderPath(attachment.folderPath);

    if (parentRoot.isEmpty || attachmentRoot.isEmpty) return false;

    return p.isWithin(parentRoot, attachmentRoot) ||
        p.normalize(parentRoot).toLowerCase() == p.normalize(attachmentRoot).toLowerCase();
  }

  Future<List<DocumentModel>> _fetchAttachmentsForDocument(DocumentModel document) async {
    if (document.status.trim() == 'كتاب تابع') return [];

    try {
      final allDocuments = await _fetchAllDocumentsFromApi();
      final attachments = allDocuments.where((item) => _isAttachmentForParent(item, document)).toList();
      attachments.sort((a, b) => b.documentDate.compareTo(a.documentDate));
      return attachments;
    } catch (_) {
      return [];
    }
  }

  String _resolveDocumentRootFolderPath(String folderPath) {
    if (folderPath.trim().isEmpty) return '';
    final normalized = p.normalize(folderPath);
    final folderName = p.basename(normalized).toLowerCase();
    if (folderName == 'original') return p.dirname(normalized);
    return normalized;
  }

  int _extractLeadingNumber(String filePath) {
    final fileName = p.basenameWithoutExtension(filePath).trim();
    final match = RegExp(r'^\d+').firstMatch(fileName);
    if (match == null) return -1;
    return int.tryParse(match.group(0) ?? '') ?? -1;
  }

  Future<List<String>> _loadAllImagesFromDocumentFolder(String folderPath) async {
    try {
      final rootFolderPath = _resolveDocumentRootFolderPath(folderPath);
      if (rootFolderPath.isEmpty) return [];

      final rootDir = Directory(rootFolderPath);
      if (!await rootDir.exists()) return [];

      final List<String> imagePaths = [];
      await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is File && _isImageFile(entity.path)) imagePaths.add(entity.path);
      }

      imagePaths.sort((a, b) {
        final aIsOriginal = a.toLowerCase().contains('${Platform.pathSeparator}original${Platform.pathSeparator}');
        final bIsOriginal = b.toLowerCase().contains('${Platform.pathSeparator}original${Platform.pathSeparator}');
        if (aIsOriginal && !bIsOriginal) return -1;
        if (!aIsOriginal && bIsOriginal) return 1;
        final aNum = _extractLeadingNumber(a);
        final bNum = _extractLeadingNumber(b);
        if (aNum != -1 && bNum != -1 && aNum != bNum) return aNum.compareTo(bNum);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

      return imagePaths;
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadPreviewFor(DocumentModel document) async {
    List<String> folderImages = [];
    if (document.folderPath.trim().isNotEmpty) {
      folderImages = await _loadAllImagesFromDocumentFolder(document.folderPath);
    }
    if (folderImages.isEmpty) {
      folderImages = document.imagePaths.where((path) => File(path).existsSync()).toList();
    }
    if (!mounted) return;
    setState(() {
      _previewImages = folderImages;
      _currentPreviewIndex = 0;
    });
  }

  Future<void> _searchDocument() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showMessage('يرجى إدخال رقم الملف أو كلمة للبحث', isError: true);
      return;
    }

    setState(() => _isSearching = true);

    try {
      final exactData = await _fetchDocumentWithAttachmentsFromApi(query);
      final exactDocument = exactData?['document'] as DocumentModel?;
      final exactAttachments = (exactData?['attachments'] as List<DocumentModel>?) ?? [];
      final results = await _searchDocumentsInApi(query);
      final selectedDocument = exactDocument ?? (results.isNotEmpty ? results.first : null);

      setState(() {
        _searchedDocument = selectedDocument;
        _searchResults = results;
        _searchedAttachments = exactDocument != null ? exactAttachments : [];
      });

      if (selectedDocument == null) {
        setState(() => _previewImages = []);
        _showMessage('لم يتم العثور على نتيجة', isError: true);
      } else {
        await _loadPreviewFor(selectedDocument);
        _showMessage(_searchedAttachments.isEmpty
            ? 'تم العثور على الملف'
            : 'تم العثور على الملف ومعه ${_searchedAttachments.length} كتاب تابع');
      }
    } catch (e) {
      _showMessage('حدث خطأ أثناء البحث: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _clearSearch() {
    setState(() {
      _searchController.clear();
      _searchedDocument = null;
      _searchResults = [];
      _searchedAttachments = [];
      _previewImages = [];
      _currentPreviewIndex = 0;
    });
    _showMessage('تم مسح نتيجة البحث');
  }

  Future<void> _selectDocument(DocumentModel document) async {
    setState(() {
      _searchedDocument = document;
      _searchedAttachments = [];
    });
    final exactData = await _fetchDocumentWithAttachmentsFromApi(document.documentNumber);
    final attachments = (exactData?['attachments'] as List<DocumentModel>?) ?? [];
    setState(() {
      _searchedAttachments = attachments;
    });
    await _loadPreviewFor(document);
  }

  Future<void> _printCurrentDocument() async {
    final activeDocument = _searchedDocument;
    if (activeDocument == null) {
      _showMessage('لا يوجد ملف محدد للطباعة', isError: true);
      return;
    }

    final validImagePaths = _previewImages.where((path) => File(path).existsSync()).toList();
    if (validImagePaths.isEmpty) {
      _showMessage('لا توجد صور صالحة للطباعة لهذا الملف', isError: true);
      return;
    }

    setState(() => _isPrinting = true);
    try {
      final pdf = pw.Document();
      for (final imagePath in validImagePaths) {
        final Uint8List imageBytes = await File(imagePath).readAsBytes();
        final imageProvider = pw.MemoryImage(imageBytes);
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(18),
            build: (_) => pw.Center(child: pw.Image(imageProvider, fit: pw.BoxFit.contain)),
          ),
        );
      }
      await Printing.layoutPdf(
        name: 'document_${activeDocument.documentNumber}',
        onLayout: (_) async => pdf.save(),
      );
    } catch (e) {
      _showMessage('حدث خطأ أثناء الطباعة: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
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

  BoxDecoration _cardDecoration({bool gradient = true}) {
    return BoxDecoration(
      color: gradient ? null : cardColor,
      gradient: gradient ? _softGradient : null,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: borderColor),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.035), blurRadius: 10, offset: const Offset(0, 3))],
    );
  }

  Widget _buildSectionTitle(String title, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, color: accentColor, size: 22), const SizedBox(width: 8)],
        Text(title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: darkColor)),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    String? hint,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.right,
        onSubmitted: (_) => _searchDocument(),
        style: TextStyle(fontSize: 15, color: darkColor, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: hint,
          labelText: label,
          prefixIcon: Icon(icon, color: accentColor, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: borderColor)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: accentColor, width: 1.4)),
          filled: true,
          fillColor: Colors.transparent,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required String label,
    required IconData icon,
    bool dark = false,
    bool loading = false,
    double height = 48,
  }) {
    final gradient = dark
        ? LinearGradient(colors: [accentDarkColor, accentColor], begin: Alignment.centerRight, end: Alignment.centerLeft)
        : _mainGradient;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(16)),
        child: ElevatedButton.icon(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0),
          icon: loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildOutlinedActionButton({required VoidCallback? onPressed, required String label, required IconData icon}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: darkColor,
          backgroundColor: Colors.white.withOpacity(0.9),
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildMiniInfoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
        child: Row(
          children: [
            Expanded(child: Text(value.isEmpty ? '-' : value, textAlign: TextAlign.right, style: TextStyle(color: darkColor, fontWeight: FontWeight.w600, fontSize: 13.2))),
            const SizedBox(width: 8),
            Text('$title:', style: TextStyle(color: softTextColor, fontWeight: FontWeight.w700, fontSize: 12.3)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('البحث عن ملف', icon: Icons.search_rounded),
          const SizedBox(height: 10),
          _buildTextField(label: 'رقم الملف أو نص البحث', icon: Icons.manage_search_rounded, controller: _searchController, hint: 'مثال: 12345 أو كلمة من الملاحظات'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _buildActionButton(onPressed: _isSearching ? null : _searchDocument, label: _isSearching ? 'جاري البحث...' : 'بحث', icon: Icons.search, loading: _isSearching)),
              const SizedBox(width: 8),
              Expanded(child: _buildOutlinedActionButton(onPressed: _clearSearch, label: 'مسح', icon: Icons.close)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentCard(DocumentModel attachment) {
    final parentTitle = _parentTitleFor(attachment);
    final parentNumber = _parentNumberFor(attachment);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _selectDocument(attachment),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor)),
          child: Row(
            children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(gradient: _mainGradient, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.attach_file_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('كتاب تابع رقم ${attachment.documentNumber}', textAlign: TextAlign.right, style: TextStyle(color: darkColor, fontWeight: FontWeight.w800, fontSize: 13.5)),
                    const SizedBox(height: 4),
                    Text(attachment.documentTitle.isEmpty ? 'بدون عنوان' : attachment.documentTitle, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: softTextColor, fontWeight: FontWeight.w600, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Text('التأريخ: ${attachment.documentDate.isEmpty ? '-' : attachment.documentDate}', textAlign: TextAlign.right, style: TextStyle(color: softTextColor, fontSize: 12)),
                    if (parentTitle.isNotEmpty || parentNumber.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'الأصل: ${parentNumber.isEmpty ? '-' : parentNumber} - ${parentTitle.isEmpty ? '-' : parentTitle}',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: accentDarkColor, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: accentColor, size: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final activeDocument = _searchedDocument;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: activeDocument == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('نتيجة البحث', icon: Icons.assignment_outlined),
                const SizedBox(height: 8),
                Text('لم يتم العثور على أي ملف بعد.', style: TextStyle(color: softTextColor, fontSize: 13)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('نتيجة البحث', icon: Icons.assignment_outlined),
                const SizedBox(height: 10),
                _buildMiniInfoRow('رقم الملف', activeDocument.documentNumber),
                _buildMiniInfoRow('تأريخ الملف', activeDocument.documentDate),
                _buildMiniInfoRow('اسم الملف', activeDocument.documentTitle),
                _buildMiniInfoRow('ملاحظات', activeDocument.notes),
                _buildMiniInfoRow('الحالة', activeDocument.status),
                _buildMiniInfoRow('تاريخ التذكير', activeDocument.reminderDate ?? ''),
                _buildMiniInfoRow('عدد الصور', _previewImages.isNotEmpty ? _previewImages.length.toString() : activeDocument.imagePaths.length.toString()),
                _buildMiniInfoRow('مسار الفولدر', activeDocument.folderPath),
                const SizedBox(height: 8),
                _buildActionButton(
                  onPressed: () => Navigator.pop(context, activeDocument),
                  label: 'تعبئة الحقول في صفحة الإدخال',
                  icon: Icons.edit_note_outlined,
                ),
                const SizedBox(height: 8),
                _buildActionButton(
                  onPressed: _isPrinting ? null : _printCurrentDocument,
                  label: _isPrinting ? 'جاري تجهيز الطباعة...' : 'طباعة الملف',
                  icon: Icons.print_outlined,
                  dark: true,
                  loading: _isPrinting,
                ),
                if (_searchedAttachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('الكتب التابعة داخل هذا الملف (${_searchedAttachments.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: darkColor)),
                  const SizedBox(height: 8),
                  ..._searchedAttachments.map(_buildAttachmentCard),
                ],
                if (_searchResults.length > 1) ...[
                  const SizedBox(height: 10),
                  Text('نتائج إضافية (${_searchResults.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: darkColor)),
                  const SizedBox(height: 6),
                  ..._searchResults.take(8).map(
                        (doc) => Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: InkWell(
                            onTap: () => _selectDocument(doc),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.white.withOpacity(0.88), borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor)),
                              child: Text('${doc.documentNumber} - ${doc.documentTitle}', textAlign: TextAlign.right, style: TextStyle(color: darkColor, fontWeight: FontWeight.w600, fontSize: 12.5)),
                            ),
                          ),
                        ),
                      ),
                ],
              ],
            ),
    );
  }

  Widget _buildLargePreviewCard() {
    final validPaths = _previewImages.where((path) => File(path).existsSync()).toList();
    final hasImages = validPaths.isNotEmpty;
    final currentPath = hasImages ? validPaths[_currentPreviewIndex.clamp(0, validPaths.length - 1).toInt()] : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('الصورة الكاملة', icon: Icons.image_outlined),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(18), border: Border.all(color: borderColor)),
              child: !hasImages
                  ? Center(child: Text('ستظهر صورة الملف هنا بعد البحث', style: TextStyle(color: softTextColor, fontWeight: FontWeight.w700)))
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        InteractiveViewer(child: Image.file(File(currentPath!), fit: BoxFit.contain)),
                        if (validPaths.length > 1) ...[
                          Positioned(left: 20, child: _arrowButton(Icons.chevron_left_rounded, _previousImage)),
                          Positioned(right: 20, child: _arrowButton(Icons.chevron_right_rounded, _nextImage)),
                        ],
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (hasImages) _buildThumbnails(validPaths),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFDFF0FF), borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
            child: Text('عدد الصفحات: ${validPaths.length}${hasImages ? '    الصفحة ${_currentPreviewIndex + 1} من ${validPaths.length}' : ''}', textAlign: TextAlign.center, style: TextStyle(color: darkColor, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Widget _arrowButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.white.withOpacity(0.9),
      borderRadius: BorderRadius.circular(14),
      child: IconButton(onPressed: onPressed, icon: Icon(icon, color: accentDarkColor), iconSize: 30),
    );
  }

  Widget _buildThumbnails(List<String> paths) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isSelected = index == _currentPreviewIndex;
          return InkWell(
            onTap: () => setState(() => _currentPreviewIndex = index),
            child: Container(
              width: 82,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: isSelected ? accentColor : borderColor, width: isSelected ? 3 : 1)),
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(paths[index]), fit: BoxFit.cover)),
            ),
          );
        },
      ),
    );
  }

  void _nextImage() {
    if (_previewImages.length <= 1) return;
    setState(() => _currentPreviewIndex = (_currentPreviewIndex + 1) % _previewImages.length);
  }

  void _previousImage() {
    if (_previewImages.length <= 1) return;
    setState(() => _currentPreviewIndex = (_currentPreviewIndex - 1 + _previewImages.length) % _previewImages.length);
  }

  Widget _buildRightColumn() {
    return SingleChildScrollView(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildActionButton(onPressed: () => Navigator.pop(context), label: 'رجوع للإدخال', icon: Icons.arrow_back_rounded, dark: true)),
            ],
          ),
          const SizedBox(height: 12),
          _buildSearchCard(),
          const SizedBox(height: 12),
          _buildResultCard(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 1100;
              return Container(
                width: double.infinity,
                height: double.infinity,
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFE9F7FF), Color(0xFFD4ECFF)], begin: Alignment.topRight, end: Alignment.bottomLeft),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 7, child: _buildLargePreviewCard()),
                          const SizedBox(width: 14),
                          Expanded(flex: 5, child: _buildRightColumn()),
                        ],
                      )
                    : SingleChildScrollView(
                        child: SizedBox(
                          height: 1000,
                          child: Column(
                            children: [
                              SizedBox(height: 520, child: _buildLargePreviewCard()),
                              const SizedBox(height: 12),
                              _buildRightColumn(),
                            ],
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

extension _DocumentCopy on DocumentModel {
  DocumentModel copyWith({String? status}) {
    return DocumentModel(
      id: id,
      documentNumber: documentNumber,
      documentDate: documentDate,
      documentTitle: documentTitle,
      notes: notes,
      status: status ?? this.status,
      reminderDate: reminderDate,
      reminderNote: reminderNote,
      folderPath: folderPath,
      imagePaths: imagePaths,
    );
  }
}
