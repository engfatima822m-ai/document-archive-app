class DocumentModel {
  final int? id;
  final String documentNumber;
  final String documentDate;
  final String documentTitle;
  final String notes;
  final String folderPath;
  final List<String> imagePaths;

  DocumentModel({
    this.id,
    required this.documentNumber,
    required this.documentDate,
    required this.documentTitle,
    required this.notes,
    required this.folderPath,
    required this.imagePaths,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'document_number': documentNumber,
      'document_date': documentDate,
      'document_title': documentTitle,
      'notes': notes,
      'folder_path': folderPath,
      'image_paths': imagePaths,
    };
  }

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}'),
      documentNumber: (json['document_number'] ?? '').toString(),
      documentDate: (json['document_date'] ?? '').toString(),
      documentTitle: (json['document_title'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      folderPath: (json['folder_path'] ?? '').toString(),
      imagePaths: json['image_paths'] != null
          ? List<String>.from(json['image_paths'])
          : [],
    );
  }
}