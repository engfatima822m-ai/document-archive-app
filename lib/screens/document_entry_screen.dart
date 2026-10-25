import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/document_model.dart';
import '../services/api_service.dart';
import '../services/document_storage_service.dart';
import 'document_search_screen.dart';
import 'documents_by_status_screen.dart';
import 'login_screen.dart';
import 'reminders_screen.dart';

class BatchBookForm {
  final TextEditingController numberController;
  final TextEditingController dateController;
  final TextEditingController titleController;
  final TextEditingController notesController;

  BatchBookForm({
    required String initialDate,
  })  : numberController =
            TextEditingController(),
        dateController =
            TextEditingController(
          text: initialDate,
        ),
        titleController =
            TextEditingController(),
        notesController =
            TextEditingController();

  void dispose() {
    numberController.dispose();
    dateController.dispose();
    titleController.dispose();
    notesController.dispose();
  }
}

class DocumentEntryScreen
    extends StatefulWidget {
  const DocumentEntryScreen({super.key});

  @override
  State<DocumentEntryScreen> createState() =>
      _DocumentEntryScreenState();
}

class _DocumentEntryScreenState
    extends State<DocumentEntryScreen> {
  static const String captureOnTouchPath =
      r'C:\Program Files (x86)\Canon Electronics\CaptureOnTouch\TouchDR.exe';

  final documentNumberController =
      TextEditingController();

  final documentDateController =
      TextEditingController();

  final documentTitleController =
      TextEditingController();

  final notesController =
      TextEditingController();

  final reminderDateController =
      TextEditingController();

  final reminderNoteController =
      TextEditingController();

  final parentNumberController =
      TextEditingController();

  final formKey = GlobalKey<FormState>();

  bool isAttachment = false;
  bool separateEachPage = false;
  bool isSaving = false;
  bool isLookingForParent = false;
  bool isImporting = false;

  String selectedStatus = 'قيد الإنجاز';

  DocumentModel? selectedParent;

  List<String> sourceImagePaths = [];
  List<BatchBookForm> batchForms = [];

  int previewIndex = 0;

  final statuses = const [
    'قيد الإنجاز',
    'منجز',
    'تم الاطلاع',
  ];

  @override
  void initState() {
    super.initState();

    documentDateController.text =
        _formatDate(DateTime.now());

    _ensureRequiredFolders();
  }

  @override
  void dispose() {
    documentNumberController.dispose();
    documentDateController.dispose();
    documentTitleController.dispose();
    notesController.dispose();
    reminderDateController.dispose();
    reminderNoteController.dispose();
    parentNumberController.dispose();

    _disposeBatchForms();

    super.dispose();
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _ensureRequiredFolders() async {
    try {
      await DocumentStorageService
          .ensureBaseFolderExists();

      final temporaryDirectory = Directory(
        DocumentStorageService
            .scanTemporaryPath,
      );

      if (!await temporaryDirectory.exists()) {
        await temporaryDirectory.create(
          recursive: true,
        );
      }
    } catch (exception) {
      if (!mounted) return;

      _showMessage(
        'تعذر تجهيز مجلدات الأرشيف: $exception',
        isError: true,
      );
    }
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
              ? const Color(0xFFB42318)
              : const Color(0xFF16835D),
        ),
      );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF9FBFE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFFD7E2F0),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF24528A),
          width: 2,
        ),
      ),
    );
  }

  String? _requiredValidator(
    String? value,
    String label,
  ) {
    if (value == null ||
        value.trim().isEmpty) {
      return '$label مطلوب';
    }

    return null;
  }

  Future<void> _pickDate(
    TextEditingController controller,
  ) async {
    final current =
        DateTime.tryParse(controller.text) ??
            DateTime.now();

    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );

    if (selected != null) {
      controller.text = _formatDate(selected);
    }
  }

  Future<void> _pickImages() async {
    if (isSaving) return;

    final result =
        await FilePicker.platform.pickFiles(
      dialogTitle:
          'اختار صور المستند بالترتيب',
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
      ],
    );

    if (result == null) return;

    final paths = result.files
        .map((file) => file.path)
        .whereType<String>()
        .where((path) => path.trim().isNotEmpty)
        .toList();

    if (paths.isEmpty) {
      _showMessage(
        'لم يتم اختيار صور صالحة.',
        isError: true,
      );
      return;
    }

    setState(() {
      sourceImagePaths = paths;
      previewIndex = 0;
    });

    _syncBatchForms();
  }

  Future<void> _importFromTemporaryFolder() async {
    if (isImporting || isSaving) return;

    setState(() {
      isImporting = true;
    });

    try {
      final directory = Directory(
        DocumentStorageService
            .scanTemporaryPath,
      );

      if (!await directory.exists()) {
        await directory.create(
          recursive: true,
        );
      }

      final files = await directory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .where((file) {
        final lower = file.path.toLowerCase();

        return lower.endsWith('.jpg') ||
            lower.endsWith('.jpeg') ||
            lower.endsWith('.png');
      }).toList();

      files.sort(
        (first, second) => first.path
            .toLowerCase()
            .compareTo(
              second.path.toLowerCase(),
            ),
      );

      if (files.isEmpty) {
        _showMessage(
          'لا توجد صور داخل مجلد السحب المؤقت.',
          isError: true,
        );
        return;
      }

      // Refresh cached images when the scanner reuses the same file paths.
      final pathsToRefresh = <String>{
        ...sourceImagePaths,
        ...files.map((file) => file.path),
      };

      for (final path in pathsToRefresh) {
        await FileImage(File(path)).evict();
      }

      if (!mounted) return;

      setState(() {
        sourceImagePaths = [];
        previewIndex = 0;
      });

      await WidgetsBinding.instance.endOfFrame;

      if (!mounted) return;

      setState(() {
        sourceImagePaths = files
            .map((file) => file.path)
            .toList();

        previewIndex = 0;
      });

      _syncBatchForms();

      _showMessage(
        'تم استيراد ${files.length} صفحة.',
      );
    } catch (exception) {
      _showMessage(
        'تعذر استيراد صور السكانر: $exception',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isImporting = false;
        });
      }
    }
  }

  Future<void> _openCaptureOnTouch() async {
    try {
      final executable =
          File(captureOnTouchPath);

      if (!await executable.exists()) {
        _showMessage(
          'برنامج CaptureOnTouch غير موجود '
          'في المسار المحدد.',
          isError: true,
        );
        return;
      }

      await Process.start(
        captureOnTouchPath,
        const [],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );

      _showMessage(
        'تم فتح برنامج جهاز الأرشفة. '
        'بعد انتهاء السحب اضغط استيراد الصور.',
      );
    } catch (exception) {
      _showMessage(
        'تعذر فتح CaptureOnTouch: $exception',
        isError: true,
      );
    }
  }

  void _disposeBatchForms() {
    for (final form in batchForms) {
      form.dispose();
    }

    batchForms = [];
  }

  void _syncBatchForms() {
    if (!separateEachPage ||
        isAttachment) {
      _disposeBatchForms();

      if (mounted) {
        setState(() {});
      }

      return;
    }

    final oldForms =
        List<BatchBookForm>.from(batchForms);

    final newForms = <BatchBookForm>[];

    for (
      var index = 0;
      index < sourceImagePaths.length;
      index++
    ) {
      if (index < oldForms.length) {
        newForms.add(oldForms[index]);
      } else {
        newForms.add(
          BatchBookForm(
            initialDate:
                documentDateController.text,
          ),
        );
      }
    }

    for (
      var index = sourceImagePaths.length;
      index < oldForms.length;
      index++
    ) {
      oldForms[index].dispose();
    }

    batchForms = newForms;

    if (mounted) {
      setState(() {});
    }
  }

  void _removeImage(int index) {
    if (isSaving) return;

    setState(() {
      sourceImagePaths.removeAt(index);

      if (sourceImagePaths.isEmpty) {
        previewIndex = 0;
      } else if (
          previewIndex >=
          sourceImagePaths.length) {
        previewIndex =
            sourceImagePaths.length - 1;
      }
    });

    _syncBatchForms();
  }

  Future<void> _findParentDocument() async {
    final number =
        parentNumberController.text.trim();

    if (number.isEmpty) {
      _showMessage(
        'اكتب رقم الملف الأصلي.',
        isError: true,
      );
      return;
    }

    setState(() {
      isLookingForParent = true;
      selectedParent = null;
    });

    try {
      final response =
          await ApiService.getJson(
        'get_document_by_number.php',
        queryParameters: {
          'document_number': number,
        },
      );

      if (
          response['multiple_matches'] ==
          true) {
        final rawMatches =
            response['matches'];

        if (rawMatches is! List) {
          throw const ApiException(
            'تعذر قراءة نتائج البحث.',
          );
        }

        final mainMatches = rawMatches
            .whereType<Map>()
            .map(
              (item) =>
                  Map<String, dynamic>.from(
                item,
              ),
            )
            .where(
              (item) =>
                  item['record_type'] ==
                  'main',
            )
            .toList();

        if (mainMatches.isEmpty) {
          throw const ApiException(
            'الرقم يعود إلى كتاب تابع '
            'وليس ملفًا أصليًا.',
          );
        }

        final selected =
            await _selectParentDialog(
          mainMatches,
        );

        if (selected == null) return;

        final detailedResponse =
            await ApiService.getJson(
          'get_document_by_number.php',
          queryParameters: {
            'document_number':
                selected[
                    'document_number'],
          },
        );

        if (
            detailedResponse[
                    'multiple_matches'] ==
                true) {
          selectedParent =
              DocumentModel.fromJson(
            selected,
          );
        } else {
          final rawDocument =
              detailedResponse['document'];

          if (rawDocument is! Map) {
            throw const ApiException(
              'تعذر قراءة الملف الأصلي.',
            );
          }

          selectedParent =
              DocumentModel.fromJson(
            Map<String, dynamic>.from(
              rawDocument,
            ),
          );
        }
      } else {
        if (response['type'] != 'main') {
          throw const ApiException(
            'الرقم المدخل ليس ملفًا أصليًا.',
          );
        }

        final rawDocument =
            response['document'];

        if (rawDocument is! Map) {
          throw const ApiException(
            'تعذر قراءة الملف الأصلي.',
          );
        }

        selectedParent =
            DocumentModel.fromJson(
          Map<String, dynamic>.from(
            rawDocument,
          ),
        );
      }

      if (!mounted) return;

      setState(() {});

      _showMessage(
        'تم اختيار الملف: '
        '${selectedParent!.documentTitle}',
      );
    } on ApiException catch (exception) {
      _showMessage(
        exception.message,
        isError: true,
      );
    } catch (exception) {
      _showMessage(
        'تعذر البحث عن الملف: $exception',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isLookingForParent = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>?>
      _selectParentDialog(
    List<Map<String, dynamic>> matches,
  ) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'اختار الملف الأصلي',
          ),
          content: SizedBox(
            width: 520,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: matches.length,
              separatorBuilder: (_, __) =>
                  const Divider(),
              itemBuilder: (_, index) {
                final item = matches[index];

                return ListTile(
                  leading: const Icon(
                    Icons.folder_outlined,
                  ),
                  title: Text(
                    item['document_title']
                            ?.toString() ??
                        '',
                  ),
                  subtitle: Text(
                    '${item['document_number']}'
                    ' — '
                    '${item['document_date']}',
                  ),
                  onTap: () {
                    Navigator.of(dialogContext)
                        .pop(item);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  bool _validateReminder() {
    final date =
        reminderDateController.text.trim();

    final note =
        reminderNoteController.text.trim();

    if (
        (date.isEmpty && note.isNotEmpty) ||
        (date.isNotEmpty && note.isEmpty)) {
      _showMessage(
        'أدخل تاريخ التنبيه وملاحظته معًا.',
        isError: true,
      );

      return false;
    }

    return true;
  }

  Future<void> _save() async {
    if (isSaving) return;

    if (sourceImagePaths.isEmpty) {
      _showMessage(
        'اكتب أو اختر صور المستند أولًا.',
        isError: true,
      );
      return;
    }

    if (separateEachPage &&
        !isAttachment) {
      await _saveSeparateBooks();
      return;
    }

    if (!(formKey.currentState?.validate() ??
        false)) {
      return;
    }

    if (!_validateReminder()) return;

    if (isAttachment &&
        selectedParent == null) {
      _showMessage(
        'اختار الملف الأصلي أولًا.',
        isError: true,
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      if (isAttachment) {
        await DocumentStorageService
            .saveAttachmentFromImages(
          parentDocumentId:
              selectedParent!.id!,
          parentDocumentNumber:
              selectedParent!
                  .documentNumber,
          parentDocumentTitle:
              selectedParent!
                  .documentTitle,
          subDocumentNumber:
              documentNumberController
                  .text
                  .trim(),
          subDocumentDate:
              documentDateController
                  .text
                  .trim(),
          subDocumentTitle:
              documentTitleController
                  .text
                  .trim(),
          notes:
              notesController.text.trim(),
          reminderDate:
              reminderDateController.text
                      .trim()
                      .isEmpty
                  ? null
                  : reminderDateController
                      .text
                      .trim(),
          reminderNote:
              reminderNoteController.text
                      .trim()
                      .isEmpty
                  ? null
                  : reminderNoteController
                      .text
                      .trim(),
          sourceImagePaths:
              List<String>.from(
            sourceImagePaths,
          ),
        );

        _showMessage(
          'تم حفظ الكتاب التابع كملف PDF.',
        );
      } else {
        await DocumentStorageService
            .saveMainDocumentFromImages(
          documentNumber:
              documentNumberController
                  .text
                  .trim(),
          documentDate:
              documentDateController
                  .text
                  .trim(),
          documentTitle:
              documentTitleController
                  .text
                  .trim(),
          notes:
              notesController.text.trim(),
          status: selectedStatus,
          reminderDate:
              reminderDateController.text
                      .trim()
                      .isEmpty
                  ? null
                  : reminderDateController
                      .text
                      .trim(),
          reminderNote:
              reminderNoteController.text
                      .trim()
                      .isEmpty
                  ? null
                  : reminderNoteController
                      .text
                      .trim(),
          sourceImagePaths:
              List<String>.from(
            sourceImagePaths,
          ),
        );

        _showMessage(
          'تم حفظ الملف الرئيسي كملف PDF.',
        );
      }

      _resetForm();
    } on ApiException catch (exception) {
      _showMessage(
        exception.message,
        isError: true,
      );
    } catch (exception) {
      _showMessage(
        exception.toString(),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Future<void> _saveSeparateBooks() async {
    if (batchForms.length !=
        sourceImagePaths.length) {
      _showMessage(
        'بيانات الكتب لا تطابق عدد الصفحات.',
        isError: true,
      );
      return;
    }

    for (
      var index = 0;
      index < batchForms.length;
      index++
    ) {
      final form = batchForms[index];

      if (form.numberController.text
              .trim()
              .isEmpty ||
          form.dateController.text
              .trim()
              .isEmpty ||
          form.titleController.text
              .trim()
              .isEmpty) {
        _showMessage(
          'أكمل رقم وتاريخ واسم '
          'الكتاب رقم ${index + 1}.',
          isError: true,
        );
        return;
      }
    }

    setState(() {
      isSaving = true;
    });

    final batchId =
        DocumentStorageService
            .generateBatchId();

    try {
      final documentsJson =
          <Map<String, dynamic>>[];

      for (
        var index = 0;
        index < batchForms.length;
        index++
      ) {
        final form = batchForms[index];

        final number =
            form.numberController.text
                .trim();

        final date =
            form.dateController.text
                .trim();

        final title =
            form.titleController.text
                .trim();

        final relativeFolder =
            DocumentStorageService
                .buildMainRelativeFolder(
          documentNumber: number,
          documentDate: date,
        );

        final pdfName =
            DocumentStorageService
                .buildPdfFileName(
          number: number,
          title: title,
        );

        final preparedPdf =
            await DocumentStorageService
                .createPdfFromImages(
          sourceImagePaths: [
            sourceImagePaths[index],
          ],
          relativeFolderPath:
              relativeFolder,
          pdfFileName: pdfName,
        );

        final document = DocumentModel(
          documentNumber: number,
          documentDate: date,
          documentTitle: title,
          notes: form.notesController.text
              .trim(),
          status: selectedStatus,
          hasPdf: true,
          relativeFolderPath:
              preparedPdf
                  .relativeFolderPath,
          pdfRelativePath:
              preparedPdf.relativePdfPath,
          pdfSizeBytes:
              preparedPdf.fileSizeBytes,
          pdfSha256:
              preparedPdf.sha256Hash,
          pageCount: 1,
          scanMode: 'separate_pages',
          scanBatchId: batchId,
        );

        documentsJson.add(
          document.toCreateJson(),
        );
      }

      final response =
          await ApiService.postJson(
        'insert_document_batch.php',
        {
          'scan_batch_id': batchId,
          'documents': documentsJson,
        },
      );

      final savedCount =
          response['documents_count'] ??
              documentsJson.length;

      await DocumentStorageService
          .deleteSuccessfulScanImages(
        List<String>.from(
          sourceImagePaths,
        ),
      );

      _showMessage(
        'تم حفظ $savedCount كتاب '
        'كملفات PDF منفصلة.',
      );

      _resetForm();
    } on ApiException catch (exception) {
      _showMessage(
        exception.message,
        isError: true,
      );
    } catch (exception) {
      _showMessage(
        'تعذر حفظ دفعة الكتب: $exception',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  void _resetForm() {
    documentNumberController.clear();
    documentTitleController.clear();
    notesController.clear();
    reminderDateController.clear();
    reminderNoteController.clear();

    documentDateController.text =
        _formatDate(DateTime.now());

    _disposeBatchForms();

    setState(() {
      sourceImagePaths = [];
      previewIndex = 0;
      selectedParent = null;
      parentNumberController.clear();
      separateEachPage = false;
      selectedStatus = 'قيد الإنجاز';
    });
  }

  Future<void> _logout() async {
    try {
      if (ApiService.isLoggedIn) {
        await ApiService.postJson(
          'logout.php',
          const {},
        );
      }
    } catch (_) {
      // يتم إنهاء الجلسة محليًا حتى
      // عند تعذر الوصول إلى الخادم.
    } finally {
      ApiService.clearSession();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              const LoginScreen(),
        ),
        (_) => false,
      );
    }
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('ملف رئيسي'),
              icon: Icon(
                Icons.folder_outlined,
              ),
            ),
            ButtonSegment(
              value: true,
              label: Text('كتاب تابع'),
              icon: Icon(
                Icons.attachment_outlined,
              ),
            ),
          ],
          selected: {isAttachment},
          onSelectionChanged: isSaving
              ? null
              : (selection) {
                  setState(() {
                    isAttachment =
                        selection.first;

                    separateEachPage = false;
                    selectedParent = null;
                    parentNumberController
                        .clear();
                  });

                  _syncBatchForms();
                },
        ),
        if (!isAttachment) ...[
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding:
                const EdgeInsets.symmetric(
              horizontal: 8,
            ),
            title: const Text(
              'كل ورقة كتاب مستقل',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: const Text(
              'فعله عند سحب عدة كتب، '
              'كل كتاب منها صفحة واحدة.',
            ),
            value: separateEachPage,
            onChanged: isSaving
                ? null
                : (value) {
                    setState(() {
                      separateEachPage =
                          value;
                    });

                    _syncBatchForms();
                  },
          ),
        ],
      ],
    );
  }

  Widget _buildParentSelector() {
    if (!isAttachment) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FD),
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color:
              const Color(0xFFBDD3EC),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller:
                      parentNumberController,
                  decoration:
                      _inputDecoration(
                    label:
                        'رقم الملف الأصلي',
                    icon: Icons.search,
                  ),
                  onSubmitted: (_) =>
                      _findParentDocument(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed:
                    isLookingForParent
                        ? null
                        : _findParentDocument,
                icon: isLookingForParent
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.manage_search,
                      ),
                label:
                    const Text('بحث'),
              ),
            ],
          ),
          if (selectedParent != null) ...[
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(
                Icons.folder_open,
                color: Color(0xFF24528A),
              ),
              title: Text(
                selectedParent!
                    .documentTitle,
              ),
              subtitle: Text(
                'رقم الملف: '
                '${selectedParent!.documentNumber}',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStandardForm() {
    return Form(
      key: formKey,
      child: Column(
        children: [
          _buildParentSelector(),
          if (isAttachment)
            const SizedBox(height: 14),
          TextFormField(
            controller:
                documentNumberController,
            decoration: _inputDecoration(
              label: isAttachment
                  ? 'رقم الكتاب التابع'
                  : 'رقم الملف',
              icon: Icons.numbers,
            ),
            validator: (value) =>
                _requiredValidator(
              value,
              isAttachment
                  ? 'رقم الكتاب التابع'
                  : 'رقم الملف',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller:
                documentDateController,
            readOnly: true,
            onTap: () => _pickDate(
              documentDateController,
            ),
            decoration: _inputDecoration(
              label: isAttachment
                  ? 'تاريخ الكتاب التابع'
                  : 'تاريخ الملف',
              icon:
                  Icons.calendar_month,
            ),
            validator: (value) =>
                _requiredValidator(
              value,
              'التاريخ',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller:
                documentTitleController,
            decoration: _inputDecoration(
              label: isAttachment
                  ? 'اسم الكتاب التابع'
                  : 'اسم الملف',
              icon:
                  Icons.description_outlined,
            ),
            validator: (value) =>
                _requiredValidator(
              value,
              isAttachment
                  ? 'اسم الكتاب التابع'
                  : 'اسم الملف',
            ),
          ),
          if (!isAttachment) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: selectedStatus,
              decoration: _inputDecoration(
                label: 'حالة الملف',
                icon:
                    Icons.task_alt_outlined,
              ),
              items: statuses
                  .map(
                    (status) =>
                        DropdownMenuItem(
                      value: status,
                      child: Text(status),
                    ),
                  )
                  .toList(),
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          selectedStatus =
                              value;
                        });
                      }
                    },
            ),
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: notesController,
            minLines: 2,
            maxLines: 4,
            decoration: _inputDecoration(
              label: 'ملاحظات',
              icon: Icons.notes,
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller:
                reminderDateController,
            readOnly: true,
            onTap: () => _pickDate(
              reminderDateController,
            ),
            decoration: _inputDecoration(
              label:
                  'تاريخ التنبيه - اختياري',
              icon:
                  Icons.notifications_outlined,
            ).copyWith(
              suffixIcon:
                  reminderDateController
                          .text
                          .isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            setState(() {
                              reminderDateController
                                  .clear();
                              reminderNoteController
                                  .clear();
                            });
                          },
                          icon: const Icon(
                            Icons.clear,
                          ),
                        ),
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller:
                reminderNoteController,
            minLines: 1,
            maxLines: 3,
            decoration: _inputDecoration(
              label:
                  'ملاحظة التنبيه - اختيارية',
              icon:
                  Icons.notification_add_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchForms() {
    if (sourceImagePaths.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text(
          'اسحب أو اختار الصور أولًا، '
          'ثم ستظهر حقول كل كتاب.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: List.generate(
        batchForms.length,
        (index) {
          final form = batchForms[index];

          return Card(
            margin:
                const EdgeInsets.only(
              bottom: 14,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'الكتاب رقم ${index + 1}',
                    style:
                        const TextStyle(
                      fontSize: 17,
                      fontWeight:
                          FontWeight.bold,
                      color:
                          Color(0xFF173A64),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        form.numberController,
                    decoration:
                        _inputDecoration(
                      label: 'رقم الكتاب',
                      icon: Icons.numbers,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        form.dateController,
                    readOnly: true,
                    onTap: () => _pickDate(
                      form.dateController,
                    ),
                    decoration:
                        _inputDecoration(
                      label: 'تاريخ الكتاب',
                      icon: Icons
                          .calendar_month,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        form.titleController,
                    decoration:
                        _inputDecoration(
                      label: 'اسم الكتاب',
                      icon: Icons
                          .description_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller:
                        form.notesController,
                    maxLines: 2,
                    decoration:
                        _inputDecoration(
                      label:
                          'ملاحظات - اختيارية',
                      icon: Icons.notes,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormPanel() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(18),
        side: const BorderSide(
          color: Color(0xFFDCE6F2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text(
              'بيانات الأرشفة',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Color(0xFF173A64),
              ),
            ),
            const SizedBox(height: 18),
            _buildModeSelector(),
            const Divider(height: 30),
            if (separateEachPage &&
                !isAttachment)
              _buildBatchForms()
            else
              _buildStandardForm(),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed:
                    isSaving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF24528A),
                ),
                icon: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.save_outlined,
                      ),
                label: Text(
                  isSaving
                      ? 'جاري الحفظ...'
                      : 'حفظ في الأرشيف',
                  style:
                      const TextStyle(
                    fontSize: 16,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    final hasImages =
        sourceImagePaths.isNotEmpty;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(18),
        side: const BorderSide(
          color: Color(0xFFDCE6F2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            const Text(
              'صفحات المستند',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Color(0xFF173A64),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: isSaving
                      ? null
                      : _openCaptureOnTouch,
                  icon: const Icon(
                    Icons.document_scanner,
                  ),
                  label: const Text(
                    'فتح جهاز الأرشفة',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isSaving ||
                          isImporting
                      ? null
                      : _importFromTemporaryFolder,
                  icon: isImporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.download_outlined,
                        ),
                  label: const Text(
                    'استيراد صور السحب',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed:
                      isSaving ? null : _pickImages,
                  icon: const Icon(
                    Icons.folder_open,
                  ),
                  label: const Text(
                    'اختيار صور',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                constraints:
                    const BoxConstraints(
                  minHeight: 340,
                ),
                decoration: BoxDecoration(
                  color:
                      const Color(0xFFF7FAFE),
                  borderRadius:
                      BorderRadius.circular(14),
                  border: Border.all(
                    color:
                        const Color(0xFFDCE6F2),
                  ),
                ),
                child: !hasImages
                    ? const Center(
                        child: Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Icon(
                              Icons
                                  .picture_as_pdf_outlined,
                              size: 70,
                              color:
                                  Color(0xFF7890AC),
                            ),
                            SizedBox(height: 14),
                            Text(
                              'ستظهر صفحات المستند هنا',
                              style:
                                  TextStyle(
                                color:
                                    Color(0xFF65758B),
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'وسيتم تحويلها إلى PDF عند الحفظ',
                              style:
                                  TextStyle(
                                fontSize: 12,
                                color:
                                    Color(0xFF8797AA),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          Positioned.fill(
                            child: Padding(
                              padding:
                                  const EdgeInsets
                                      .all(4),
                              child:
                                  InteractiveViewer(
                                minScale: 1,
                                maxScale: 6,
                                boundaryMargin:
                                    const EdgeInsets
                                        .all(100),
                                clipBehavior:
                                    Clip.hardEdge,
                                child: Image.file(
                                  File(
                                    sourceImagePaths[
                                        previewIndex],
                                  ),
                                  width:
                                      double.infinity,
                                  height:
                                      double.infinity,
                                  fit:
                                      BoxFit.contain,
                                  filterQuality:
                                      FilterQuality
                                          .high,
                                  errorBuilder: (
                                    _,
                                    __,
                                    ___,
                                  ) {
                                    return const Center(
                                      child: Text(
                                        'تعذر عرض الصفحة',
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: IconButton.filled(
                              tooltip:
                                  'حذف الصفحة',
                              onPressed: () =>
                                  _removeImage(
                                previewIndex,
                              ),
                              icon: const Icon(
                                Icons.delete_outline,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (hasImages) ...[
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed:
                        previewIndex > 0
                            ? () {
                                setState(() {
                                  previewIndex--;
                                });
                              }
                            : null,
                    icon: const Icon(
                      Icons.chevron_right,
                    ),
                  ),
                  Text(
                    'الصفحة ${previewIndex + 1} '
                    'من ${sourceImagePaths.length}',
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: previewIndex <
                            sourceImagePaths
                                    .length -
                                1
                        ? () {
                            setState(() {
                              previewIndex++;
                            });
                          }
                        : null,
                    icon: const Icon(
                      Icons.chevron_left,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection:
                      Axis.horizontal,
                  itemCount:
                      sourceImagePaths.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final selected =
                        index == previewIndex;

                    return InkWell(
                      onTap: () {
                        setState(() {
                          previewIndex = index;
                        });
                      },
                      child: Container(
                        width: 62,
                        padding:
                            const EdgeInsets.all(3),
                        decoration:
                            BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(
                            8,
                          ),
                          border: Border.all(
                            color: selected
                                ? const Color(
                                    0xFF24528A,
                                  )
                                : const Color(
                                    0xFFDCE6F2,
                                  ),
                            width:
                                selected ? 2 : 1,
                          ),
                        ),
                        child: Image.file(
                          File(
                            sourceImagePaths[
                                index],
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF2F6FB),
      appBar: AppBar(
        title: const Text(
          'نظام الأرشفة Standard',
        ),
        backgroundColor:
            const Color(0xFF173A64),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'البحث',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const DocumentSearchScreen(),
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'الملفات حسب الحالة',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const DocumentsByStatusScreen(),
                ),
              );
            },
            icon: const Icon(
              Icons.fact_check_outlined,
            ),
          ),
          IconButton(
            tooltip: 'التنبيهات',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const RemindersScreen(),
                ),
              );
            },
            icon: const Icon(
              Icons.notifications_outlined,
            ),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: _logout,
            icon: const Icon(
              Icons.logout,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              constraints.maxWidth >= 1050;

          if (wide) {
            return Padding(
              padding:
                  const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child:
                        _buildPreviewPanel(),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child:
                        SingleChildScrollView(
                      child:
                          _buildFormPanel(),
                    ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding:
                const EdgeInsets.all(14),
            child: Column(
              children: [
                SizedBox(
                  height: 590,
                  child:
                      _buildPreviewPanel(),
                ),
                const SizedBox(height: 14),
                _buildFormPanel(),
              ],
            ),
          );
        },
      ),
    );
  }
}
