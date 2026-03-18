import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../services/api_service.dart';

enum QueryMode { rag, agent }

class ChatProvider extends ChangeNotifier {
  final _uuid = const Uuid();

  List<ChatSession> _sessions = [];
  ChatSession? _currentSession;
  bool _isLoading = false;
  bool _serverOnline = false;
  QueryMode _mode = QueryMode.rag;

  List<ChatSession> get sessions => _sessions;
  ChatSession? get currentSession => _currentSession;
  bool get isLoading => _isLoading;
  bool get serverOnline => _serverOnline;
  QueryMode get mode => _mode;
  List<ChatMessage> get messages => _currentSession?.messages ?? [];

  ChatProvider() {
    _init();
  }

  Future<void> _init() async {
    await checkHealth();
    newSession();
  }

  // ── 헬스체크 ──────────────────────────────────────────────
  Future<void> checkHealth() async {
    _serverOnline = await ApiService.healthCheck();
    notifyListeners();
  }

  // ── 모드 전환 ─────────────────────────────────────────────
  void setMode(QueryMode mode) {
    _mode = mode;
    notifyListeners();
  }

  // ── 새 세션 ───────────────────────────────────────────────
  void newSession() {
    final session = ChatSession(
      id: _uuid.v4(),
      title: '새 대화',
    );
    // 시스템 환영 메시지
    session.messages.add(ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: 'AI RAG 시스템에 오신 것을 환영합니다! 🚀\n\n'
          '문서 기반 질문이나 AI Agent 추론을 활용해보세요.\n'
          '상단의 **RAG** / **Agent** 버튼으로 모드를 전환할 수 있습니다.',
    ));
    _sessions.insert(0, session);
    _currentSession = session;
    notifyListeners();
  }

  // ── 세션 선택 ─────────────────────────────────────────────
  void selectSession(ChatSession session) {
    _currentSession = session;
    notifyListeners();
  }

  // ── 세션 삭제 ─────────────────────────────────────────────
  void deleteSession(String sessionId) {
    _sessions.removeWhere((s) => s.id == sessionId);
    if (_currentSession?.id == sessionId) {
      if (_sessions.isEmpty) newSession();
      else _currentSession = _sessions.first;
    }
    notifyListeners();
  }

  // ── 메시지 전송 ───────────────────────────────────────────
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty || _isLoading) return;
    if (_currentSession == null) newSession();

    final session = _currentSession!;

    // 세션 제목 자동 설정 (첫 메시지)
    if (session.messages.length <= 1) {
      session.title = content.length > 30
          ? '${content.substring(0, 30)}...'
          : content;
    }

    // 사용자 메시지 추가
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: content,
    );
    session.messages.add(userMsg);
    session.updatedAt = DateTime.now();
    notifyListeners();

    // AI 응답 메시지 (스트리밍용 빈 메시지)
    final aiMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: '',
      status: MessageStatus.streaming,
      isAgent: _mode == QueryMode.agent,
    );
    session.messages.add(aiMsg);
    _isLoading = true;
    notifyListeners();

    try {
      if (_mode == QueryMode.agent) {
        // Agent 모드 — 단일 응답
        final answer = await ApiService.agentQuery(content);
        aiMsg.content = answer;
        aiMsg.status = MessageStatus.done;
      } else {
        // RAG 모드 — 스트리밍
        await _streamRagResponse(content, session.id, aiMsg);
      }
    } catch (e) {
      aiMsg.content = '⚠️ 오류가 발생했습니다: $e\n\n서버 연결을 확인해주세요.';
      aiMsg.status = MessageStatus.error;
    }

    _isLoading = false;
    session.updatedAt = DateTime.now();
    notifyListeners();
  }

  Future<void> _streamRagResponse(
    String query,
    String sessionId,
    ChatMessage aiMsg,
  ) async {
    final buffer = StringBuffer();

    // HTTP 스트리밍 (fetch API 방식)
    try {
      final fullResponse = await ApiService.ragQuery(
        query: query,
        sessionId: sessionId,
      );
      aiMsg.content = fullResponse;
      aiMsg.status = MessageStatus.done;
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }
}
