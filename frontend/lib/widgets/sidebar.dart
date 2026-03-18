import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/chat_provider.dart';
import '../models/chat_message.dart';
import '../theme/app_theme.dart';

class SidebarWidget extends StatelessWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            border: Border(
              right: BorderSide(color: AppTheme.borderColor),
            ),
          ),
          child: Column(
            children: [
              // 헤더
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppTheme.borderColor),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.history,
                        color: AppTheme.textSecond, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      '대화 기록',
                      style: TextStyle(
                        color: AppTheme.textSecond,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${provider.sessions.length}개',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // 새 대화 버튼
              Padding(
                padding: const EdgeInsets.all(10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('새 대화 시작'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentCyan,
                      side: const BorderSide(
                          color: AppTheme.accentCyan, width: 0.8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: provider.newSession,
                  ),
                ),
              ),

              // 세션 목록
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: provider.sessions.length,
                  itemBuilder: (context, index) {
                    final session = provider.sessions[index];
                    final isSelected =
                        session.id == provider.currentSession?.id;
                    return _SessionItem(
                      session: session,
                      isSelected: isSelected,
                      onTap: () => provider.selectSession(session),
                      onDelete: () => provider.deleteSession(session.id),
                    );
                  },
                ),
              ),

              // 하단 정보
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.borderColor),
                  ),
                ),
                child: Column(
                  children: [
                    _InfoRow(
                      icon: Icons.storage,
                      label: 'Milvus',
                      color: AppTheme.accentBlue,
                    ),
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: Icons.psychology_outlined,
                      label: 'EXAONE LLM',
                      color: AppTheme.accentAmber,
                    ),
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: Icons.security,
                      label: 'PII 마스킹',
                      color: AppTheme.accentGreen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SessionItem extends StatefulWidget {
  final dynamic session;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionItem({
    required this.session,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_SessionItem> createState() => _SessionItemState();
}

class _SessionItemState extends State<_SessionItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? AppTheme.accentCyan.withOpacity(0.1)
                : _hovered
                    ? AppTheme.bgCardHover
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: widget.isSelected
                ? Border.all(
                    color: AppTheme.accentCyan.withOpacity(0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 14,
                color: widget.isSelected
                    ? AppTheme.accentCyan
                    : AppTheme.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isSelected
                            ? AppTheme.textPrimary
                            : AppTheme.textSecond,
                        fontSize: 12,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    Text(
                      DateFormat('MM/dd HH:mm')
                          .format(widget.session.updatedAt),
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hovered || widget.isSelected)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: AppTheme.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}
