import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/responsive.dart';
import '../../l10n/app_localizations.dart';
import '../../models/fee_group.dart';
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
    final isNarrow = Responsive.isNarrow(context);

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
        body: TabBarView(
          children: [
            isNarrow ? const _UsageViewMobile() : const _UsageViewDesktop(),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: const FeeGroupManager(mode: FeeGroupManagerMode.section),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageViewMobile extends StatefulWidget {
  const _UsageViewMobile();

  @override
  State<_UsageViewMobile> createState() => _UsageViewMobileState();
}

class _UsageViewMobileState extends State<_UsageViewMobile> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _usageData = [];
  bool _isLoading = true;
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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _db.getTokenUsage(
        start: _dateRange.start,
        end: _dateRange.end,
      );
      if (mounted) {
        setState(() {
          _usageData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateRange(String preset) {
    final now = DateTime.now();
    DateTime start;
    switch (preset) {
      case 'today': start = DateTime(now.year, now.month, now.day); break;
      case 'week': start = now.subtract(const Duration(days: 7)); break;
      case 'month': start = DateTime(now.year, now.month - 1, now.day); break;
      case 'year': start = DateTime(now.year - 1, now.month, now.day); break;
      default: start = now.subtract(const Duration(days: 7));
    }
    setState(() { _dateRange = DateTimeRange(start: start, end: now); });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final stats = _calculateStats(_usageData, appState);

    return Column(
      children: [
        // Filter Bar
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
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
              IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _loadData),
            ],
          ),
        ),

        // Summary Cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Row(
                children: [
                  _buildStatCard(l10n.inputTokens, stats.totalInput.toString(), Colors.blue),
                  const SizedBox(width: 8),
                  _buildStatCard(l10n.outputTokens, stats.totalOutput.toString(), Colors.green),
                ],
              ),
              const SizedBox(height: 8),
              // Use expanded: false here because it's in a Column, not a Row
              _buildStatCard(l10n.estimatedCost, '\$${stats.totalCost.toStringAsFixed(4)}', Colors.orange, isBold: true, expanded: false),
            ],
          ),
        ),

        const Divider(height: 24),

        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _UsageList(usageData: _usageData, onRefresh: _loadData),
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

  Widget _buildStatCard(String label, String value, Color color, {bool isBold = false, bool expanded = true}) {
    final card = Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
          ],
        ),
      ),
    );

    if (expanded) {
      return Expanded(child: card);
    }
    return SizedBox(width: double.infinity, child: card);
  }
}

class _UsageViewDesktop extends StatefulWidget {
  const _UsageViewDesktop();

  @override
  State<_UsageViewDesktop> createState() => _UsageViewDesktopState();
}

