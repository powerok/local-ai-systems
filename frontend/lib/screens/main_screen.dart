import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/sidebar.dart';
import '../widgets/chat_area.dart';
import '../widgets/top_bar.dart';
import 'documents_screen.dart';
import 'status_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _sidebarOpen = true;
  int _selectedTab = 0;

  final _navItems = [
    _NavItem(Icons.chat_bubble_outline, Icons.chat_bubble, '채팅'),
    _NavItem(Icons.folder_outlined, Icons.folder, '문서'),
    _NavItem(Icons.monitor_heart_outlined, Icons.monitor_heart, '상태'),
  ];

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Row(
        children: [
          // 좌측 네비 레일
          _NavRail(
            items: _navItems,
            selectedIndex: _selectedTab,
            onTap: (i) => setState(() => _selectedTab = i),
          ),

          // 채팅 탭에서만 사이드바
          if (_selectedTab == 0 && isWide)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: _sidebarOpen ? 260 : 0,
              child: _sidebarOpen
                  ? const SidebarWidget()
                  : const SizedBox.shrink(),
            ),

          // 메인 콘텐츠
          Expanded(
            child: Column(
              children: [
                _selectedTab == 0
                    ? TopBarWidget(
                        onToggleSidebar: () =>
                            setState(() => _sidebarOpen = !_sidebarOpen),
                        sidebarOpen: _sidebarOpen,
                      )
                    : _SimpleTopBar(title: _navItems[_selectedTab].label),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: const [
                      ChatArea(),
                      DocumentsScreen(),
                      StatusScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  _NavItem(this.icon, this.activeIcon, this.label);
}

class _NavRail extends StatelessWidget {
  final List<_NavItem> items;
  final int selectedIndex;
  final Function(int) onTap;
  const _NavRail(
      {required this.items,
      required this.selectedIndex,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(right: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 36,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.accentCyan, AppTheme.accentBlue],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome,
                color: Colors.white, size: 18),
          ),
          ...items.asMap().entries.map((e) => _NavRailItem(
                icon: selectedIndex == e.key ? e.value.activeIcon : e.value.icon,
                label: e.value.label,
                selected: selectedIndex == e.key,
                onTap: () => onTap(e.key),
              )),
          const Spacer(),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('v2.1',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
          ),
        ],
      ),
    );
  }
}

class _NavRailItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _NavRailItem(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  State<_NavRailItem> createState() => _NavRailItemState();
}

class _NavRailItemState extends State<_NavRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: widget.selected
                  ? AppTheme.accentCyan.withOpacity(0.15)
                  : _hovered
                      ? AppTheme.bgCardHover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: widget.selected
                  ? Border.all(
                      color: AppTheme.accentCyan.withOpacity(0.4))
                  : null,
            ),
            child: Icon(widget.icon,
                size: 20,
                color: widget.selected
                    ? AppTheme.accentCyan
                    : _hovered
                        ? AppTheme.textSecond
                        : AppTheme.textMuted),
          ),
        ),
      ),
    );
  }
}

class _SimpleTopBar extends StatelessWidget {
  final String title;
  const _SimpleTopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        border:
            Border(bottom: BorderSide(color: AppTheme.borderColor)),
      ),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          Consumer<ChatProvider>(
            builder: (_, p, __) => Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.serverOnline
                      ? AppTheme.accentGreen
                      : Colors.redAccent,
                ),
              ),
              const SizedBox(width: 6),
              Text(p.serverOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                      color: p.serverOnline
                          ? AppTheme.accentGreen
                          : Colors.redAccent,
                      fontSize: 12)),
            ]),
          ),
        ],
      ),
    );
  }
}
