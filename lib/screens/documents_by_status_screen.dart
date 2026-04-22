import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class DocumentsByStatusScreen extends StatefulWidget {
  const DocumentsByStatusScreen({super.key});

  @override
  State<DocumentsByStatusScreen> createState() =>
      _DocumentsByStatusScreenState();
}

class _DocumentsByStatusScreenState
    extends State<DocumentsByStatusScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tabController;

  List<dynamic> allDocuments = [];
  bool isLoading = true;

  final String baseUrl = "http://localhost/document_api";

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    try {
      final response =
          await http.get(Uri.parse("$baseUrl/get_documents.php"));

      final data = jsonDecode(response.body);

      if (data['success'] == true) {
        setState(() {
          allDocuments = data['documents'];
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  List<dynamic> _filterByStatus(String status) {
    return allDocuments.where((doc) {
      return (doc['status'] ?? '') == status;
    }).toList();
  }

  Widget _buildList(List<dynamic> docs) {
    if (docs.isEmpty) {
      return const Center(child: Text("لا توجد بيانات"));
    }

    return ListView.builder(
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];

        return Card(
          margin: const EdgeInsets.all(8),
          child: ListTile(
            title: Text(doc['document_title'] ?? ''),
            subtitle: Text(doc['document_number'] ?? ''),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.pop(context, doc);
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("عرض الملفات"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "منجز"),
            Tab(text: "قيد الإنجاز"),
            Tab(text: "تم الاطلاع"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildList(_filterByStatus("منجز")),
                _buildList(_filterByStatus("قيد الإنجاز")),
                _buildList(_filterByStatus("تم الاطلاع")),
              ],
            ),
    );
  }
}