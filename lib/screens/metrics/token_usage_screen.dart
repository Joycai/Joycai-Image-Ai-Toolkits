import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../services/database_service.dart';

class TokenUsageScreen extends StatefulWidget {
  const TokenUsageScreen({super.key});

  @override
  State<TokenUsageScreen> createState() => _TokenUsageScreenState();
}

class _TokenUsageScreenState extends State<TokenUsageScreen> {
  final DatabaseService _db = DatabaseService();
  
  List<Map<String, dynamic>> _usageData = [];
  List<String> _availableModels = [];
  List<String> _selectedModels = [];
  
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    final models = await _db.getModels();
    setState(() {
      _availableModels = models.map((m) => m['model_id'] as String).toList();
    });
    _refreshData();
  }

  Future<void> _refreshData() async {
    final data = await _db.getTokenUsage(
      modelIds: _selectedModels.isEmpty ? null : _selectedModels,
      start: _dateRange.start,
      end: _dateRange.end.add(const Duration(days: 1)),
    );
    setState(() {
      _usageData = data;
    });
  }

  void _setQuickFilter(String type) {
    final now = DateTime.now();
    DateTime start;
    switch (type) {
      case 'today':
        start = DateTime(now.year, now.month, now.day);
        break;
      case 'week':
        start = now.subtract(const Duration(days: 7));
        break;
      case 'month':
        start = DateTime(now.year, now.month - 1, now.day);
        break;
      case 'year':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = now.subtract(const Duration(days: 7));
    }
    setState(() {
      _dateRange = DateTimeRange(start: start, end: now);
    });
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    int totalInput = 0;
    int totalOutput = 0;
    double totalCost = 0.0;

    for (var row in _usageData) {
      final inTokens = row['input_tokens'] as int;
      final outTokens = row['output_tokens'] as int;
      final inPrice = row['input_price'] as double;
      final outPrice = row['output_price'] as double;

      totalInput += inTokens;
      totalOutput += outTokens;
      totalCost += (inTokens / 1000000 * inPrice) + (outTokens / 1000000 * outPrice);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tokenUsageMetrics),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.clearAllUsage,
            onPressed: () => _confirmClearAll(l10n),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshData),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(colorScheme, l10n),
          _buildSummaryCards(totalInput, totalOutput, totalCost, colorScheme, l10n),
          Expanded(
            child: _usageData.isEmpty
                ? const Center(child: Text('No usage data found for selected range.'))
                : _buildUsageList(colorScheme, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme colorScheme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: colorScheme.surfaceVariant.withOpacity(0.3),
      child: Column(
        children: [
          Row(
            children: [
              Text(l10n.modelsLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: _availableModels.map((m) {
                    final isSelected = _selectedModels.contains(m);
                    return FilterChip(
                      label: Text(m, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          if (val) _selectedModels.add(m);
                          else _selectedModels.remove(m);
                        });
                        _refreshData();
                      },
                      onDeleted: () => _confirmClearModel(l10n, m),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(l10n.rangeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.date_range, size: 16),
                label: Text('${DateFormat('yyyy-MM-dd').format(_dateRange.start)} - ${DateFormat('yyyy-MM-dd').format(_dateRange.end)}'),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    initialDateRange: _dateRange,
                    firstDate: DateTime(2023),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _dateRange = picked);
                    _refreshData();
                  }
                },
              ),
              const SizedBox(width: 16),
              Wrap(
                spacing: 8,
                children: [
                  _quickFilterBtn(l10n.today, 'today'),
                  _quickFilterBtn(l10n.lastWeek, 'week'),
                  _quickFilterBtn(l10n.lastMonth, 'month'),
                  _quickFilterBtn(l10n.thisYear, 'year'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickFilterBtn(String label, String type) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => _setQuickFilter(type),
    );
  }

  Widget _buildSummaryCards(int input, int output, double cost, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          _summaryCard(l10n.inputTokens, input.toString(), Icons.login, Colors.blue),
          const SizedBox(width: 16),
          _summaryCard(l10n.outputTokens, output.toString(), Icons.logout, Colors.green),
          const SizedBox(width: 16),
          _summaryCard(l10n.estimatedCost, '\$${cost.toStringAsFixed(4)}', Icons.attach_money, Colors.orange),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsageList(ColorScheme colorScheme, AppLocalizations l10n) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _usageData.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final row = _usageData[index];
        final date = DateTime.parse(row['timestamp']);
        final cost = (row['input_tokens'] / 1000000 * row['input_price']) + 
                     (row['output_tokens'] / 1000000 * row['output_price']);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: const Icon(Icons.analytics_outlined, size: 20),
          ),
          title: Row(
            children: [
              Text(row['model_id'], style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('\$${cost.toStringAsFixed(6)}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(DateFormat('yyyy-MM-dd HH:mm:ss').format(date), style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 4),
              Row(
                children: [
                  _tokenBadge('IN: ${row['input_tokens']}', Colors.blue),
                  const SizedBox(width: 8),
                  _tokenBadge('OUT: ${row['output_tokens']}', Colors.green),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tokenBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  void _confirmClearAll(AppLocalizations l10n) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearAllUsage),
        content: Text(l10n.clearUsageWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.clearTokenUsage();
              Navigator.pop(context);
              _refreshData();
            },
            child: Text(l10n.clearAll, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmClearModel(AppLocalizations l10n, String modelId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearDataForModel(modelId)),
        content: Text(l10n.clearModelDataWarning(modelId)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.clearTokenUsage(modelId: modelId);
              Navigator.pop(context);
              _refreshData();
            },
            child: Text(l10n.clearModelData, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
