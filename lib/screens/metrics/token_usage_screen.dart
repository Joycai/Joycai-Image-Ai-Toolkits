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
              Tab(text: l10n.priceConfig),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _UsageView(),
            _FeeGroupsView(),
          ],
        ),
      ),
    );
  }
}

class _FeeGroupsView extends StatefulWidget {
  const _FeeGroupsView();

  @override
  State<_FeeGroupsView> createState() => _FeeGroupsViewState();
}

class _FeeGroupsViewState extends State<_FeeGroupsView> {
  final DatabaseService _db = DatabaseService();
  List<Map<String, dynamic>> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final groups = await _db.getFeeGroups();
    setState(() {
      _groups = List.from(groups);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.monetization_on_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(l10n.noModelsConfigured, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), // Using similar string
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showGroupDialog(l10n),
              icon: const Icon(Icons.add),
              label: Text(l10n.addFeeGroup),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGroupDialog(l10n),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _groups.length,
        itemBuilder: (context, index) {
          final group = _groups[index];
          final billingMode = group['billing_mode'] as String;
          
          return Card(
            child: ListTile(
              leading: Icon(
                billingMode == 'request' ? Icons.ads_click : Icons.token,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(group['name']),
              subtitle: Text(billingMode == 'request'
                ? '\$${group['request_price']}/Req'
                : 'In: \$${group['input_price']}/M | Out: \$${group['output_price']}/M'
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _showGroupDialog(l10n, group: group),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _confirmDelete(l10n, group),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(AppLocalizations l10n, Map<String, dynamic> group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteFeeGroupConfirm(group['name'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _db.deleteFeeGroup(group['id']);
              if (context.mounted) {
                Navigator.pop(context);
                _loadGroups();
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showGroupDialog(AppLocalizations l10n, {Map<String, dynamic>? group}) {
    final nameCtrl = TextEditingController(text: group?['name'] ?? '');
    final inputPriceCtrl = TextEditingController(text: (group?['input_price'] ?? 0.0).toString());
    final outputPriceCtrl = TextEditingController(text: (group?['output_price'] ?? 0.0).toString());
    final requestPriceCtrl = TextEditingController(text: (group?['request_price'] ?? 0.0).toString());
    String billingMode = group?['billing_mode'] ?? 'token';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(group == null ? l10n.addFeeGroup : l10n.editFeeGroup),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: l10n.groupName)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: billingMode,
                  items: [
                    DropdownMenuItem(value: 'token', child: Text(l10n.perToken)),
                    DropdownMenuItem(value: 'request', child: Text(l10n.perRequest)),
                  ],
                  onChanged: (v) => setDialogState(() => billingMode = v!),
                  decoration: InputDecoration(labelText: l10n.billingMode),
                ),
                const SizedBox(height: 16),
                if (billingMode == 'token')
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: inputPriceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: l10n.inputPrice, border: const OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: outputPriceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(labelText: l10n.outputPrice, border: const OutlineInputBorder()),
                        ),
                      ),
                    ],
                  )
                else
                  TextField(
                    controller: requestPriceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: l10n.requestPrice, border: const OutlineInputBorder()),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'name': nameCtrl.text,
                  'billing_mode': billingMode,
                  'input_price': double.tryParse(inputPriceCtrl.text) ?? 0.0,
                  'output_price': double.tryParse(outputPriceCtrl.text) ?? 0.0,
                  'request_price': double.tryParse(requestPriceCtrl.text) ?? 0.0,
                };
                if (group == null) {
                  await _db.addFeeGroup(data);
                } else {
                  await _db.updateFeeGroup(group['id'], data);
                }
                if (context.mounted) {
                  Navigator.pop(context);
                  _loadGroups();
                }
              },
              child: Text(group == null ? l10n.add : l10n.save),
            ),
          ],
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
  List<Map<String, dynamic>> _models = [];
  List<Map<String, dynamic>> _feeGroups = [];
  List<String> _availableModelIds = [];
  final List<String> _selectedModelIds = [];
  
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
    final feeGroups = await _db.getFeeGroups();
    setState(() {
      _models = models;
      _feeGroups = feeGroups;
      _availableModelIds = models.map((m) => m['model_id'] as String).toSet().toList();
    });
    _refreshData();
  }

  Future<void> _refreshData() async {
    final data = await _db.getTokenUsage(
      modelIds: _selectedModelIds.isEmpty ? null : _selectedModelIds,
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
    int totalRequests = 0;
    double totalCost = 0.0;

    // Map to store group-wise totals: groupPk -> cost
    final Map<int?, double> groupCosts = {};

    for (var row in _usageData) {
      final inTokens = row['input_tokens'] as int;
      final outTokens = row['output_tokens'] as int;
      final inPrice = row['input_price'] as double;
      final outPrice = row['output_price'] as double;
      final billingMode = row['billing_mode'] as String? ?? 'token';
      final reqCount = row['request_count'] as int? ?? 1;
      final reqPrice = row['request_price'] as double? ?? 0.0;
      final modelPk = row['model_pk'] as int?;

      totalInput += inTokens;
      totalOutput += outTokens;
      totalRequests += reqCount;

      double cost = 0.0;
      if (billingMode == 'request') {
        cost = (reqCount * reqPrice);
      } else {
        cost = (inTokens / 1000000 * inPrice) + (outTokens / 1000000 * outPrice);
      }
      totalCost += cost;

      // Find Fee Group ID for this usage record
      int? groupId;
      if (modelPk != null) {
        final model = _models.cast<Map<String, dynamic>?>().firstWhere((m) => m?['id'] == modelPk, orElse: () => null);
        if (model != null) groupId = model['fee_group_id'] as int?;
      }
      
      groupCosts[groupId] = (groupCosts[groupId] ?? 0.0) + cost;
    }

    return Column(
      children: [
        _buildFilterBar(colorScheme, l10n),
        _buildSummaryCards(totalInput, totalOutput, totalRequests, totalCost, colorScheme, l10n),
        
        // Fee Group Summary Area
        if (groupCosts.isNotEmpty) 
          _buildGroupSummaryArea(groupCosts, colorScheme, l10n),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.latestLog, style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    tooltip: l10n.clearAllUsage,
                    onPressed: () => _confirmClearAll(l10n),
                  ),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshData),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _usageData.isEmpty
              ? const Center(child: Text('No usage data found for selected range.'))
              : _buildUsageList(colorScheme, l10n),
        ),
      ],
    );
  }

  Widget _buildGroupSummaryArea(Map<int?, double> groupCosts, ColorScheme colorScheme, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withAlpha(50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.secondaryContainer),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_outline, size: 16, color: colorScheme.secondary),
              const SizedBox(width: 8),
              Text(l10n.usageByGroup, style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.secondary)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: groupCosts.entries.map((entry) {
              final group = _feeGroups.cast<Map<String, dynamic>?>().firstWhere((g) => g?['id'] == entry.key, orElse: () => null);
              final name = group != null ? group['name'] : l10n.noFeeGroup;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text('\$${entry.value.toStringAsFixed(4)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme colorScheme, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round()),
      child: Column(
        children: [
          Row(
            children: [
              Text(l10n.modelsLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: _availableModelIds.map((m) {
                    final isSelected = _selectedModelIds.contains(m);
                    return FilterChip(
                      label: Text(m, style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            _selectedModelIds.add(m);
                          } else {
                            _selectedModelIds.remove(m);
                          }
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

  Widget _buildSummaryCards(int input, int output, int requests, double cost, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          _summaryCard(l10n.requests, requests.toString(), Icons.numbers, Colors.purple),
          const SizedBox(width: 16),
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
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          child: Column(
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey), overflow: TextOverflow.ellipsis),
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
        final billingMode = row['billing_mode'] as String? ?? 'token';
        final inTokens = row['input_tokens'] as int;
        final outTokens = row['output_tokens'] as int;
        final inPrice = row['input_price'] as double;
        final outPrice = row['output_price'] as double;
        final reqCount = row['request_count'] as int? ?? 1;
        final reqPrice = row['request_price'] as double? ?? 0.0;

        final cost = billingMode == 'request' 
            ? (reqCount * reqPrice)
            : (inTokens / 1000000 * inPrice) + (outTokens / 1000000 * outPrice);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(billingMode == 'request' ? Icons.ads_click : Icons.analytics_outlined, size: 20),
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
                  if (billingMode == 'token') ...[
                    _tokenBadge('IN: $inTokens', Colors.blue),
                    const SizedBox(width: 8),
                    _tokenBadge('OUT: $outTokens', Colors.green),
                  ] else ...[
                    _tokenBadge('${l10n.requests.toUpperCase()}: $reqCount', Colors.purple),
                    if (inTokens > 0 || outTokens > 0) ...[
                      const SizedBox(width: 8),
                      _tokenBadge('IN: $inTokens', Colors.blue.withAlpha(128)),
                      const SizedBox(width: 4),
                      _tokenBadge('OUT: $outTokens', Colors.green.withAlpha(128)),
                    ],
                  ],
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
        color: color.withAlpha((255 * 0.1).round()),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha((255 * 0.3).round())),
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
              if (context.mounted) {
                Navigator.pop(context);
                _refreshData();
              }
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
              if (context.mounted) {
                Navigator.pop(context);
                _refreshData();
              }
            },
            child: Text(l10n.clearModelData, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

