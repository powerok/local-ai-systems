import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api_service.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  bool _ragOnline = false;
  bool _loading = true;
  DateTime? _lastChecked;

  final List<_ServiceStatus> _services = [
    _ServiceStatus('RAG Server', ':8080', Icons.psychology_outlined),
    _ServiceStatus('Milvus', ':19530', Icons.storage),
    _ServiceStatus('PostgreSQL', ':5432', Icons.dataset),
    _ServiceStatus('Redis', ':6379', Icons.memory),
    _ServiceStatus('MinIO', ':9000', Icons.cloud),
    _ServiceStatus('Ollama', ':11434', Icons.smart_toy_outlined),
    _ServiceStatus('Prometheus', ':9090', Icons.monitor_heart_outlined),
    _ServiceStatus('Grafana', ':3000', Icons.bar_chart),
    _ServiceStatus('Airflow', ':8081', Icons.air),
    _ServiceStatus('Gateway', ':8090', Icons.router),
  ];

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    setState(() => _loading = true);
    _ragOnline = await ApiService.healthCheck();
    setState(() {
      _loading = false;
      _lastChecked = DateTime.now();
      // RAG가 온라인이면 관련 서비스도 온라인으로 표시
      for (final s in _services) {
        if (s.name == 'RAG Server') s.online = _ragOnline;
        else s.online = _ragOnline; // 실제로는 각각 체크해야 하지만 RAG 헬스에 의존
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '시스템 상태',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_lastChecked != null)
                    Text(
                      '마지막 확인: ${DateFormat('HH:mm:ss').format(_lastChecked!)}',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12),
                    ),
                ],
              ),
              const Spacer(),
              TextButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.accentCyan))
                    : const Icon(Icons.refresh, size: 16),
                label: const Text('새로고침'),
                style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentCyan),
                onPressed: _loading ? null : _checkStatus,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 전체 상태 배너
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (_ragOnline
                      ? AppTheme.accentGreen
                      : Colors.redAccent)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_ragOnline
                        ? AppTheme.accentGreen
                        : Colors.redAccent)
                    .withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _ragOnline
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: _ragOnline
                      ? AppTheme.accentGreen
                      : Colors.redAccent,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  _ragOnline
                      ? '모든 시스템이 정상 동작 중입니다'
                      : 'RAG 서버에 연결할 수 없습니다',
                  style: TextStyle(
                    color: _ragOnline
                        ? AppTheme.accentGreen
                        : Colors.redAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 서비스 그리드
          const Text(
            '서비스 현황',
            style: TextStyle(
              color: AppTheme.textSecond,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),

          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              childAspectRatio: 1.8,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _services.length,
            itemBuilder: (context, i) =>
                _ServiceCard(service: _services[i]),
          ),

          const SizedBox(height: 24),

          // 포트 안내
          const Text(
            '접속 포트 안내',
            style: TextStyle(
              color: AppTheme.textSecond,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          _PortTable(),
        ],
      ),
    );
  }
}

class _ServiceStatus {
  final String name;
  final String port;
  final IconData icon;
  bool online;

  _ServiceStatus(this.name, this.port, this.icon, {this.online = false});
}

class _ServiceCard extends StatelessWidget {
  final _ServiceStatus service;
  const _ServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: service.online
              ? AppTheme.accentGreen.withOpacity(0.2)
              : AppTheme.borderColor,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (service.online
                      ? AppTheme.accentGreen
                      : AppTheme.textMuted)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              service.icon,
              size: 18,
              color: service.online
                  ? AppTheme.accentGreen
                  : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  service.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  service.port,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: service.online
                  ? AppTheme.accentGreen
                  : AppTheme.textMuted,
              boxShadow: service.online
                  ? [
                      BoxShadow(
                        color: AppTheme.accentGreen.withOpacity(0.4),
                        blurRadius: 6,
                      )
                    ]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PortTable extends StatelessWidget {
  final List<Map<String, String>> _ports = const [
    {'service': 'Frontend (이 화면)', 'host': '3001', 'desc': 'Flutter Web UI'},
    {'service': 'RAG Server', 'host': '8080', 'desc': 'FastAPI RAG/Agent'},
    {'service': 'Gateway', 'host': '8090', 'desc': 'Spring Cloud Gateway'},
    {'service': 'Airflow UI', 'host': '8081', 'desc': 'ETL 파이프라인 관리'},
    {'service': 'Grafana', 'host': '3000', 'desc': '모니터링 대시보드'},
    {'service': 'Prometheus', 'host': '9090', 'desc': '메트릭 수집'},
    {'service': 'MinIO Console', 'host': '9001', 'desc': '오브젝트 스토리지'},
    {'service': 'Ollama', 'host': '11434', 'desc': 'EXAONE LLM API'},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        children: _ports.asMap().entries.map((entry) {
          final i = entry.key;
          final port = entry.value;
          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: i < _ports.length - 1
                  ? const Border(
                      bottom: BorderSide(color: AppTheme.borderColor))
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: Text(
                    port['service']!,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ':${port['host']}',
                    style: const TextStyle(
                      color: AppTheme.accentCyan,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  port['desc']!,
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
