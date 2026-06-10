import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_colors.dart';
import '../services/supabase_service.dart';
import '../widgets/grid_painter.dart';

Color colorForMetric(String metric) => switch (metric) {
      "soil_moisture_pct" => AppColors.accent,
      "temperature_c"     => AppColors.high,
      "humidity_pct"      => const Color(0xFF60A5FA),
      "light_level_pct"   => const Color(0xFFFBBF24),
      _                   => AppColors.textMid,
    };

String metricLabel(String m) => switch (m) {
      "soil_moisture_pct" => "Soil Moisture",
      "temperature_c"     => "Temperature",
      "humidity_pct"      => "Humidity",
      "light_level_pct"   => "Light",
      _                   => m,
    };

class DataPage extends StatefulWidget {
  const DataPage({super.key, required this.plants, required this.selectedPlant});
  final List<String> plants;
  final String? selectedPlant;

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  static const _metrics = [
    "soil_moisture_pct",
    "temperature_c",
    "humidity_pct",
    "light_level_pct"
  ];
  static const _allColumns = [
    ('soil_moisture_pct', 'Soil %'),
    ('temperature_c', 'Temp °C'),
    ('humidity_pct', 'Humidity %'),
    ('light_level_pct', 'Light %'),
    ('risk_class', 'Risk'),
    ('recommendation_summary', 'Water in'),
    // Virtual column: shows the actions:[...] part of recommendation_summary.
    ('actions', 'Actions'),
  ];

  /// Maps a (possibly virtual) table column to the database column it reads.
  static String _dbColumn(String col) =>
      col == 'actions' ? 'recommendation_summary' : col;

  List<String> selectedMetrics = ["soil_moisture_pct"];
  String timeRange = "24h";
  List<DateTime> timestamps = [];
  Map<String, List<FlSpot>> graphData = {};
  bool _loading = false;

  final List<String> _tableColumns = ['soil_moisture_pct'];
  List<Map<String, dynamic>> _tableRows = [];
  bool _tableLoading = false;
  bool _tableVisible = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() => Future.wait([loadGraph(), _fetchTable()]);

  bool isInRange(DateTime t) {
    final now = DateTime.now();
    if (timeRange == "24h") return now.difference(t).inHours <= 24;
    if (timeRange == "7d") return now.difference(t).inDays <= 7;
    return true;
  }

  Future<void> loadGraph() async {
    if (widget.selectedPlant == null) return;
    setState(() => _loading = true);

    final response = await supabase
        .from('plant_readings')
        .select()
        .eq('plant_label', widget.selectedPlant!)
        .order('timestamp', ascending: true);

    final data = List<Map<String, dynamic>>.from(response);
    final Map<String, List<FlSpot>> temp = {};
    final List<DateTime> loadedTimestamps = [];
    final filtered = data
        .where((row) => isInRange(DateTime.parse(row['timestamp'])))
        .toList();

    for (int i = 0; i < filtered.length; i++) {
      final row = filtered[i];
      loadedTimestamps.add(DateTime.parse(row['timestamp']).toLocal());
      for (final m in selectedMetrics) {
        final value = (row[m] ?? 0).toDouble().clamp(0.0, 100.0);
        temp.putIfAbsent(m, () => []);
        temp[m]!.add(FlSpot(i.toDouble(), value));
      }
    }

    if (!mounted) return;
    setState(() {
      timestamps = loadedTimestamps;
      graphData = temp;
      _loading = false;
    });
  }

  Future<void> _fetchTable() async {
    if (widget.selectedPlant == null) return;
    setState(() => _tableLoading = true);

    final cols = {
      'plant_label',
      'timestamp',
      ..._tableColumns.map(_dbColumn),
    }.join(',');
    final res = await supabase
        .from('plant_readings')
        .select(cols)
        .eq('plant_label', widget.selectedPlant!)
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
  }

  String _fmtTimestamp(String ts) {
    final t = DateTime.parse(ts).toLocal();
    return "${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} "
        "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
  }

