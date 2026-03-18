import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';  // kIsWeb 임포트 추가

class ApiService {
  // RAG Server 직접 연결 (nginx 프록시 통해)
  //static const String _baseUrl = '/api';
  static String get _baseUrl {
    if (kIsWeb) return '/api';
    return 'http://192.168.0.15:8080';  // ← /api 포함
  }
  

  // ── RAG 쿼리 (스트리밍) ─────────────────────────────────
  static Stream<String> ragQueryStream({
    required String query,
    required String sessionId,
  }) async* {
    final uri = Uri.parse('$_baseUrl/rag/query');
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({'query': query, 'session_id': sessionId});

    try {
      final response = await request.send();
      if (response.statusCode != 200) {
        yield '오류가 발생했습니다. (HTTP ${response.statusCode})';
        return;
      }

      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.isNotEmpty) yield chunk;
      }

      // 스트림이 줄바꿈 없이 오는 경우 처리
    } catch (e) {
      // 스트리밍 바이트 방식으로 재시도
      final response2 = await request.send();
      final buffer = StringBuffer();
      await for (final bytes in response2.stream) {
        buffer.write(utf8.decode(bytes));
        yield utf8.decode(bytes);
      }
    }
  }

  // ── RAG 쿼리 (일반, 전체 응답) ──────────────────────────
  static Future<String> ragQuery({
    required String query,
    required String sessionId,
  }) async {
    final uri = Uri.parse('$_baseUrl/rag/query');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'query': query, 'session_id': sessionId}),
    ).timeout(const Duration(seconds: 180)); 
	
    if (response.statusCode == 200) {
      return utf8.decode(response.bodyBytes);
    }
    throw Exception('RAG 쿼리 실패: ${response.statusCode}');
  }

  // ── Agent 쿼리 ───────────────────────────────────────────
  static Future<String> agentQuery(String query) async {
    final uri = Uri.parse('$_baseUrl/agent/query');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'query': query}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data['answer'] ?? '응답 없음';
    }
    throw Exception('Agent 쿼리 실패: ${response.statusCode}');
  }

  // ── 헬스체크 ─────────────────────────────────────────────
  static Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse('$_baseUrl/health');
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
