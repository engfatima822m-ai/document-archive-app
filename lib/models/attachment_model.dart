class AttachmentModel {
  final int? id;
  final String parentDocumentNumber;
  final String subDocumentNumber;
  final String subDocumentDate;
  final String subDocumentTitle;
  final String notes;
  final String folderPath;
  final List<String> imagePaths;

  AttachmentModel({
    this.id,
    required this.parentDocumentNumber,
    required this.subDocumentNumber,
    required this.subDocumentDate,
    required this.subDocumentTitle,
    required this.notes,
    required this.folderPath,
    required this.imagePaths,
  });

  factory AttachmentModel.fromJson(Map<String, dynamic> json) {
    return AttachmentModel(
      id: json['id'],
      parentDocumentNumber: json['parent_document_number'],
      subDocumentNumber: json['sub_document_number'],
      subDocumentDate: json['sub_document_date'],
      subDocumentTitle: json['sub_document_title'],
      notes: json['notes'] ?? '',
      folderPath: json['folder_path'],
      imagePaths: json['image_paths'] != null
          ? List<String>.from(json['image_paths'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "parent_document_number": parentDocumentNumber,
      "sub_document_number": subDocumentNumber,
      "sub_document_date": subDocumentDate,
      "sub_document_title": subDocumentTitle,
      "notes": notes,
      "folder_path": folderPath,
      "image_paths": imagePaths,
    };
  }
}