  String _fmtValue(dynamic v, String col) {
    if (v == null) return '—';
    if (col == 'risk_class') {
      return switch (v) { 0 => 'Healthy', 1 => 'Moderate', 2 => 'High', _ => '$v' };
    }
    if (col == 'actions') {
      final m = RegExp(r'actions:\[([^\]]*)\]').firstMatch(v as String? ?? '');
      final items = (m?.group(1) ?? '')
          .trim()
          .split(RegExp(r'\s+'))
          .where((s) => s.isNotEmpty);
      return items.isEmpty ? '—' : items.join(', ');
    }
    if (col == 'recommendation_summary') {
      final match = RegExp(r'predWaterMin[=:\s]+([\d.]+)').firstMatch(v as String? ?? '');
      if (match == null) return '—';
      final minutes = double.parse(match.group(1)!);
      if (minutes >= 1440) {
        final d = minutes / 1440;
        return "${d % 1 == 0 ? d.toInt() : d.toStringAsFixed(1)}d";
      }
      if (minutes >= 60) {
        final h = minutes / 60;
        return "${h % 1 == 0 ? h.toInt() : h.toStringAsFixed(1)}h";
      }
      return "${minutes.toInt()} min";
    }
    return (v as num).toStringAsFixed(1);
  }

  Color _riskColor(dynamic v) => switch (v) {
        0 => AppColors.healthy,
        1 => AppColors.moderate,
        2 => AppColors.high,
        _ => AppColors.textLow,
      };

