import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_provider.dart';
import '../theme/app_theme.dart';
import 'message_bubble.dart';
import 'input_bar.dart';

class ChatArea extends StatefulWidget {
  const ChatArea({super.key});

  @override
  State<ChatArea> createState() => _ChatAreaState();
}

class _ChatAreaState extends State<ChatArea> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        final messages = provider.messages;

        // 새 메시지 시 스크롤
        if (messages.isNotEmpty) _scrollToBottom();

        return Column(
          children: [
            // 메시지 목록
            Expanded(
              child: messages.isEmpty
                  ? const _WelcomeView()
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 0, vertical: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        return MessageBubble(
                            message: messages[index]);
                      },
                    ),
            ),

            // 입력 바
            InputBar(
              onSend: (text) => provider.sendMessage(text),
              isLoading: provider.isLoading,
              mode: provider.mode,
            ),
          ],
        );
      },
    );
  }
}

class _WelcomeView extends StatelessWidget {
  const _WelcomeView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.accentCyan, AppTheme.accentBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentCyan.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 36),
          ),
          const SizedBox(height: 20),
          const Text(
            'AI RAG System',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'EXAONE 기반 문서 검색 & AI Agent',
            style: TextStyle(
              color: AppTheme.textSecond,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: const [
              _SuggestionChip('📄 문서 내용 검색'),
              _SuggestionChip('🤖 Agent 추론'),
              _SuggestionChip('🔒 PII 자동 마스킹'),
              _SuggestionChip('💬 멀티턴 대화'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  const _SuggestionChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.textSecond,
          fontSize: 13,
        ),
      ),
    );
  }
}
