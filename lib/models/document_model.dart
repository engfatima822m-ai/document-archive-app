class DocumentModel {
  final int? id;
  final String documentNumber;
  final String documentDate;
  final String documentTitle;
  final String? category;
  final String notes;
  final String status;
  final String? reminderDate;
  final String? reminderNote;
  final String folderPath;
  final List<String> imagePaths;

  // حتى نعرف التنبيه من جدول documents لو document_attachments
  final String recordType;

  DocumentModel({
    this.id,
    required this.documentNumber,
    required this.documentDate,
    required this.documentTitle,
    this.category,
    required this.notes,
    required this.status,
    this.reminderDate,
    this.reminderNote,
    required this.folderPath,
    required this.imagePaths,
    this.recordType = 'main',
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}'),
      documentNumber: json['document_number']?.toString() ?? '',
      documentDate: json['document_date']?.toString() ?? '',
      documentTitle: json['document_title']?.toString() ?? '',
      category: json['category']?.toString(),
      notes: json['notes']?.toString() ?? '',
      status: json['status']?.toString() ?? 'قيد الإنجاز',
      reminderDate: json['reminder_date']?.toString(),
      reminderNote: json['reminder_note']?.toString(),
      folderPath: json['folder_path']?.toString() ?? '',
      imagePaths: json['image_paths'] is List
          ? List<String>.from(json['image_paths'].map((e) => e.toString()))
          : [],
      recordType: json['record_type']?.toString() ?? 'main',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "id": id,
      "document_number": documentNumber,
      "document_date": documentDate,
      "document_title": documentTitle,
      "category": category,
      "notes": notes,
      "status": status,
      "reminder_date": reminderDate,
      "reminder_note": reminderNote,
      "folder_path": folderPath,
      "image_paths": imagePaths,
      "record_type": recordType,
    };
  }
}