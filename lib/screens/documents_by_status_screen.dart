import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DocumentsByStatusScreen extends StatefulWidget {
  const DocumentsByStatusScreen({super.key});

  @override
  State<DocumentsByStatusScreen> createState() =>
      _DocumentsByStatusScreenState();
}

class _DocumentsByStatusScreenState extends State<DocumentsByStatusScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<dynamic> allDocuments = [];
  bool isLoading = true;

  final String baseUrl = "http://localhost/document_api";

  final Color bgColor = const Color(0xFFEAF6FF);
  final Color cardColor = Colors.white;
  final Color accentColor = const Color(0xFF1976D2);
  final Color accentLightColor = const Color(0xFF5CB6FF);
  final Color accentDarkColor = const Color(0xFF0D47A1);
  final Color softTextColor = const Color(0xFF5F7FA6);
  final Color borderColor = const Color(0xFFB8D9F7);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadDocuments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    try {
      final response = await http.get(Uri.parse("$baseUrl/get_documents.php"));
      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        setState(() {
          allDocuments = data['documents'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  List<dynamic> _filterByStatus(String status) {
    return allDocuments.where((doc) {
      return (doc['status'] ?? '').toString().trim() == status;
    }).toList();
  }

  LinearGradient get _mainGradient => LinearGradient(
        colors: [accentColor, accentLightColor],
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
      );

  Widget _buildEmptyState(String status) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        margin: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor.withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 58, color: accentColor),
            const SizedBox(height: 14),
            Text(
              "لا توجد ملفات بحالة $status",
              style: TextStyle(
                color: accentDarkColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "عند حفظ ملفات بهذه الحالة ستظهر هنا تلقائيًا.",
              textAlign: TextAlign.center,
              style: TextStyle(color: softTextColor, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<dynamic> docs, String status) {
    if (docs.isEmpty) return _buildEmptyState(status);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: docs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final doc = docs[index];

        final number = (doc['document_number'] ?? '').toString();
        final title = (doc['document_title'] ?? '').toString();
        final date = (doc['document_date'] ?? '').toString();
        final notes = (doc['notes'] ?? '').toString();

        return InkWell(
          onTap: () => Navigator.pop(context, doc),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardColor.withOpacity(0.94),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: _mainGradient,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        title.isEmpty ? "بدون عنوان" : title,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: accentDarkColor,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "رقم الملف: ${number.isEmpty ? '-' : number}",
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: softTextColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (date.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          "التأريخ: $date",
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: softTextColor,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                      if (notes.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          notes,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: softTextColor,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_left_rounded, color: accentColor, size: 28),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFEAF6FF), const Color(0xFFD6ECFF)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back_rounded, color: accentDarkColor),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "عرض الملفات",
                    style: TextStyle(
                      color: accentDarkColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "الملفات مرتبة حسب الحالة",
                    style: TextStyle(
                      color: softTextColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: _mainGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.folder_open, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.75),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: _mainGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: accentDarkColor,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
              tabs: const [
                Tab(text: "منجز"),
                Tab(text: "قيد الإنجاز"),
                Tab(text: "تم الاطلاع"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: isLoading
                    ? Center(
                        child: CircularProgressIndicator(color: accentColor),
                      )
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildList(_filterByStatus("منجز"), "منجز"),
                          _buildList(
                              _filterByStatus("قيد الإنجاز"), "قيد الإنجاز"),
                          _buildList(
                              _filterByStatus("تم الاطلاع"), "تم الاطلاع"),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}