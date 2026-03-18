import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatefulWidget {
  final ChatMessage message;
  const MessageBubble({super.key, required this.message});

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnim = CurvedAnimation(
        parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: Offset(widget.message.isUser ? 0.05 : -0.05, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(
        ClipboardData(text: widget.message.content));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 6),
          child: msg.isUser
              ? _UserMessage(msg: msg)
              : _AiMessage(
                  msg: msg,
                  onCopy: _copyToClipboard,
                  copied: _copied,
                ),
        ),
      ),
    );
  }
}

// ── 사용자 메시지 ────────────────────────────────────────────
class _UserMessage extends StatelessWidget {
  final ChatMessage msg;
  const _UserMessage({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1E3A5F),
                  Color(0xFF1A2F50),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
              border: Border.all(
                  color: AppTheme.accentBlue.withOpacity(0.3)),
            ),
            child: Text(
              msg.content,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.accentBlue, Color(0xFF1D4ED8)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.person, color: Colors.white, size: 16),
        ),
      ],
    );
  }
}

// ── AI 메시지 ────────────────────────────────────────────────
class _AiMessage extends StatelessWidget {
  final ChatMessage msg;
  final VoidCallback onCopy;
  final bool copied;

  const _AiMessage({
    required this.msg,
    required this.onCopy,
    required this.copied,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // AI 아바타
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: msg.isAgent
                  ? [AppTheme.accentAmber, const Color(0xFFD97706)]
                  : [AppTheme.accentCyan, AppTheme.accentBlue],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: (msg.isAgent
                        ? AppTheme.accentAmber
                        : AppTheme.accentCyan)
                    .withOpacity(0.3),
                blurRadius: 8,
              ),
            ],
          ),
          child: Icon(
            msg.isAgent ? Icons.psychology : Icons.auto_awesome,
            color: Colors.white,
            size: 16,
          ),
        ),

        const SizedBox(width: 10),

        // 메시지 본문
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 모드 레이블
              Row(
                children: [
                  Text(
                    msg.isAgent ? 'Agent' : 'RAG',
                    style: TextStyle(
                      color: msg.isAgent
                          ? AppTheme.accentAmber
                          : AppTheme.accentCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('HH:mm').format(msg.timestamp),
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.aiBubble,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                child: msg.isStreaming && msg.content.isEmpty
                    ? _TypingIndicator()
                    : msg.isError
                        ? _ErrorContent(msg.content)
                        : MarkdownBody(
                            data: msg.content,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                height: 1.6,
                              ),
                              h1: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                              h2: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              h3: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              strong: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                              em: const TextStyle(
                                color: AppTheme.accentCyan,
                                fontStyle: FontStyle.italic,
                              ),
                              code: TextStyle(
                                color: AppTheme.accentGreen,
                                backgroundColor:
                                    AppTheme.bgCard,
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: AppTheme.bgCard,
                                borderRadius:
                                    BorderRadius.circular(8),
                                border: Border.all(
                                    color: AppTheme.borderColor),
                              ),
                              listBullet: const TextStyle(
                                color: AppTheme.accentCyan,
                              ),
                              blockquoteDecoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: AppTheme.accentCyan
                                        .withOpacity(0.5),
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
              ),

              // 복사 버튼
              if (!msg.isStreaming && msg.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: GestureDetector(
                    onTap: onCopy,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          copied
                              ? Icons.check_circle_outline
                              : Icons.copy_outlined,
                          size: 12,
                          color: copied
                              ? AppTheme.accentGreen
                              : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          copied ? '복사됨' : '복사',
                          style: TextStyle(
                            color: copied
                                ? AppTheme.accentGreen
                                : AppTheme.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (i) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      )..repeat(
          reverse: true,
          period: Duration(milliseconds: 600 + i * 150),
        ),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _controllers[i],
          builder: (_, __) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 6,
            height: 6 + _controllers[i].value * 4,
            decoration: BoxDecoration(
              color: AppTheme.accentCyan
                  .withOpacity(0.5 + _controllers[i].value * 0.5),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}

class _ErrorContent extends StatelessWidget {
  final String content;
  const _ErrorContent(this.content);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline,
            color: Colors.redAccent, size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            content,
            style: const TextStyle(
              color: Colors.redAccent,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
