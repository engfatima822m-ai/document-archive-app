import 'package:flutter/material.dart';

import '../models/document_model.dart';
import '../services/api_service.dart';
import '../services/print_service.dart';

class DocumentsByStatusScreen
    extends StatefulWidget {
  const DocumentsByStatusScreen({
    super.key,
  });

  @override
  State<DocumentsByStatusScreen>
      createState() =>
          _DocumentsByStatusScreenState();
}

class _DocumentsByStatusScreenState
    extends State<DocumentsByStatusScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabController;

  final statuses = const [
    'منجز',
    'قيد الإنجاز',
    'تم الاطلاع',
  ];

  final Map<String, List<DocumentModel>>
      documentsByStatus = {
    'منجز': [],
    'قيد الإنجاز': [],
    'تم الاطلاع': [],
  };

  final Map<String, int> currentPages = {
    'منجز': 0,
    'قيد الإنجاز': 0,
    'تم الاطلاع': 0,
  };

  final Map<String, int> totalPages = {
    'منجز': 0,
    'قيد الإنجاز': 0,
    'تم الاطلاع': 0,
  };

  final Map<String, bool> loading = {
    'منجز': false,
    'قيد الإنجاز': false,
    'تم الاطلاع': false,
  };

  @override
  void initState() {
    super.initState();

    tabController = TabController(
      length: statuses.length,
      vsync: this,
      initialIndex: 1,
    );

    tabController.addListener(
      _handleTabChanged,
    );

    loadStatus(
      statuses[tabController.index],
      refresh: true,
    );
  }

  @override
  void dispose() {
    tabController.removeListener(
      _handleTabChanged,
    );

    tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (tabController.indexIsChanging) {
      return;
    }

    final status =
        statuses[tabController.index];

    if (documentsByStatus[status]!.isEmpty) {
      loadStatus(
        status,
        refresh: true,
      );
    }
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

  int? parseInt(dynamic value) {
    if (value is int) return value;

    return int.tryParse(
      value?.toString() ?? '',
    );
  }

  Future<void> loadStatus(
    String status, {
    bool refresh = false,
  }) async {
    if (loading[status] == true) {
      return;
    }

    final nextPage = refresh
        ? 1
        : (currentPages[status] ?? 0) + 1;

    setState(() {
      loading[status] = true;
    });

    try {
      final response =
          await ApiService.getJson(
        'get_documents.php',
        queryParameters: {
          'status': status,
          'page': nextPage,
          'per_page': 25,
        },
      );

      final rawDocuments =
          response['documents'];

      final parsed =
          <DocumentModel>[];

      if (rawDocuments is List) {
        for (final rawDocument
            in rawDocuments) {
          if (rawDocument is! Map) {
            continue;
          }

          parsed.add(
            DocumentModel.fromJson(
              Map<String, dynamic>.from(
                rawDocument,
              ),
            ),
          );
        }
      }

      final rawPagination =
          response['pagination'];

      final pagination =
          rawPagination is Map
              ? Map<String, dynamic>.from(
                  rawPagination,
                )
              : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        if (refresh) {
          documentsByStatus[status] =
              parsed;
        } else {
          documentsByStatus[status]!
              .addAll(parsed);
        }

        currentPages[status] =
            parseInt(
              pagination['page'],
            ) ??
            nextPage;

        totalPages[status] =
            parseInt(
              pagination['total_pages'],
            ) ??
            0;
      });
    } on ApiException catch (exception) {
      showMessage(
        exception.message,
        isError: true,
      );
    } catch (exception) {
      showMessage(
        'تعذر جلب الملفات: $exception',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          loading[status] = false;
        });
      }
    }
  }

  Future<void> printPdf(
    DocumentModel document,
  ) async {
    if (!document.hasPdf) {
      showMessage(
        'لا يوجد PDF مرتبط بهذا الملف.',
        isError: true,
      );
      return;
    }

    if (document.id == null) {
      showMessage(
        'معرّف الملف غير صحيح.',
        isError: true,
      );
      return;
    }

    try {
      final bytes =
          await ApiService.getPdfBytes(
        id: document.id!,
        recordType: 'main',
      );

      if (!mounted) return;
      await PrintService.printPdf(
        context,
        bytes: bytes,
        name: '${document.documentNumber}.pdf',
      );
    } on ApiException catch (exception) {
      showMessage(
        exception.message,
        isError: true,
      );
    } catch (exception) {
      showMessage(
        'تعذر تنفيذ الطباعة: $exception',
        isError: true,
      );
    }
  }

  Future<void> showDetails(
    DocumentModel document,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            document.documentTitle,
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  detailRow(
                    'رقم الملف',
                    document.documentNumber,
                  ),
                  detailRow(
                    'تاريخ الملف',
                    document.documentDate,
                  ),
                  detailRow(
                    'الحالة',
                    document.status,
                  ),
                  detailRow(
                    'عدد الصفحات',
                    document.pageCount
                            ?.toString() ??
                        '-',
                  ),
                  detailRow(
                    'الكتب التابعة',
                    document.attachmentsCount
                        .toString(),
                  ),
                  detailRow(
                    'الملاحظات',
                    document.notes.isEmpty
                        ? '-'
                        : document.notes,
                  ),
                  detailRow(
                    'تاريخ التنبيه',
                    document.reminderDate ??
                        '-',
                  ),
                  detailRow(
                    'ملاحظة التنبيه',
                    document.reminderNote ??
                        '-',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop();
              },
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: document.hasPdf
                  ? () {
                      Navigator.of(
                        dialogContext,
                      ).pop();

                      printPdf(document);
                    }
                  : null,
              icon: const Icon(
                Icons.picture_as_pdf,
              ),
              label: const Text(
                'طباعة PDF',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget detailRow(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF173A64),
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Widget emptyState(String status) {
    return Center(
      child: Column(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          const Icon(
            Icons.folder_off_outlined,
            size: 70,
            color: Color(0xFF7890AC),
          ),
          const SizedBox(height: 14),
          Text(
            'لا توجد ملفات ضمن «$status»',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF173A64),
            ),
          ),
        ],
      ),
    );
  }

  Widget documentCard(
    DocumentModel document,
  ) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(14),
        side: const BorderSide(
          color: Color(0xFFDCE6F2),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        onTap: () =>
            showDetails(document),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color:
                const Color(0xFFE2ECF8),
            borderRadius:
                BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.description_outlined,
            color: Color(0xFF24528A),
          ),
        ),
        title: Text(
          document.documentTitle,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF173A64),
          ),
        ),
        subtitle: Padding(
          padding:
              const EdgeInsets.only(
            top: 7,
          ),
          child: Wrap(
            spacing: 12,
            runSpacing: 5,
            children: [
              Text(
                'الرقم: '
                '${document.documentNumber}',
              ),
              Text(
                'التاريخ: '
                '${document.documentDate}',
              ),
              Text(
                'الصفحات: '
                '${document.pageCount ?? '-'}',
              ),
              Text(
                'الكتب التابعة: '
                '${document.attachmentsCount}',
              ),
            ],
          ),
        ),
        trailing: IconButton(
          tooltip: 'طباعة PDF',
          onPressed: document.hasPdf
              ? () => printPdf(document)
              : null,
          icon: Icon(
            Icons.picture_as_pdf,
            color: document.hasPdf
                ? const Color(0xFFC62828)
                : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget statusList(String status) {
    final documents =
        documentsByStatus[status]!;

    final isLoading =
        loading[status] == true;

    if (documents.isEmpty &&
        isLoading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (documents.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => loadStatus(
          status,
          refresh: true,
        ),
        child: ListView(
          children: [
            SizedBox(
              height: 500,
              child: emptyState(status),
            ),
          ],
        ),
      );
    }

    final canLoadMore =
        (currentPages[status] ?? 0) <
            (totalPages[status] ?? 0);

    return RefreshIndicator(
      onRefresh: () => loadStatus(
        status,
        refresh: true,
      ),
      child: ListView.builder(
        padding:
            const EdgeInsets.all(16),
        itemCount: documents.length +
            (canLoadMore ? 1 : 0),
        itemBuilder: (_, index) {
          if (index <
              documents.length) {
            return documentCard(
              documents[index],
            );
          }

          return Padding(
            padding:
                const EdgeInsets.all(12),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: isLoading
                    ? null
                    : () => loadStatus(
                          status,
                        ),
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.expand_more,
                      ),
                label: const Text(
                  'عرض المزيد',
                ),
              ),
            ),
          );
        },
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
          'الملفات حسب الحالة',
        ),
        backgroundColor:
            const Color(0xFF173A64),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () {
              final status = statuses[
                  tabController.index];

              loadStatus(
                status,
                refresh: true,
              );
            },
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
        bottom: TabBar(
          controller: tabController,
          labelColor: Colors.white,
          unselectedLabelColor:
              const Color(0xFFBED0E5),
          indicatorColor: Colors.white,
          tabs: statuses
              .map(
                (status) => Tab(
                  text: status,
                ),
              )
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: statuses
            .map(statusList)
            .toList(),
      ),
    );
  }
}