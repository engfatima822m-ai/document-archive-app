import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../models/attachment_model.dart';
import '../models/document_model.dart';
import '../services/api_service.dart';

class SearchGroup {
  final DocumentModel parent;
  final List<AttachmentModel> attachments;

  const SearchGroup({
    required this.parent,
    required this.attachments,
  });
}

class DocumentSearchScreen
    extends StatefulWidget {
  const DocumentSearchScreen({super.key});

  @override
  State<DocumentSearchScreen> createState() =>
      _DocumentSearchScreenState();
}

class _DocumentSearchScreenState
    extends State<DocumentSearchScreen> {
  final searchController =
      TextEditingController();

  List<SearchGroup> groups = [];

  bool isLoading = false;
  int currentPage = 1;
  int totalPages = 0;
  int totalItems = 0;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void showMessage(
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

  Future<void> search({
    int page = 1,
  }) async {
    final query =
        searchController.text.trim();

    if (query.length < 2) {
      showMessage(
        'اكتبي حرفين على الأقل للبحث.',
        isError: true,
      );
      return;
    }

    if (isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      isLoading = true;
    });

    try {
      final response =
          await ApiService.getJson(
        'search_documents.php',
        queryParameters: {
          'query': query,
          'page': page,
          'per_page': 20,
        },
      );

      final rawGroups = response['groups'];

      final parsedGroups = <SearchGroup>[];

      if (rawGroups is List) {
        for (final rawGroup in rawGroups) {
          if (rawGroup is! Map) continue;

          final group =
              Map<String, dynamic>.from(
            rawGroup,
          );

          final rawParent = group['parent'];

          if (rawParent is! Map) continue;

          final parent =
              DocumentModel.fromJson(
            Map<String, dynamic>.from(
              rawParent,
            ),
          );

          final attachments =
              <AttachmentModel>[];

          final rawAttachments =
              group['attachments'];

          if (rawAttachments is List) {
            for (final rawAttachment
                in rawAttachments) {
              if (rawAttachment is! Map) {
                continue;
              }

              final attachment =
                  AttachmentModel.fromJson(
                Map<String, dynamic>.from(
                  rawAttachment,
                ),
              ).copyWith(
                parentDocumentId:
                    parent.id ?? 0,
                parentDocumentNumber:
                    parent.documentNumber,
                parentDocumentTitle:
                    parent.documentTitle,
              );

              attachments.add(attachment);
            }
          }

          parsedGroups.add(
            SearchGroup(
              parent: parent,
              attachments: attachments,
            ),
          );
        }
      }

      final paginationValue =
          response['pagination'];

      final pagination =
          paginationValue is Map
              ? Map<String, dynamic>.from(
                  paginationValue,
                )
              : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        groups = parsedGroups;
        currentPage =
            _parseInt(pagination['page']) ??
                page;
        totalPages = _parseInt(
              pagination['total_pages'],
            ) ??
            0;
        totalItems = _parseInt(
              pagination['total_items'],
            ) ??
            parsedGroups.length;
      });
    } on ApiException catch (exception) {
      showMessage(
        exception.message,
        isError: true,
      );
    } catch (exception) {
      showMessage(
        'تعذر تنفيذ البحث: $exception',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;

    return int.tryParse(
      value?.toString() ?? '',
    );
  }

  Future<void> openPdf({
    required int? id,
    required String recordType,
  }) async {
    if (id == null || id < 1) {
      showMessage(
        'معرّف الملف غير صحيح.',
        isError: true,
      );
      return;
    }

    try {
      showMessage(
        'جاري تجهيز ملف PDF...',
      );

      final bytes =
          await ApiService.getPdfBytes(
        id: id,
        recordType: recordType,
      );

      await Printing.layoutPdf(
        name: 'archive_document.pdf',
        onLayout: (_) async => bytes,
      );
    } on ApiException catch (exception) {
      showMessage(
        exception.message,
        isError: true,
      );
    } catch (exception) {
      showMessage(
        'تعذر فتح ملف PDF: $exception',
        isError: true,
      );
    }
  }

  Future<String?> pickDate(
    String? currentValue,
  ) async {
    final current =
        DateTime.tryParse(
          currentValue ?? '',
        ) ??
        DateTime.now();

    final selected = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );

    if (selected == null) return null;

    return '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
  }

  Future<void> editMainDocument(
    DocumentModel document,
  ) async {
    final numberController =
        TextEditingController(
      text: document.documentNumber,
    );

    final dateController =
        TextEditingController(
      text: document.documentDate,
    );

    final titleController =
        TextEditingController(
      text: document.documentTitle,
    );

    final notesController =
        TextEditingController(
      text: document.notes,
    );

    final reminderDateController =
        TextEditingController(
      text: document.reminderDate ?? '',
    );

    final reminderNoteController =
        TextEditingController(
      text: document.reminderNote ?? '',
    );

    var status = document.status;
    var saving = false;

    final saved =
        await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            dialogContext,
            setDialogState,
          ) {
            Future<void> submit() async {
              if (saving) return;

              if (numberController.text
                      .trim()
                      .isEmpty ||
                  dateController.text
                      .trim()
                      .isEmpty ||
                  titleController.text
                      .trim()
                      .isEmpty) {
                showMessage(
                  'الرقم والتاريخ والاسم مطلوبة.',
                  isError: true,
                );
                return;
              }

              final reminderDate =
                  reminderDateController.text
                      .trim();

              final reminderNote =
                  reminderNoteController.text
                      .trim();

              if (
                  (reminderDate.isEmpty &&
                      reminderNote.isNotEmpty) ||
                  (reminderDate.isNotEmpty &&
                      reminderNote.isEmpty)) {
                showMessage(
                  'أدخلي تاريخ وملاحظة '
                  'التنبيه معًا.',
                  isError: true,
                );
                return;
              }

              setDialogState(() {
                saving = true;
              });

              try {
                final updated =
                    document.copyWith(
                  documentNumber:
                      numberController.text
                          .trim(),
                  documentDate:
                      dateController.text
                          .trim(),
                  documentTitle:
                      titleController.text
                          .trim(),
                  notes: notesController.text
                      .trim(),
                  status: status,
                  reminderDate:
                      reminderDate.isEmpty
                          ? null
                          : reminderDate,
                  reminderNote:
                      reminderNote.isEmpty
                          ? null
                          : reminderNote,
                  clearReminderDate:
                      reminderDate.isEmpty,
                  clearReminderNote:
                      reminderNote.isEmpty,
                );

                await ApiService.postJson(
                  'update_document.php',
                  updated.toUpdateJson(),
                );

                if (!dialogContext.mounted) {
                  return;
                }

                Navigator.of(dialogContext)
                    .pop(true);
              } on ApiException catch (
                  exception) {
                showMessage(
                  exception.message,
                  isError: true,
                );

                setDialogState(() {
                  saving = false;
                });
              } catch (exception) {
                showMessage(
                  'تعذر التحديث: $exception',
                  isError: true,
                );

                setDialogState(() {
                  saving = false;
                });
              }
            }

            return AlertDialog(
              title: const Text(
                'تعديل الملف الرئيسي',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      TextField(
                        controller:
                            numberController,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'رقم الملف',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            dateController,
                        readOnly: true,
                        onTap: () async {
                          final date =
                              await pickDate(
                            dateController.text,
                          );

                          if (date != null) {
                            setDialogState(() {
                              dateController.text =
                                  date;
                            });
                          }
                        },
                        decoration:
                            const InputDecoration(
                          labelText:
                              'تاريخ الملف',
                          suffixIcon: Icon(
                            Icons.calendar_month,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            titleController,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'اسم الملف',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<
                          String>(
                        initialValue: status,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'حالة الملف',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value:
                                'قيد الإنجاز',
                            child: Text(
                              'قيد الإنجاز',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'منجز',
                            child:
                                Text('منجز'),
                          ),
                          DropdownMenuItem(
                            value:
                                'تم الاطلاع',
                            child: Text(
                              'تم الاطلاع',
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              status = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            notesController,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'الملاحظات',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            reminderDateController,
                        readOnly: true,
                        onTap: () async {
                          final date =
                              await pickDate(
                            reminderDateController
                                .text,
                          );

                          if (date != null) {
                            setDialogState(() {
                              reminderDateController
                                  .text = date;
                            });
                          }
                        },
                        decoration:
                            InputDecoration(
                          labelText:
                              'تاريخ التنبيه',
                          suffixIcon:
                              IconButton(
                            onPressed: () {
                              setDialogState(() {
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
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            reminderNoteController,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'ملاحظة التنبيه',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.of(
                            dialogContext,
                          ).pop(false);
                        },
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed:
                      saving ? null : submit,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    numberController.dispose();
    dateController.dispose();
    titleController.dispose();
    notesController.dispose();
    reminderDateController.dispose();
    reminderNoteController.dispose();

    if (saved == true) {
      showMessage(
        'تم تحديث الملف بنجاح.',
      );

      await search(page: currentPage);
    }
  }

  Future<void> editAttachment(
    AttachmentModel attachment,
  ) async {
    final numberController =
        TextEditingController(
      text: attachment.subDocumentNumber,
    );

    final dateController =
        TextEditingController(
      text: attachment.subDocumentDate,
    );

    final titleController =
        TextEditingController(
      text: attachment.subDocumentTitle,
    );

    final notesController =
        TextEditingController(
      text: attachment.notes,
    );

    final reminderDateController =
        TextEditingController(
      text: attachment.reminderDate ?? '',
    );

    final reminderNoteController =
        TextEditingController(
      text: attachment.reminderNote ?? '',
    );

    var saving = false;

    final saved =
        await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            dialogContext,
            setDialogState,
          ) {
            Future<void> submit() async {
              if (saving) return;

              if (numberController.text
                      .trim()
                      .isEmpty ||
                  dateController.text
                      .trim()
                      .isEmpty ||
                  titleController.text
                      .trim()
                      .isEmpty) {
                showMessage(
                  'الرقم والتاريخ والاسم مطلوبة.',
                  isError: true,
                );
                return;
              }

              final reminderDate =
                  reminderDateController.text
                      .trim();

              final reminderNote =
                  reminderNoteController.text
                      .trim();

              if (
                  (reminderDate.isEmpty &&
                      reminderNote.isNotEmpty) ||
                  (reminderDate.isNotEmpty &&
                      reminderNote.isEmpty)) {
                showMessage(
                  'أدخلي تاريخ وملاحظة '
                  'التنبيه معًا.',
                  isError: true,
                );
                return;
              }

              setDialogState(() {
                saving = true;
              });

              try {
                final updated =
                    attachment.copyWith(
                  subDocumentNumber:
                      numberController.text
                          .trim(),
                  subDocumentDate:
                      dateController.text
                          .trim(),
                  subDocumentTitle:
                      titleController.text
                          .trim(),
                  notes: notesController.text
                      .trim(),
                  reminderDate:
                      reminderDate.isEmpty
                          ? null
                          : reminderDate,
                  reminderNote:
                      reminderNote.isEmpty
                          ? null
                          : reminderNote,
                  clearReminderDate:
                      reminderDate.isEmpty,
                  clearReminderNote:
                      reminderNote.isEmpty,
                );

                await ApiService.postJson(
                  'update_attachment.php',
                  updated.toUpdateJson(),
                );

                if (!dialogContext.mounted) {
                  return;
                }

                Navigator.of(dialogContext)
                    .pop(true);
              } on ApiException catch (
                  exception) {
                showMessage(
                  exception.message,
                  isError: true,
                );

                setDialogState(() {
                  saving = false;
                });
              } catch (exception) {
                showMessage(
                  'تعذر التحديث: $exception',
                  isError: true,
                );

                setDialogState(() {
                  saving = false;
                });
              }
            }

            return AlertDialog(
              title: const Text(
                'تعديل الكتاب التابع',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      TextField(
                        controller:
                            numberController,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'رقم الكتاب التابع',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            dateController,
                        readOnly: true,
                        onTap: () async {
                          final date =
                              await pickDate(
                            dateController.text,
                          );

                          if (date != null) {
                            setDialogState(() {
                              dateController.text =
                                  date;
                            });
                          }
                        },
                        decoration:
                            const InputDecoration(
                          labelText:
                              'تاريخ الكتاب',
                          suffixIcon: Icon(
                            Icons.calendar_month,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            titleController,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'اسم الكتاب التابع',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            notesController,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'الملاحظات',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            reminderDateController,
                        readOnly: true,
                        onTap: () async {
                          final date =
                              await pickDate(
                            reminderDateController
                                .text,
                          );

                          if (date != null) {
                            setDialogState(() {
                              reminderDateController
                                  .text = date;
                            });
                          }
                        },
                        decoration:
                            InputDecoration(
                          labelText:
                              'تاريخ التنبيه',
                          suffixIcon:
                              IconButton(
                            onPressed: () {
                              setDialogState(() {
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
                      const SizedBox(height: 12),
                      TextField(
                        controller:
                            reminderNoteController,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'ملاحظة التنبيه',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () {
                          Navigator.of(
                            dialogContext,
                          ).pop(false);
                        },
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed:
                      saving ? null : submit,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('حفظ'),
                ),
              ],
            );
          },
        );
      },
    );

    numberController.dispose();
    dateController.dispose();
    titleController.dispose();
    notesController.dispose();
    reminderDateController.dispose();
    reminderNoteController.dispose();

    if (saved == true) {
      showMessage(
        'تم تحديث الكتاب التابع.',
      );

      await search(page: currentPage);
    }
  }

  Widget pdfButton({
    required int? id,
    required String recordType,
    required bool hasPdf,
  }) {
    return IconButton(
      tooltip: 'عرض أو طباعة PDF',
      onPressed: hasPdf
          ? () => openPdf(
                id: id,
                recordType: recordType,
              )
          : null,
      icon: Icon(
        Icons.picture_as_pdf,
        color: hasPdf
            ? const Color(0xFFC62828)
            : Colors.grey,
      ),
    );
  }

  Widget attachmentTile(
    AttachmentModel attachment,
  ) {
    return Card(
      color: const Color(0xFFF7FAFE),
      margin: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 5,
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor:
              Color(0xFFE0ECFA),
          child: Icon(
            Icons.attachment,
            color: Color(0xFF24528A),
          ),
        ),
        title: Text(
          attachment.subDocumentTitle,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          'الرقم: '
          '${attachment.subDocumentNumber}'
          '   |   التاريخ: '
          '${attachment.subDocumentDate}'
          '${attachment.pageCount == null ? '' : '   |   الصفحات: ${attachment.pageCount}'}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            pdfButton(
              id: attachment.id,
              recordType: 'attachment',
              hasPdf: attachment.hasPdf,
            ),
            IconButton(
              tooltip: 'تعديل',
              onPressed: () =>
                  editAttachment(attachment),
              icon: const Icon(
                Icons.edit_outlined,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget groupCard(SearchGroup group) {
    final document = group.parent;

    return Card(
      margin: const EdgeInsets.only(
        bottom: 14,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(14),
        side: const BorderSide(
          color: Color(0xFFDCE6F2),
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const CircleAvatar(
          backgroundColor:
              Color(0xFF24528A),
          foregroundColor: Colors.white,
          child: Icon(
            Icons.folder_outlined,
          ),
        ),
        title: Text(
          document.documentTitle,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF173A64),
          ),
        ),
        subtitle: Text(
          'الرقم: ${document.documentNumber}'
          '   |   التاريخ: ${document.documentDate}'
          '   |   الحالة: ${document.status}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            pdfButton(
              id: document.id,
              recordType: 'main',
              hasPdf: document.hasPdf,
            ),
            IconButton(
              tooltip: 'تعديل',
              onPressed: () =>
                  editMainDocument(document),
              icon: const Icon(
                Icons.edit_outlined,
              ),
            ),
            const Icon(
              Icons.expand_more,
            ),
          ],
        ),
        children: [
          if (document.notes.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(document.notes),
            ),
          if (group.attachments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'لا توجد كتب تابعة لهذا الملف.',
              ),
            )
          else
            ...group.attachments.map(
              attachmentTile,
            ),
          const SizedBox(height: 10),
        ],
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
          'البحث في الأرشيف',
        ),
        backgroundColor:
            const Color(0xFF173A64),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller:
                        searchController,
                    autofocus: true,
                    textInputAction:
                        TextInputAction.search,
                    onSubmitted: (_) =>
                        search(),
                    decoration:
                        InputDecoration(
                      labelText:
                          'رقم أو اسم الكتاب أو الملاحظات',
                      prefixIcon:
                          const Icon(
                        Icons.search,
                      ),
                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed:
                        isLoading ? null : search,
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.manage_search,
                          ),
                    label: const Text('بحث'),
                  ),
                ),
              ],
            ),
          ),
          if (totalItems > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                18,
                10,
                18,
                0,
              ),
              child: Align(
                alignment:
                    Alignment.centerRight,
                child: Text(
                  'عدد النتائج: $totalItems',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Expanded(
            child: isLoading
                ? const Center(
                    child:
                        CircularProgressIndicator(),
                  )
                : groups.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 70,
                              color:
                                  Color(0xFF8192A8),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'اكتبي كلمة للبحث في الأرشيف',
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.all(
                          18,
                        ),
                        itemCount:
                            groups.length,
                        itemBuilder:
                            (_, index) {
                          return groupCard(
                            groups[index],
                          );
                        },
                      ),
          ),
          if (totalPages > 1)
            Container(
              color: Colors.white,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'الصفحة السابقة',
                    onPressed: currentPage > 1
                        ? () => search(
                              page:
                                  currentPage - 1,
                            )
                        : null,
                    icon: const Icon(
                      Icons.chevron_right,
                    ),
                  ),
                  Text(
                    'صفحة $currentPage '
                    'من $totalPages',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    tooltip: 'الصفحة التالية',
                    onPressed:
                        currentPage < totalPages
                            ? () => search(
                                  page:
                                      currentPage +
                                          1,
                                )
                            : null,
                    icon: const Icon(
                      Icons.chevron_left,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}