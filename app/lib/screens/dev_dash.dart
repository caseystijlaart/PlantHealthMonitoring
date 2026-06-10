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

  final List<String> _visibleColumns = List.of(_allColumns);

  final Map<String, Set<String>> _columnFilters = {};

  List<Map<String, dynamic>> _tableRows = [];
  bool _tableLoading = false;

  List<Map<String, dynamic>> _modelReadings = [];
  bool _modelStatsLoading = false;

  /// Filters for the model performance table (device_name / model_version).
  final Map<String, Set<String>> _modelFilters = {};

  bool _showModelSection = false;
  bool _showDevicesSection = false;
  bool _showLogsSection = false;

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
          .select(
            'device_id,device_name,status,model_version,last_seen,'
            'trigger_reset,trigger_measurement',
          )
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

  /// Fetches the model-performance telemetry rows. The firmware writes these
  /// to the dedicated model_metrics table (one row per monitoring cycle).
  /// Aggregation happens in [_modelStats] so the header filters can re-group
  /// without refetching.
  Future<void> _fetchModelStats() async {
    setState(() => _modelStatsLoading = true);

    try {
      final res = await supabase
          .from('model_metrics')
          .select(
            'created_at,plant_label,device_name,model_version,'
            'confidence,risk_class,predicted_water_min',
          )
          .order('created_at', ascending: false)
          .limit(2000);

      final now = DateTime.now();
      final rows = <Map<String, dynamic>>[];
      for (final row in List<Map<String, dynamic>>.from(res)) {
        if (!_inTimeRange(DateTime.parse(row['created_at']), now)) continue;
        rows.add({
          ...row,
          'model_version': row['model_version']?.toString() ?? '-',
          'device_name': row['device_name']?.toString() ?? '-',
        });
      }

      if (!mounted) return;
      setState(() {
        _modelReadings = rows;
        _modelStatsLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _modelStatsLoading = false);
    }
  }

  /// Model-metrics rows with the header filters applied.
  List<Map<String, dynamic>> get _filteredModelReadings {
    return _modelReadings.where((row) {
      for (final e in _modelFilters.entries) {
        if (e.value.isNotEmpty &&
            !e.value.contains(row[e.key]?.toString() ?? '-')) {
          return false;
        }
      }
      return true;
    }).toList();
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
    if (_modelReadings.isEmpty) {
      return Text(
        "No readings with model version v0.2 or above",
        style: TextStyle(color: AppColors.textMid),
      );
    }

    List<String> distinct(String key) =>
        _modelReadings.map((r) => r[key]?.toString() ?? "-").toSet().toList()
          ..sort();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 20,
        columns: [
          DataColumn(
            label: _filterableHeader(
              "MODEL",
              distinct('model_version'),
              _modelFilters.putIfAbsent('model_version', () => <String>{}),
            ),
          ),
          DataColumn(
            label: _filterableHeader(
              "DEVICE",
              distinct('device_name'),
              _modelFilters.putIfAbsent('device_name', () => <String>{}),
            ),
          ),
          const DataColumn(label: Text("TIME")),
          const DataColumn(label: Text("PLANT")),
          const DataColumn(label: Text("RISK"), numeric: true),
          const DataColumn(label: Text("CONF"), numeric: true),
          const DataColumn(label: Text("PRED (D)"), numeric: true),
        ],
        rows: _filteredModelReadings.map((r) {
          final conf = (r['confidence'] as num?)?.toDouble();
          final pred = (r['predicted_water_min'] as num?)?.toDouble();
          return DataRow(
            cells: [
              DataCell(Text(r['model_version'].toString())),
              DataCell(Text(r['device_name'].toString())),
              DataCell(Text(_fmtTimestamp(r['created_at'].toString()))),
              DataCell(Text(r['plant_label']?.toString() ?? "-")),
              DataCell(Text(r['risk_class']?.toString() ?? "-")),
              DataCell(Text(conf == null ? "-" : conf.toStringAsFixed(3))),
              DataCell(
                Text(pred == null ? "-" : (pred / 1440.0).toStringAsFixed(1)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDevicesTable() {
    if (_devicesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_deviceRows.isEmpty) {
      return Text(
        "No devices registered",
        style: TextStyle(color: AppColors.textMid),
      );
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

          return DataRow(
            cells: [
              DataCell(Text(d['device_name']?.toString() ?? "-")),
              DataCell(
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
                    status.toUpperCase(),
                    style: TextStyle(color: color),
                  ),
                ),
              ),
              DataCell(Text(d['model_version']?.toString() ?? "-")),
              DataCell(
                Text(
                  d['last_seen'] == null
                      ? "-"
                      : _fmtTimestamp(d['last_seen'].toString()),
                ),
              ),
              DataCell(Text(triggers.isEmpty ? "-" : triggers)),
              DataCell(Text(d['device_id']?.toString() ?? "-")),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// Header cell — filterable columns open a multi-select dropdown anchored
  /// to the header. An empty selection means "show all" (see _filteredRows).
  Widget _columnLabel(String col) {
    if (!_filterableColumns.contains(col)) {
      return Text(col.toUpperCase());
    }

    final values =
        _tableRows.map((r) => r[col]?.toString() ?? "-").toSet().toList()
          ..sort();
    return _filterableHeader(
      col.toUpperCase(),
      values,
      _columnFilters.putIfAbsent(col, () => <String>{}),
      upperValues: col == "status",
    );
  }

  /// Multi-select dropdown header, shared by the logs and model tables.
  Widget _filterableHeader(
    String label,
    List<String> values,
    Set<String> selected, {
    bool upperValues = false,
  }) {
    final active = selected.isNotEmpty;

    return MenuAnchor(
      menuChildren: [
        ...values.map((v) {
          return CheckboxMenuButton(
            value: selected.contains(v),
            closeOnActivate: false,
            onChanged: (on) {
              setState(() {
                on == true ? selected.add(v) : selected.remove(v);
              });
            },
            child: Text(upperValues ? v.toUpperCase() : v),
          );
        }),
        if (active) ...[
          const Divider(height: 1),
          MenuItemButton(
            leadingIcon: const Icon(Icons.clear, size: 16),
            onPressed: () => setState(selected.clear),
            child: const Text("Clear filter"),
          ),
        ],
      ],
      builder: (context, controller, _) {
        return InkWell(
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              const SizedBox(width: 4),
              Icon(
                active ? Icons.filter_alt : Icons.arrow_drop_down,
                size: 16,
                color: active ? Colors.greenAccent : AppColors.textMid,
              ),
            ],
          ),
        );
      },
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

        final tableWidth =
            minColWidth + // timestamp column
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
                  (c) => DataColumn(label: _columnLabel(c)),
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
            children: [if (_showModelSection) _buildModelStats()],
          ),

          // ---------------- DEVICES SECTION ----------------
          ExpansionTile(
            title: const Text("Devices"),
            initiallyExpanded: _showDevicesSection,
            onExpansionChanged: (v) => setState(() => _showDevicesSection = v),
            childrenPadding: const EdgeInsets.only(bottom: 16),
            children: [if (_showDevicesSection) _buildDevicesTable()],
          ),

          // ---------------- LOGS SECTION ----------------
          ExpansionTile(
            title: const Text("Logs"),
            initiallyExpanded: _showLogsSection,
            onExpansionChanged: (v) => setState(() => _showLogsSection = v),
            childrenPadding: const EdgeInsets.only(bottom: 16),
            children: [
              if (_showLogsSection) ...[
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
