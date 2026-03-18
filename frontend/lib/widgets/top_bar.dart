import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_provider.dart';
import '../theme/app_theme.dart';

class TopBarWidget extends StatelessWidget {
  final VoidCallback onToggleSidebar;
  final bool sidebarOpen;

  const TopBarWidget({
    super.key,
    required this.onToggleSidebar,
    required this.sidebarOpen,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 500; // ← 좁은 화면 감지

    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        return Container(
          height: 56,
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            border: Border(
              bottom: BorderSide(color: AppTheme.borderColor),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // 사이드바 토글
              IconButton(
                icon: Icon(
                  sidebarOpen ? Icons.menu_open : Icons.menu,
                  color: AppTheme.textSecond,
                  size: 20,
                ),
                onPressed: onToggleSidebar,
                tooltip: '사이드바',
              ),

              const SizedBox(width: 8),

              // 로고 — 좁으면 텍스트 숨김
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.accentCyan, AppTheme.accentBlue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  if (!isNarrow) ...[
                    const SizedBox(width: 8),
                    const Text(
                      'AI RAG System',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ],
              ),

              const Spacer(),

              // RAG / Agent 모드 토글
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderColor),
                ),
                padding: const EdgeInsets.all(3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ModeButton(
                      label: 'RAG',
                      icon: Icons.search,
                      selected: provider.mode == QueryMode.rag,
                      color: AppTheme.accentCyan,
                      onTap: () => provider.setMode(QueryMode.rag),
                    ),
                    const SizedBox(width: 2),
                    _ModeButton(
                      label: 'Agent',
                      icon: Icons.psychology,
                      selected: provider.mode == QueryMode.agent,
                      color: AppTheme.accentAmber,
                      onTap: () => provider.setMode(QueryMode.agent),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // 서버 상태 — 좁으면 점만 표시
              GestureDetector(
                onTap: provider.checkHealth,
                child: Tooltip(
                  message: provider.serverOnline
                      ? '서버 정상 (클릭하여 새로고침)'
                      : '서버 오프라인',
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: provider.serverOnline
                              ? AppTheme.accentGreen
                              : Colors.red,
                        ),
                      ),
                      if (!isNarrow) ...[
                        const SizedBox(width: 6),
                        Text(
                          provider.serverOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: provider.serverOnline
                                ? AppTheme.accentGreen
                                : Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // 새 대화 — 좁으면 아이콘만
              isNarrow
                  ? IconButton(
                      icon: const Icon(Icons.add, size: 18,
                          color: AppTheme.accentCyan),
                      onPressed: provider.newSession,
                      tooltip: '새 대화',
                    )
                  : TextButton.icon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('새 대화'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.accentCyan,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onPressed: provider.newSession,
                    ),
            ],
          ),
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: selected
              ? Border.all(color: color.withOpacity(0.4))
              : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 14,
                color: selected ? color : AppTheme.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : AppTheme.textMuted,
                fontSize: 12,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}