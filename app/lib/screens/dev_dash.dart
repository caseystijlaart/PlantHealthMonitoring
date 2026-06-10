import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_colors.dart';
import '../services/supabase_service.dart';
import '../widgets/grid_painter.dart';

class DevDash extends StatefulWidget {
  const DevDash({super.key});

  @override
  State<DevDash> createState() => _DevDashState();
}

class _DevDashState extends State<DevDash> {
  static const _allColumns = ["device_id", "device_name", "status", "message"];

  static const _filterableColumns = ["device_id", "device_name", "status"];

  String timeRange = "24h";

  final List<String> _visibleColumns = ["device_name", "status", "message"];

  final Map<String, Set<String>> _columnFilters = {};

  List<Map<String, dynamic>> _tableRows = [];
  bool _tableLoading = false;

  List<Map<String, dynamic>> _modelStats = [];
  bool _modelStatsLoading = false;

  bool _showModelSection = true;
  bool _showDevicesSection = true;
  bool _showLogsSection = true;

  List<Map<String, dynamic>> _deviceRows = [];
  bool _devicesLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() =>
      Future.wait([_fetchTable(), _fetchModelStats(), _fetchDevices()]);

  Future<void> _fetchDevices() async {
    setState(() => _devicesLoading = true);

    try {
      final res = await supabase
          .from('devices')
          .select('device_id,device_name,status,model_version,last_seen,'
              'trigger_reset,trigger_measurement')
          .order('last_seen', ascending: false);

      if (!mounted) return;
      setState(() {
        _deviceRows = List<Map<String, dynamic>>.from(res);
        _devicesLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _devicesLoading = false);
    }
  }

  bool _inTimeRange(DateTime t, DateTime now) {
    if (timeRange == '24h') return now.difference(t).inHours <= 24;
    if (timeRange == '7d') return now.difference(t).inDays <= 7;
    return true;
  }

  /// Aggregates plant_readings per model_version so model generations can be
  /// compared (sample count, mean/min confidence, risk distribution).
  Future<void> _fetchModelStats() async {
    setState(() => _modelStatsLoading = true);

    try {
      final res = await supabase
          .from('plant_readings')
          .select('timestamp,model_version,confidence,risk_class')
          .order('timestamp', ascending: false)
          .limit(2000);

      final now = DateTime.now();
      final byVersion = <String, List<Map<String, dynamic>>>{};
      for (final row in List<Map<String, dynamic>>.from(res)) {
        if (!_inTimeRange(DateTime.parse(row['timestamp']), now)) continue;
        final v = row['model_version']?.toString() ?? 'pre-versioning';
        byVersion.putIfAbsent(v, () => []).add(row);
      }

      final stats = byVersion.entries.map((e) {
        final rows = e.value;
        final confs = rows
            .map((r) => (r['confidence'] as num?)?.toDouble())
            .whereType<double>()
            .toList();
        int risk(int c) =>
            rows.where((r) => (r['risk_class'] as num?)?.toInt() == c).length;
        return <String, dynamic>{
          'version': e.key,
          'readings': rows.length,
          'avg_conf': confs.isEmpty
              ? null
              : confs.reduce((a, b) => a + b) / confs.length,
          'low_conf_pct': confs.isEmpty
              ? null
              : 100.0 * confs.where((c) => c < 0.6).length / confs.length,
          'risk_0': risk(0),
          'risk_1': risk(1),
          'risk_2': risk(2),
        };
      }).toList()
        ..sort((a, b) =>
            (b['version'] as String).compareTo(a['version'] as String));

      if (!mounted) return;
      setState(() {
        _modelStats = stats;
        _modelStatsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _modelStatsLoading = false);
    }
  }

  Future<void> _fetchTable() async {
    setState(() => _tableLoading = true);

    try {
      final cols = ['timestamp', ..._allColumns].join(',');

      final res = await supabase
          .from('logs')
          .select(cols)
          .order('timestamp', ascending: false)
          .limit(200);

      final now = DateTime.now();

      final rows = List<Map<String, dynamic>>.from(res).where((row) {
        final t = DateTime.parse(row['timestamp']);

        if (timeRange == '24h') return now.difference(t).inHours <= 24;
        if (timeRange == '7d') return now.difference(t).inDays <= 7;
        return true;
      }).toList();

      if (!mounted) return;

      setState(() {
        _tableRows = rows;
        _tableLoading = false;
      });
    } catch (e) {
      setState(() => _tableLoading = false);
    }
  }

  String _fmtTimestamp(String ts) {
    final t = DateTime.parse(ts).toLocal();

    return "${t.year}-${t.month.toString().padLeft(2, '0')}-"
        "${t.day.toString().padLeft(2, '0')} "
        "${t.hour.toString().padLeft(2, '0')}:"
        "${t.minute.toString().padLeft(2, '0')}:"
        "${t.second.toString().padLeft(2, '0')}";
  }

  Color _statusColor(String v) {
    final val = v.toLowerCase();
    if (val == "ok") return Colors.greenAccent;
    if (val == "error") return const Color(0xFFF87171);
    return AppColors.textMid;
  }

  List<Map<String, dynamic>> get _filteredRows {
    return _tableRows.where((row) {
      for (final e in _columnFilters.entries) {
        if (e.value.isEmpty) continue;
        final value = row[e.key]?.toString() ?? "-";
        if (!e.value.contains(value)) return false;
      }
      return true;
    }).toList();
  }

  /// Width needed so the longest visible message fits in at most two lines.
  double _messageColWidth(TextStyle style) {
    const minWidth = 160.0;
    const maxWidth = 480.0;
    double widest = 0;
    for (final row in _filteredRows) {
      final v = row['message']?.toString() ?? "-";
      final tp = TextPainter(
        text: TextSpan(text: v, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (tp.width > widest) widest = tp.width;
    }
    // Half the single-line width (plus padding slack) lets it wrap onto two lines.
    return (widest / 2 + 24).clamp(minWidth, maxWidth);
  }

  Widget _buildModelStats() {
    if (_modelStatsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_modelStats.isEmpty) {
      return Text("No readings in range",
          style: TextStyle(color: AppColors.textMid));
    }

    String pct(dynamic v) => v == null ? "-" : (v as double).toStringAsFixed(1);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text("MODEL")),
          DataColumn(label: Text("READINGS"), numeric: true),
          DataColumn(label: Text("AVG CONF"), numeric: true),
          DataColumn(label: Text("CONF <0.6 %"), numeric: true),
          DataColumn(label: Text("RISK 0/1/2")),
        ],
        rows: _modelStats.map((s) {
          final avg = s['avg_conf'] as double?;
          return DataRow(cells: [
            DataCell(Text(s['version'].toString())),
            DataCell(Text(s['readings'].toString())),
            DataCell(Text(avg == null ? "-" : avg.toStringAsFixed(3))),
            DataCell(Text(pct(s['low_conf_pct']))),
            DataCell(Text("${s['risk_0']} / ${s['risk_1']} / ${s['risk_2']}")),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildDevicesTable() {
    if (_devicesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_deviceRows.isEmpty) {
      return Text("No devices registered",
          style: TextStyle(color: AppColors.textMid));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        columns: const [
          DataColumn(label: Text("NAME")),
          DataColumn(label: Text("STATUS")),
          DataColumn(label: Text("MODEL")),
          DataColumn(label: Text("LAST SEEN")),
          DataColumn(label: Text("TRIGGERS")),
          DataColumn(label: Text("DEVICE ID")),
        ],
        rows: _deviceRows.map((d) {
          final status = d['status']?.toString() ?? "-";
          final color = _statusColor(status);
          final triggers = [
            if (d['trigger_reset'] == true) "reset",
            if (d['trigger_measurement'] == true) "measure",
          ].join(", ");

          return DataRow(cells: [
            DataCell(Text(d['device_name']?.toString() ?? "-")),
            DataCell(
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status.toUpperCase(),
                    style: TextStyle(color: color)),
              ),
            ),
            DataCell(Text(d['model_version']?.toString() ?? "-")),
            DataCell(Text(d['last_seen'] == null
                ? "-"
                : _fmtTimestamp(d['last_seen'].toString()))),
            DataCell(Text(triggers.isEmpty ? "-" : triggers)),
            DataCell(Text(d['device_id']?.toString() ?? "-")),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildTable() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const minColWidth = 160.0;
        final textStyle =
            DataTableTheme.of(context).dataTextStyle ??
            Theme.of(context).textTheme.bodyMedium ??
            const TextStyle(fontSize: 14);
        final msgWidth = _visibleColumns.contains("message")
            ? _messageColWidth(textStyle)
            : 0.0;

        double colWidth(String col) =>
            col == "message" ? msgWidth : minColWidth;

        final tableWidth = minColWidth + // timestamp column
            _visibleColumns.fold<double>(0, (sum, c) => sum + colWidth(c)) +
            _visibleColumns.length * 20; // column spacing

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth < constraints.maxWidth
                ? constraints.maxWidth
                : tableWidth,
            child: DataTable(
              columnSpacing: 20,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 72,
              columns: [
                const DataColumn(label: Text("TIME")),
                ..._visibleColumns.map(
                  (c) => DataColumn(label: Text(c.toUpperCase())),
                ),
              ],
              rows: _filteredRows.map((row) {
                return DataRow(
                  cells: [
                    DataCell(Text(_fmtTimestamp(row['timestamp']))),

                    ..._visibleColumns.map((col) {
                      final v = row[col]?.toString() ?? "-";

                      if (col == "status") {
                        final color = _statusColor(v);

                        return DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              v.toUpperCase(),
                              style: TextStyle(color: color),
                            ),
                          ),
                        );
                      }

                      return DataCell(
                        SizedBox(
                          width: colWidth(col),
                          child: Text(
                            v,
                            softWrap: true,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Developer Page")),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------------- TIME RANGE (RESTORED) ----------------
          DropdownButtonFormField<String>(
            value: timeRange,
            decoration: const InputDecoration(labelText: "Time range"),
            items: const [
              DropdownMenuItem(value: "24h", child: Text("Past 24 hours")),
              DropdownMenuItem(value: "7d", child: Text("Past 7 days")),
              DropdownMenuItem(value: "all", child: Text("All time")),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => timeRange = v);
              _loadAll();
            },
          ),

          const SizedBox(height: 12),

          // ---------------- MODEL PERFORMANCE SECTION ----------------
          ExpansionTile(
            title: const Text("Model performance"),
            initiallyExpanded: _showModelSection,
            onExpansionChanged: (v) => setState(() => _showModelSection = v),
            childrenPadding: const EdgeInsets.only(bottom: 16),
            children: [
              if (_showModelSection) _buildModelStats(),
            ],
          ),

          // ---------------- DEVICES SECTION ----------------
          ExpansionTile(
            title: const Text("Devices"),
            initiallyExpanded: _showDevicesSection,
            onExpansionChanged: (v) => setState(() => _showDevicesSection = v),
            childrenPadding: const EdgeInsets.only(bottom: 16),
            children: [
              if (_showDevicesSection) _buildDevicesTable(),
            ],
          ),

          // ---------------- LOGS SECTION ----------------
          ExpansionTile(
            title: const Text("Logs"),
            initiallyExpanded: _showLogsSection,
            onExpansionChanged: (v) => setState(() => _showLogsSection = v),
            childrenPadding: const EdgeInsets.only(bottom: 16),
            children: [
              if (_showLogsSection) ...[
                // Column selector — applies to the logs table only.
                Wrap(
                  spacing: 8,
                  children: _allColumns.map((c) {
                    final selected = _visibleColumns.contains(c);

                    return FilterChip(
                      label: Text(c.toUpperCase()),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _visibleColumns.add(c);
                          } else {
                            _visibleColumns.remove(c);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                if (_tableLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  _buildTable(),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
