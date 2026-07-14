import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import 'usage_stats.dart';

/// Paged list of token-usage records, shared by the mobile and desktop views.
/// Set [shrinkWrap] when embedding inside another scroll view.
class UsageList extends StatelessWidget {
  final List<Map<String, dynamic>> usageData;
  final bool shrinkWrap;
  final VoidCallback onRefresh;
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  const UsageList({
    super.key,
    required this.usageData,
    this.shrinkWrap = false,
    required this.onRefresh,
    required this.hasMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    if (usageData.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Text('No usage data found for selected range.'),
      ));
    }

    final list = ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
      itemCount: usageData.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == usageData.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Center(
              child: isLoadingMore
                ? const CircularProgressIndicator()
                : OutlinedButton(
                    onPressed: onLoadMore,
                    child: const Text('Load More'),
                  ),
            ),
          );
        }

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
                    _buildTokenChip(Icons.input, Colors.blue, row['input_tokens']),
                    // Only rows that actually hit the cache carry the extra chip,
                    // keeping the common no-cache row as compact as before.
                    if ((row['cache_tokens'] as int? ?? 0) > 0) ...[
                      const SizedBox(width: 8),
                      _buildTokenChip(Icons.bolt, Colors.teal, row['cache_tokens']),
                    ],
                    const SizedBox(width: 8),
                    _buildTokenChip(Icons.output, Colors.green, row['output_tokens']),
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

    if (shrinkWrap) {
      return list;
    }
    return Expanded(child: list);
  }

  Widget _buildTokenChip(IconData icon, Color color, Object? tokens) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 2),
        Text('${tokens ?? 0}', style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildCostBadge(Map<String, dynamic> row) {
    final cost = calculateRowCost(row);

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
