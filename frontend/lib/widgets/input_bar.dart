import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chat_provider.dart';
import '../theme/app_theme.dart';

class InputBar extends StatefulWidget {
  final Function(String) onSend;
  final bool isLoading;
  final QueryMode mode;

  const InputBar({
    super.key,
    required this.onSend,
    required this.isLoading,
    required this.mode,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      setState(() => _hasText = _ctrl.text.trim().isNotEmpty);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.isLoading) return;
    widget.onSend(text);
    _ctrl.clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isRag = widget.mode == QueryMode.rag;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(
          top: BorderSide(color: AppTheme.borderColor),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 모드 힌트
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  isRag ? Icons.search : Icons.psychology,
                  size: 12,
                  color: isRag ? AppTheme.accentCyan : AppTheme.accentAmber,
                ),
                const SizedBox(width: 6),
                Text(
                  isRag
                      ? '문서 기반 RAG 검색 모드 — 색인된 문서에서 답변을 찾습니다'
                      : 'Agent 모드 — RAG 검색, DB 조회, 계산 등 다중 도구 추론',
                  style: TextStyle(
                    color: isRag
                        ? AppTheme.accentCyan.withOpacity(0.7)
                        : AppTheme.accentAmber.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // 입력 영역
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _send();
                    }
                  },
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focusNode,
                    maxLines: 5,
                    minLines: 1,
                    enabled: !widget.isLoading,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                    decoration: InputDecoration(
                      hintText: isRag
                          ? '문서에 대해 질문하세요... (Enter 전송, Shift+Enter 줄바꿈)'
                          : 'Agent에게 질문하세요...',
                      hintStyle: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppTheme.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppTheme.borderColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isRag
                              ? AppTheme.accentCyan
                              : AppTheme.accentAmber,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: AppTheme.bgDark,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // 전송 버튼
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: widget.isLoading
                    ? Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.bgDark,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.borderColor),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accentCyan,
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: _hasText ? _send : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: _hasText
                                ? LinearGradient(
                                    colors: isRag
                                        ? [
                                            AppTheme.accentCyan,
                                            AppTheme.accentBlue
                                          ]
                                        : [
                                            AppTheme.accentAmber,
                                            const Color(0xFFD97706)
                                          ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: _hasText ? null : AppTheme.bgDark,
                            borderRadius: BorderRadius.circular(12),
                            border: _hasText
                                ? null
                                : Border.all(color: AppTheme.borderColor),
                            boxShadow: _hasText
                                ? [
                                    BoxShadow(
                                      color: (isRag
                                              ? AppTheme.accentCyan
                                              : AppTheme.accentAmber)
                                          .withOpacity(0.3),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            Icons.send_rounded,
                            color: _hasText
                                ? Colors.white
                                : AppTheme.textMuted,
                            size: 18,
                          ),
                        ),
                      ),
              ),
            ],
          ),

          // 하단 안내
          const SizedBox(height: 8),
          const Text(
            'AI가 생성한 답변은 참고용입니다. 중요한 결정에는 전문가 확인을 권장합니다.',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
