class DocumentModel {
  final int? id;

  final String documentNumber;
  final String documentDate;
  final String documentTitle;
  final String notes;
  final String status;

  final String? reminderDate;
  final String? reminderNote;

  final bool hasPdf;
  final String? relativeFolderPath;
  final String? pdfRelativePath;
  final int? pdfSizeBytes;
  final String? pdfSha256;
  final int? pageCount;

  final String scanMode;
  final String? scanBatchId;

  final int attachmentsCount;
  final int version;

  final String recordType;
  final String? createdAt;
  final String? updatedAt;

  const DocumentModel({
    this.id,
    required this.documentNumber,
    required this.documentDate,
    required this.documentTitle,
    this.notes = '',
    this.status = 'قيد الإنجاز',
    this.reminderDate,
    this.reminderNote,
    this.hasPdf = false,
    this.relativeFolderPath,
    this.pdfRelativePath,
    this.pdfSizeBytes,
    this.pdfSha256,
    this.pageCount,
    this.scanMode = 'single_document',
    this.scanBatchId,
    this.attachmentsCount = 0,
    this.version = 1,
    this.recordType = 'main',
    this.createdAt,
    this.updatedAt,
  });

  static int? _parseNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(value.toString());
  }

  static bool _parseBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is int) {
      return value == 1;
    }

    final normalized = value
        ?.toString()
        .trim()
        .toLowerCase();

    return normalized == '1' ||
        normalized == 'true';
  }

  factory DocumentModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final pdfPath =
        json['pdf_relative_path']?.toString();

    return DocumentModel(
      id: _parseNullableInt(json['id']),
      documentNumber:
          json['document_number']
                  ?.toString() ??
              '',
      documentDate:
          json['document_date']
                  ?.toString() ??
              '',
      documentTitle:
          json['document_title']
                  ?.toString() ??
              '',
      notes:
          json['notes']?.toString() ?? '',
      status:
          json['status']?.toString() ??
              'قيد الإنجاز',
      reminderDate:
          json['reminder_date']?.toString(),
      reminderNote:
          json['reminder_note']?.toString(),
      hasPdf:
          _parseBool(json['has_pdf']) ||
          (pdfPath != null &&
              pdfPath.trim().isNotEmpty),
      relativeFolderPath:
          json['relative_folder_path']
              ?.toString(),
      pdfRelativePath: pdfPath,
      pdfSizeBytes:
          _parseNullableInt(
            json['pdf_size_bytes'],
          ),
      pdfSha256:
          json['pdf_sha256']?.toString(),
      pageCount:
          _parseNullableInt(
            json['page_count'],
          ),
      scanMode:
          json['scan_mode']?.toString() ??
              'single_document',
      scanBatchId:
          json['scan_batch_id']?.toString(),
      attachmentsCount:
          _parseNullableInt(
            json['attachments_count'],
          ) ??
          0,
      version:
          _parseNullableInt(
            json['version'],
          ) ??
          1,
      recordType:
          json['record_type']?.toString() ??
              'main',
      createdAt:
          json['created_at']?.toString(),
      updatedAt:
          json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toCreateJson() {
    final folderPath =
        relativeFolderPath?.trim() ?? '';

    final pdfPath =
        pdfRelativePath?.trim() ?? '';

    final pages = pageCount ?? 0;

    if (folderPath.isEmpty) {
      throw StateError(
        'مسار مجلد الملف غير محدد.',
      );
    }

    if (pdfPath.isEmpty) {
      throw StateError(
        'مسار ملف PDF غير محدد.',
      );
    }

    if (pages < 1) {
      throw StateError(
        'عدد صفحات ملف PDF غير صحيح.',
      );
    }

    return {
      'document_number': documentNumber,
      'document_date': documentDate,
      'document_title': documentTitle,
      'notes':
          notes.trim().isEmpty ? null : notes,
      'status': status,
      'reminder_date': reminderDate,
      'reminder_note': reminderNote,
      'relative_folder_path': folderPath,
      'pdf': {
        'relative_path': pdfPath,
        'page_count': pages,
        if (pdfSha256 != null &&
            pdfSha256!.trim().isNotEmpty)
          'sha256': pdfSha256,
      },
      'scan_mode': scanMode,
      'scan_batch_id': scanBatchId,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    if (id == null || id! < 1) {
      throw StateError(
        'معرّف الملف غير صحيح.',
      );
    }

    return {
      'id': id,
      'version': version,
      'document_number': documentNumber,
      'document_date': documentDate,
      'document_title': documentTitle,
      'notes':
          notes.trim().isEmpty ? null : notes,
      'status': status,
      'reminder_date': reminderDate,
      'reminder_note': reminderNote,
    };
  }

  DocumentModel copyWith({
    int? id,
    String? documentNumber,
    String? documentDate,
    String? documentTitle,
    String? notes,
    String? status,
    String? reminderDate,
    String? reminderNote,
    bool clearReminderDate = false,
    bool clearReminderNote = false,
    bool? hasPdf,
    String? relativeFolderPath,
    String? pdfRelativePath,
    int? pdfSizeBytes,
    String? pdfSha256,
    int? pageCount,
    String? scanMode,
    String? scanBatchId,
    int? attachmentsCount,
    int? version,
    String? recordType,
    String? createdAt,
    String? updatedAt,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      documentNumber:
          documentNumber ??
          this.documentNumber,
      documentDate:
          documentDate ??
          this.documentDate,
      documentTitle:
          documentTitle ??
          this.documentTitle,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      reminderDate: clearReminderDate
          ? null
          : reminderDate ??
              this.reminderDate,
      reminderNote: clearReminderNote
          ? null
          : reminderNote ??
              this.reminderNote,
      hasPdf: hasPdf ?? this.hasPdf,
      relativeFolderPath:
          relativeFolderPath ??
          this.relativeFolderPath,
      pdfRelativePath:
          pdfRelativePath ??
          this.pdfRelativePath,
      pdfSizeBytes:
          pdfSizeBytes ??
          this.pdfSizeBytes,
      pdfSha256:
          pdfSha256 ??
          this.pdfSha256,
      pageCount:
          pageCount ?? this.pageCount,
      scanMode:
          scanMode ?? this.scanMode,
      scanBatchId:
          scanBatchId ??
          this.scanBatchId,
      attachmentsCount:
          attachmentsCount ??
          this.attachmentsCount,
      version: version ?? this.version,
      recordType:
          recordType ?? this.recordType,
      createdAt:
          createdAt ?? this.createdAt,
      updatedAt:
          updatedAt ?? this.updatedAt,
    );
  }
}