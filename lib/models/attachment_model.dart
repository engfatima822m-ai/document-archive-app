class AttachmentModel {
  final int? id;

  final int parentDocumentId;
  final String? parentDocumentNumber;
  final String? parentDocumentTitle;

  final String subDocumentNumber;
  final String subDocumentDate;
  final String subDocumentTitle;

  final String notes;
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

  final int version;
  final String recordType;

  final String? createdAt;
  final String? updatedAt;

  const AttachmentModel({
    this.id,
    required this.parentDocumentId,
    this.parentDocumentNumber,
    this.parentDocumentTitle,
    required this.subDocumentNumber,
    required this.subDocumentDate,
    required this.subDocumentTitle,
    this.notes = '',
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
    this.version = 1,
    this.recordType = 'attachment',
    this.createdAt,
    this.updatedAt,
  });

  static int? _parseNullableInt(
    dynamic value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(
      value.toString(),
    );
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

  factory AttachmentModel.fromJson(
    Map<String, dynamic> json,
  ) {
    final parent = json['parent'];

    final parentMap =
        parent is Map<String, dynamic>
            ? parent
            : <String, dynamic>{};

    final pdfPath =
        json['pdf_relative_path']
            ?.toString();

    return AttachmentModel(
      id: _parseNullableInt(json['id']),
      parentDocumentId:
          _parseNullableInt(
            json['parent_document_id'] ??
                parentMap['id'],
          ) ??
          0,
      parentDocumentNumber:
          json['parent_document_number']
                  ?.toString() ??
              parentMap['document_number']
                  ?.toString(),
      parentDocumentTitle:
          json['parent_document_title']
                  ?.toString() ??
              parentMap['document_title']
                  ?.toString(),
      subDocumentNumber:
          json['sub_document_number']
                  ?.toString() ??
              json['document_number']
                  ?.toString() ??
              '',
      subDocumentDate:
          json['sub_document_date']
                  ?.toString() ??
              json['document_date']
                  ?.toString() ??
              '',
      subDocumentTitle:
          json['sub_document_title']
                  ?.toString() ??
              json['document_title']
                  ?.toString() ??
              '',
      notes:
          json['notes']?.toString() ?? '',
      reminderDate:
          json['reminder_date']
              ?.toString(),
      reminderNote:
          json['reminder_note']
              ?.toString(),
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
          json['scan_batch_id']
              ?.toString(),
      version:
          _parseNullableInt(
            json['version'],
          ) ??
          1,
      recordType:
          json['record_type']
                  ?.toString() ??
              'attachment',
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

    if (parentDocumentId < 1) {
      throw StateError(
        'معرّف الملف الأصلي غير صحيح.',
      );
    }

    if (folderPath.isEmpty) {
      throw StateError(
        'مسار مجلد الكتاب التابع غير محدد.',
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
      'parent_document_id':
          parentDocumentId,
      'sub_document_number':
          subDocumentNumber,
      'sub_document_date':
          subDocumentDate,
      'sub_document_title':
          subDocumentTitle,
      'notes':
          notes.trim().isEmpty ? null : notes,
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
        'معرّف الكتاب التابع غير صحيح.',
      );
    }

    return {
      'id': id,
      'version': version,
      'sub_document_number':
          subDocumentNumber,
      'sub_document_date':
          subDocumentDate,
      'sub_document_title':
          subDocumentTitle,
      'notes':
          notes.trim().isEmpty ? null : notes,
      'reminder_date': reminderDate,
      'reminder_note': reminderNote,
    };
  }

  AttachmentModel copyWith({
    int? id,
    int? parentDocumentId,
    String? parentDocumentNumber,
    String? parentDocumentTitle,
    String? subDocumentNumber,
    String? subDocumentDate,
    String? subDocumentTitle,
    String? notes,
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
    int? version,
    String? recordType,
    String? createdAt,
    String? updatedAt,
  }) {
    return AttachmentModel(
      id: id ?? this.id,
      parentDocumentId:
          parentDocumentId ??
          this.parentDocumentId,
      parentDocumentNumber:
          parentDocumentNumber ??
          this.parentDocumentNumber,
      parentDocumentTitle:
          parentDocumentTitle ??
          this.parentDocumentTitle,
      subDocumentNumber:
          subDocumentNumber ??
          this.subDocumentNumber,
      subDocumentDate:
          subDocumentDate ??
          this.subDocumentDate,
      subDocumentTitle:
          subDocumentTitle ??
          this.subDocumentTitle,
      notes: notes ?? this.notes,
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