  Widget buildMetricSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _metrics.map((m) {
        final sel = selectedMetrics.contains(m);
        return FilterChip(
          label: Text(metricLabel(m)),
          selected: sel,
          onSelected: (v) {
            setState(() {
              if (v) {
                selectedMetrics.add(m);
              } else {
                selectedMetrics.remove(m);
              }
            });
            loadGraph();
          },
        );
      }).toList(),
    );
  }

  Widget buildLegend() {
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: selectedMetrics.map((m) {
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: colorForMetric(m), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(metricLabel(m),
              style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMid)),
        ]);
      }).toList(),
    );
  }

  Widget buildChart(bool isWide) {
    if (selectedMetrics.isEmpty) {
      return Center(
          child: Text("Select at least one metric",
              style: GoogleFonts.outfit(color: AppColors.textLow)));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (graphData.isEmpty) {
      return Center(
          child: Text("No data for selected range",
              style: GoogleFonts.outfit(color: AppColors.textLow)));
    }

    return LineChart(LineChartData(
      minY: 0,
      maxY: 100,
      backgroundColor: Colors.transparent,
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.surface2,
          getTooltipItems: (spots) {
            final i = spots.first.x.toInt();
            final t = (i >= 0 && i < timestamps.length) ? timestamps[i] : null;
            final dateStr = t != null
                ? "${t.day}/${t.month}  ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}"
                : "";
            return List.generate(spots.length, (idx) {
              final spot = spots[idx];
              final mn = spot.barIndex < selectedMetrics.length
                  ? selectedMetrics[spot.barIndex]
                  : '';
              final isLast = idx == spots.length - 1;
              return LineTooltipItem(
                "${metricLabel(mn)}: ${spot.y.toStringAsFixed(1)}",
                GoogleFonts.outfit(color: colorForMetric(mn), fontSize: 11),
                children: isLast && dateStr.isNotEmpty
                    ? [
                        TextSpan(
                            text: '\n$dateStr',
                            style: GoogleFonts.outfit(
                                color: AppColors.textLow, fontSize: 10))
                      ]
                    : [],
              );
            });
          },
        ),
      ),
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.gridLine, strokeWidth: 1),
        getDrawingVerticalLine: (_) =>
            const FlLine(color: AppColors.gridLine, strokeWidth: 1),
      ),
      borderData: FlBorderData(
          show: true, border: Border.all(color: AppColors.border)),
      titlesData: FlTitlesData(
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: timestamps.isNotEmpty ? (timestamps.length / 5).ceilToDouble() : 1,
            getTitlesWidget: (value, meta) {
              final i = value.toInt();
              if (i < 0 || i >= timestamps.length) return const Text("");
              final t = timestamps[i];
              return Text("${t.day}/${t.month}",
                  style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textLow));
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            getTitlesWidget: (value, meta) => Text(value.toInt().toString(),
                style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textLow)),
          ),
        ),
      ),
      lineBarsData: selectedMetrics.map((m) {
        return LineChartBarData(
          spots: graphData[m] ?? [],
          isCurved: true,
          preventCurveOverShooting: true,
          barWidth: 2,
          color: colorForMetric(m),
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
              show: true, color: colorForMetric(m).withValues(alpha: 0.06)),
        );
      }).toList(),
    ));
  }

  Widget _buildInlineTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("DATA",
            style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textLow,
                letterSpacing: 1.8)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _allColumns.map((c) {
            final sel = _tableColumns.contains(c.$1);
            return FilterChip(
              label: Text(c.$2),
              selected: sel,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _tableColumns.add(c.$1);
                  } else {
                    _tableColumns.remove(c.$1);
                  }
                });
                _fetchTable();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_tableLoading)
          const Center(child: CircularProgressIndicator(color: AppColors.accent))
        else if (_tableRows.isEmpty)
          Center(
              child: Text("No data found",
                  style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 13)))
        else
          // Columns auto-size to their content, but the table is never
          // narrower than the screen: a minWidth makes it stretch edge to
          // edge, and when wider the horizontal scroll view takes over.
          LayoutBuilder(builder: (context, constraints) {
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: SingleChildScrollView(
                    child: DataTable(
                  headingRowColor:
                      WidgetStateProperty.all(AppColors.surface),
                  dataRowColor:
                      WidgetStateProperty.all(Colors.transparent),
                  dividerThickness: 1,
                  columnSpacing: 20,
                  headingTextStyle: GoogleFonts.outfit(
                      color: AppColors.textLow,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2),
                  dataTextStyle:
                      GoogleFonts.outfit(color: AppColors.textMid, fontSize: 13),
                  columns: [
                    const DataColumn(label: Text("TIME")),
                    ..._tableColumns.map((col) {
                      final lbl = _allColumns
                          .firstWhere((c) => c.$1 == col)
                          .$2
                          .toUpperCase();
                      return DataColumn(label: Text(lbl));
                    }),
                  ],
                  rows: _tableRows.map((row) {
                    return DataRow(cells: [
                      DataCell(Text(_fmtTimestamp(row['timestamp']),
                          style: GoogleFonts.outfit(
                              color: AppColors.textLow, fontSize: 12))),
                      ..._tableColumns.map((col) {
                        final v = row[_dbColumn(col)];
                        if (col == 'risk_class') {
                          return DataCell(Text(_fmtValue(v, col),
                              style: GoogleFonts.outfit(
                                  color: _riskColor(v),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)));
                        }
                        return DataCell(Text(_fmtValue(v, col)));
                      }),
                    ]);
                  }).toList(),
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            tooltip: "Back",
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(CupertinoIcons.back)),
        title: const Text("Charts & Data"),
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AppColors.border)),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: GridPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: isWide ? 1100.0 : double.infinity),
                child: RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      buildMetricSelector(),
                      const SizedBox(height: 12),
                      buildLegend(),
                      const SizedBox(height: 16),
                      Container(
                        height: isWide ? 420 : 320,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: buildChart(isWide),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey("datapage-range-$timeRange"),
                        initialValue: timeRange,
                        decoration:
                            const InputDecoration(labelText: "Time range"),
                        items: [
                          DropdownMenuItem(
                              value: "24h",
                              child: Text("Past 24 hours",
                                  style: GoogleFonts.outfit(
                                      color: AppColors.textMid))),
                          DropdownMenuItem(
                              value: "7d",
                              child: Text("Past 7 days",
                                  style: GoogleFonts.outfit(
                                      color: AppColors.textMid))),
                          DropdownMenuItem(
                              value: "all",
                              child: Text("All time",
                                  style: GoogleFonts.outfit(
                                      color: AppColors.textMid))),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => timeRange = v);
                          _loadAll();
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() => _tableVisible = !_tableVisible);
                          if (_tableVisible && _tableRows.isEmpty) _fetchTable();
                        },
                        icon: Icon(
                            _tableVisible
                                ? Icons.table_chart
                                : Icons.table_chart_outlined,
                            size: 16),
                        label: Text(_tableVisible
                            ? "Hide Data Table"
                            : "Show Data Table"),
                      ),
                      if (_tableVisible) ...[
                        const SizedBox(height: 16),
                        _buildInlineTable(),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