class _UsageViewDesktopState extends State<_UsageViewDesktop> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _usageData = [];
  bool _isLoading = true;
  String _activePreset = 'week';
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
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _db.getTokenUsage(
        start: _dateRange.start,
        end: _dateRange.end,
      );
      if (mounted) {
        setState(() {
          _usageData = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateRange(String preset) {
    final now = DateTime.now();
    DateTime start;
    switch (preset) {
      case 'today': start = DateTime(now.year, now.month, now.day); break;
      case 'week': start = now.subtract(const Duration(days: 7)); break;
      case 'month': start = DateTime(now.year, now.month - 1, now.day); break;
      case 'year': start = DateTime(now.year - 1, now.month, now.day); break;
      default: start = now.subtract(const Duration(days: 7));
    }
    setState(() { 
      _dateRange = DateTimeRange(start: start, end: now); 
      _activePreset = preset;
    });
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final appState = Provider.of<AppState>(context);
    final stats = _calculateStats(_usageData, appState);

    return Row(
      children: [
        // Sidebar
        Container(
          width: 250,
          color: colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(l10n.rangeLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
              ),
              _buildPresetTile('today', l10n.today, Icons.today_outlined),
              _buildPresetTile('week', l10n.lastWeek, Icons.date_range_outlined),
              _buildPresetTile('month', l10n.lastMonth, Icons.calendar_month_outlined),
              _buildPresetTile('year', l10n.thisYear, Icons.calendar_today_outlined),
              const Spacer(),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _loadData,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(l10n.refresh),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _confirmClearAll,
                      style: ElevatedButton.styleFrom(backgroundColor: colorScheme.errorContainer, foregroundColor: colorScheme.error),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                      label: Text(l10n.clearAll),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Large Summary
                          Row(
                            children: [
                              _buildBigStat(l10n.inputTokens, stats.totalInput.toString(), Colors.blue),
                              const SizedBox(width: 24),
                              _buildBigStat(l10n.outputTokens, stats.totalOutput.toString(), Colors.green),
                              const SizedBox(width: 24),
                              _buildBigStat(l10n.estimatedCost, '\$${stats.totalCost.toStringAsFixed(4)}', Colors.orange, isBold: true),
                            ],
                          ),
                          const SizedBox(height: 32),
                          
                          if (stats.groupCosts.isNotEmpty) ...[
                            Text(l10n.usageByGroup, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: stats.groupCosts.entries.map((e) {
                                final group = appState.allFeeGroups.cast<FeeGroup?>().firstWhere(
                                  (g) => g?.id == e.key, 
                                  orElse: () => null
                                );
                                if (group == null) return const SizedBox.shrink();
                                return _buildGroupCard(group.name, e.value, colorScheme);
                              }).toList(),
                            ),
                            const SizedBox(height: 32),
                          ],

                          const Divider(),
                          const SizedBox(height: 16),
                          _UsageList(usageData: _usageData, shrinkWrap: true, onRefresh: _loadData),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildPresetTile(String id, String label, IconData icon) {
    final isSelected = _activePreset == id;
    return ListTile(
      selected: isSelected,
      leading: Icon(icon, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      onTap: () => _updateRange(id),
    );
  }

  Widget _buildBigStat(String label, String value, Color color, {bool isBold = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withAlpha(15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.withAlpha(200))),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 28, fontWeight: isBold ? FontWeight.bold : FontWeight.w300, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(String name, double cost, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withAlpha(100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 12),
          Text('\$${cost.toStringAsFixed(4)}', style: const TextStyle(fontFamily: 'monospace')),
        ],
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
}

class _UsageList extends StatelessWidget {
  final List<Map<String, dynamic>> usageData;
  final bool shrinkWrap;
  final VoidCallback onRefresh;

  const _UsageList({required this.usageData, this.shrinkWrap = false, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (usageData.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Text('No usage data found for selected range.'),
      ));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      itemCount: usageData.length,
      itemBuilder: (context, index) {
        final row = usageData[index];
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
                Text(DateFormat('MM-dd HH:mm').format(time), style: const TextStyle(fontSize: 10, color: Colors.grey)),
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
                    Text('${row['request_count']} items', style: const TextStyle(fontSize: 11)),
                  ],
                  const Spacer(),
                  _buildCostBadge(row),
                ],
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              onPressed: () => _confirmDeleteModelData(context, row['model_id']),
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
      child: Text('\$${cost.toStringAsFixed(5)}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }

  void _confirmDeleteModelData(BuildContext context, String modelId) {
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
              await DatabaseService().clearTokenUsage(modelId: modelId);
              if (context.mounted) {
                Navigator.pop(context);
                onRefresh();
              }
            },
            child: Text(l10n.clearModelData),
          ),
        ],
      ),
    );
  }
}

class _UsageStats {
  final int totalInput;
  final int totalOutput;
  final double totalCost;
  final Map<int, double> groupCosts;

  _UsageStats({required this.totalInput, required this.totalOutput, required this.totalCost, required this.groupCosts});
}

_UsageStats _calculateStats(List<Map<String, dynamic>> usageData, AppState appState) {
  final Map<int, double> groupCosts = {};
  int totalInput = 0;
  int totalOutput = 0;
  double totalCost = 0.0;

  for (var row in usageData) {
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
  return _UsageStats(totalInput: totalInput, totalOutput: totalOutput, totalCost: totalCost, groupCosts: groupCosts);
}