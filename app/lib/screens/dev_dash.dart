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

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() => _fetchTable();

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

  Widget _buildTable() {
    final cols = ["timestamp", ..._visibleColumns];

    return LayoutBuilder(
      builder: (context, constraints) {
        const minColWidth = 160.0;
        final tableWidth = cols.length * minColWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth < constraints.maxWidth
                ? constraints.maxWidth
                : tableWidth,
            child: DataTable(
              columnSpacing: 20,
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
                          width: 180,
                          child: Text(
                            v,
                            softWrap: true,
                            overflow: TextOverflow.visible,
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
      appBar: AppBar(title: const Text("Charts & Data")),

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

          // ---------------- COLUMN SELECTOR ----------------
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
      ),
    );
  }
}
