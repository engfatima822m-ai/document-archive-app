class DocumentModel {
  final int? id;
  final String documentNumber;
  final String documentDate;
  final String documentTitle;
  final String notes;
  final String status;
  final String? reminderDate;
  final String? reminderNote;
  final String folderPath;
  final List<String> imagePaths;

  DocumentModel({
    this.id,
    required this.documentNumber,
    required this.documentDate,
    required this.documentTitle,
    required this.notes,
    required this.status,
    this.reminderDate,
    this.reminderNote,
    required this.folderPath,
    required this.imagePaths,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'],
      documentNumber: json['document_number'] ?? '',
      documentDate: json['document_date'] ?? '',
      documentTitle: json['document_title'] ?? '',
      notes: json['notes'] ?? '',
      status: json['status'] ?? 'قيد الإنجاز',
      reminderDate: json['reminder_date'],
      reminderNote: json['reminder_note'],
      folderPath: json['folder_path'] ?? '',
      imagePaths: json['image_paths'] != null
          ? List<String>.from(json['image_paths'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "document_number": documentNumber,
      "document_date": documentDate,
      "document_title": documentTitle,
      "notes": notes,
      "status": status,
      "reminder_date": reminderDate,
      "reminder_note": reminderNote,
      "folder_path": folderPath,
      "image_paths": imagePaths,
    };
  }
}