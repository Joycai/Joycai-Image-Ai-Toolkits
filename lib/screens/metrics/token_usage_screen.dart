import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/llm_model.dart';
import '../../services/database_service.dart';
import '../../state/app_state.dart';
import '../../widgets/fee_group_manager.dart';

class TokenUsageScreen extends StatefulWidget {
  const TokenUsageScreen({super.key});

  @override
  State<TokenUsageScreen> createState() => _TokenUsageScreenState();
}

class _TokenUsageScreenState extends State<TokenUsageScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tokenUsageMetrics),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.usage),
              Tab(text: l10n.feeGroups),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: TabBarView(
              children: [
                const _UsageView(),
                const FeeGroupManager(mode: FeeGroupManagerMode.section),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UsageView extends StatefulWidget {
  const _UsageView();

  @override
  State<_UsageView> createState() => _UsageViewState();
}

class _UsageViewState extends State<_UsageView> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _usageData = [];
  bool _isLoading = true;

  final Set<String> _selectedModelIds = {};
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _db.getTokenUsage(
      modelIds: _selectedModelIds.toList(),
      start: _dateRange.start,
      end: _dateRange.end,
    );
    if (mounted) {
      setState(() {
        _usageData = data;
        _isLoading = false;
      });
    }
  }

  void _updateRange(String preset) {
    final now = DateTime.now();
    DateTime start;
    switch (preset) {
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
        start = DateTime(now.year - 1, now.month, now.day);
        break;
      default:
        start = now.subtract(const Duration(days: 7));
    }
    setState(() {
      _dateRange = DateTimeRange(start: start, end: now);
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context);
    final isMobile = Responsive.isMobile(context);

    // Calculate aggregated stats
    final Map<int, double> groupCosts = {};
    int totalInput = 0;
    int totalOutput = 0;
    double totalCost = 0.0;

    for (var row in _usageData) {
      final input = row['input_tokens'] as int? ?? 0;
      final output = row['output_tokens'] as int? ?? 0;
      final billingMode = row['billing_mode'] as String? ?? 'token';
      final reqCount = row['request_count'] as int? ?? 1;
      
      double cost = 0.0;
      if (billingMode == 'token') {
        final inPrice = (row['input_price'] ?? 0.0) as num;
        final outPrice = (row['output_price'] ?? 0.0) as num;
        cost = (input * inPrice.toDouble() / 1000000) +
               (output * outPrice.toDouble() / 1000000);
      } else {
        final reqPrice = (row['request_price'] ?? 0.0) as num;
        cost = reqCount * reqPrice.toDouble();
      }

      totalInput += input;
      totalOutput += output;
      totalCost += cost;

      final modelPk = row['model_pk'] as int?;
      int? groupId;
      if (modelPk != null) {
        final model = appState.allModels.cast<LLMModel?>().firstWhere((m) => m?.id == modelPk, orElse: () => null);
        if (model != null) groupId = model.feeGroupId;
      }

      if (groupId != null) {
        groupCosts[groupId] = (groupCosts[groupId] ?? 0) + cost;
      }
    }

    return Column(
      children: [
        // Filter Bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              if (!isMobile) Text(l10n.rangeLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (!isMobile) const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPresetChip('today', l10n.today),
                      const SizedBox(width: 4),
                      _buildPresetChip('week', l10n.lastWeek),
                      const SizedBox(width: 4),
                      _buildPresetChip('month', l10n.lastMonth),
                      const SizedBox(width: 4),
                      _buildPresetChip('year', l10n.thisYear),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: _confirmClearAll,
                tooltip: l10n.clearAllUsage,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadData,
              ),
            ],
          ),
        ),

        // Summary Cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: isMobile
            ? Column(
                children: [
                  Row(
                    children: [
                      _buildStatCard(l10n.inputTokens, totalInput.toString(), Colors.blue),
                      const SizedBox(width: 8),
                      _buildStatCard(l10n.outputTokens, totalOutput.toString(), Colors.green),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildStatCard(l10n.estimatedCost, '\$${totalCost.toStringAsFixed(4)}', Colors.orange, isBold: true),
                ],
              )
            : Row(
                children: [
                  _buildStatCard(l10n.inputTokens, totalInput.toString(), Colors.blue),
                  const SizedBox(width: 16),
                  _buildStatCard(l10n.outputTokens, totalOutput.toString(), Colors.green),
                  const SizedBox(width: 16),
                  _buildStatCard(l10n.estimatedCost, '\$${totalCost.toStringAsFixed(4)}', Colors.orange, isBold: true),
                ],
              ),
        ),

        const SizedBox(height: 16),
        if (groupCosts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(l10n.usageByGroup, style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.secondary)),
            ),
          ),
        
        if (groupCosts.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: groupCosts.entries.map((e) {
                final group = appState.allFeeGroups.firstWhere((g) => g.id == e.key);
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Text(group.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Text('\$${e.value.toStringAsFixed(4)}', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

        const Divider(height: 32),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _usageData.isEmpty
                  ? const Center(child: Text('No usage data found for selected range.'))
                  : _buildUsageList(colorScheme, l10n),
        ),
      ],
    );
  }

  Widget _buildPresetChip(String id, String label) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      onPressed: () => _updateRange(id),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildStatCard(String label, String value, Color color, {bool isBold = false}) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsageList(ColorScheme colorScheme, AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _usageData.length,
      itemBuilder: (context, index) {
        final row = _usageData[index];
        final time = DateTime.parse(row['timestamp']);
        final billingMode = row['billing_mode'] as String? ?? 'token';
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            dense: true,
            title: Row(
              children: [
                Expanded(child: Text(row['model_id'], style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Text(
                  DateFormat('MM-dd HH:mm').format(time),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  if (billingMode == 'token') ...[
                    const Icon(Icons.input, size: 10, color: Colors.blue),
                    const SizedBox(width: 2),
                    Text('${row['input_tokens']}', style: const TextStyle(fontSize: 11)),
                    const SizedBox(width: 8),
                    const Icon(Icons.output, size: 10, color: Colors.green),
                    const SizedBox(width: 2),
                    Text('${row['output_tokens']}', style: const TextStyle(fontSize: 11)),
                  ] else ...[
                    const Icon(Icons.repeat, size: 10, color: Colors.purple),
                    const SizedBox(width: 2),
                    Text('${row['request_count']} ${l10n.requests}', style: const TextStyle(fontSize: 11)),
                  ],
                  const Spacer(),
                  _buildCostBadge(row),
                ],
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: () => _confirmDeleteModelData(row['model_id']),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCostBadge(Map<String, dynamic> row) {
    final billingMode = row['billing_mode'] as String? ?? 'token';
    double cost = 0.0;
    if (billingMode == 'token') {
      final inPrice = (row['input_price'] ?? 0.0) as num;
      final outPrice = (row['output_price'] ?? 0.0) as num;
      cost = ((row['input_tokens'] ?? 0) * inPrice.toDouble() / 1000000) +
             ((row['output_tokens'] ?? 0) * outPrice.toDouble() / 1000000);
    } else {
      final reqPrice = (row['request_price'] ?? 0.0) as num;
      cost = (row['request_count'] ?? 1) * reqPrice.toDouble();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '\$${cost.toStringAsFixed(5)}',
        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }

  void _confirmClearAll() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearAllUsage),
        content: Text(l10n.clearUsageWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.clearTokenUsage();
              if (context.mounted) {
                Navigator.pop(context);
                _loadData();
              }
            },
            child: Text(l10n.clearAll),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteModelData(String modelId) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearDataForModel(modelId)),
        content: Text(l10n.clearModelDataWarning(modelId)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.clearTokenUsage(modelId: modelId);
              if (context.mounted) {
                Navigator.pop(context);
                _loadData();
              }
            },
            child: Text(l10n.clearModelData),
          ),
        ],
      ),
    );
  }
}