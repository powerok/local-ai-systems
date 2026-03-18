import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';

class DocumentInfo {
  final int id;
  final String source;
  final int chunkCount;
  final int piiCount;
  final DateTime indexedAt;

  DocumentInfo({
    required this.id,
    required this.source,
    required this.chunkCount,
    required this.piiCount,
    required this.indexedAt,
  });

  factory DocumentInfo.fromJson(Map<String, dynamic> json) {
    return DocumentInfo(
      id: json['id'] ?? 0,
      source: json['source'] ?? '',
      chunkCount: json['chunk_count'] ?? 0,
      piiCount: json['pii_count'] ?? 0,
      indexedAt: DateTime.tryParse(json['indexed_at'] ?? '') ?? DateTime.now(),
    );
  }

  String get fileName => source.split('/').last;
  String get fileType {
    final ext = source.split('.').last.toLowerCase();
    return ext;
  }
}

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  List<DocumentInfo> _documents = [];
  bool _loading = true;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<void> _loadDocuments() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.get(
        Uri.parse('/api/documents'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _documents = data.map((e) => DocumentInfo.fromJson(e)).toList();
          _loading = false;
        });
      } else {
        // API가 없는 경우 mock 데이터 표시
        setState(() {
          _documents = _mockDocuments();
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _documents = _mockDocuments();
        _loading = false;
      });
    }
  }

  List<DocumentInfo> _mockDocuments() => [
    DocumentInfo(
      id: 1,
      source: '/ai-system/data/test_doc.txt',
      chunkCount: 1,
      piiCount: 1,
      indexedAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
    DocumentInfo(
      id: 2,
      source: '/ai-system/data/사막의 빛.pdf',
      chunkCount: 2,
      piiCount: 0,
      indexedAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
    DocumentInfo(
      id: 3,
      source: '/ai-system/data/사막의 빛.docx',
      chunkCount: 2,
      piiCount: 0,
      indexedAt: DateTime.now().subtract(const Duration(hours: 1)),
    ),
  ];

  List<DocumentInfo> get _filtered => _searchQuery.isEmpty
      ? _documents
      : _documents
          .where((d) => d.source
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()))
          .toList();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '색인된 문서',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '총 ${_documents.length}개 문서 · '
                    '${_documents.fold(0, (s, d) => s + d.chunkCount)}개 청크',
                    style: const TextStyle(
                      color: AppTheme.textSecond,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh,
                    color: AppTheme.accentCyan, size: 20),
                onPressed: _loadDocuments,
                tooltip: '새로고침',
              ),
            ],
          ),
        ),

        // 통계 카드
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              _StatCard(
                icon: Icons.description_outlined,
                label: '총 문서',
                value: '${_documents.length}',
                color: AppTheme.accentCyan,
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.auto_awesome_mosaic,
                label: '총 청크',
                value: '${_documents.fold(0, (s, d) => s + d.chunkCount)}',
                color: AppTheme.accentBlue,
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.security,
                label: 'PII 마스킹',
                value: '${_documents.fold(0, (s, d) => s + d.piiCount)}건',
                color: AppTheme.accentGreen,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 검색
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: '파일명으로 검색...',
              prefixIcon: const Icon(Icons.search,
                  color: AppTheme.textMuted, size: 18),
              filled: true,
              fillColor: AppTheme.bgCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.accentCyan),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // 문서 목록
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accentCyan))
              : _filtered.isEmpty
                  ? const Center(
                      child: Text('문서가 없습니다',
                          style: TextStyle(color: AppTheme.textMuted)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) =>
                          _DocumentCard(doc: _filtered[i]),
                    ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final DocumentInfo doc;
  const _DocumentCard({required this.doc});

  Color get _typeColor {
    switch (doc.fileType) {
      case 'pdf': return Colors.redAccent;
      case 'docx': case 'doc': return AppTheme.accentBlue;
      case 'txt': case 'md': return AppTheme.accentGreen;
      default: return AppTheme.textMuted;
    }
  }

  IconData get _typeIcon {
    switch (doc.fileType) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'docx': case 'doc': return Icons.description;
      case 'txt': return Icons.text_snippet;
      case 'md': return Icons.article;
      default: return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _typeColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_typeIcon, color: _typeColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.fileName,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  doc.source,
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Badge('${doc.chunkCount}청크', AppTheme.accentBlue),
          const SizedBox(width: 6),
          if (doc.piiCount > 0)
            _Badge('PII ${doc.piiCount}', AppTheme.accentAmber),
          const SizedBox(width: 12),
          Text(
            DateFormat('MM/dd HH:mm').format(doc.indexedAt),
            style: const TextStyle(
                color: AppTheme.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
