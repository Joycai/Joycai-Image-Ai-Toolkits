import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';

enum FeeGroupManagerMode {
  section,
  fullPage
}

class FeeGroupManager extends StatelessWidget {
  final AppState appState;
  final FeeGroupManagerMode mode;

  const FeeGroupManager({
    super.key,
    required this.appState,
    this.mode = FeeGroupManagerMode.section,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groups = appState.allFeeGroups;

    if (groups.isEmpty && mode == FeeGroupManagerMode.fullPage) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.monetization_on_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(l10n.noModelsConfigured, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showGroupDialog(context, l10n),
              icon: const Icon(Icons.add),
              label: Text(l10n.addFeeGroup),
            ),
          ],
        ),
      );
    }

    final listView = ListView.builder(
      shrinkWrap: mode == FeeGroupManagerMode.section,
      physics: mode == FeeGroupManagerMode.section ? const NeverScrollableScrollPhysics() : null,
      padding: mode == FeeGroupManagerMode.fullPage ? const EdgeInsets.all(16) : EdgeInsets.zero,
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final billingMode = group['billing_mode'] as String;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
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
                  onPressed: () => _showGroupDialog(context, l10n, group: group),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, l10n, group),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (mode == FeeGroupManagerMode.fullPage) {
      return Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showGroupDialog(context, l10n),
          child: const Icon(Icons.add),
        ),
        body: listView,
      );
    }

    return Column(
      children: [
        listView,
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showGroupDialog(context, l10n),
          icon: const Icon(Icons.add),
          label: Text(l10n.addFeeGroup),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, AppLocalizations l10n, Map<String, dynamic> group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteFeeGroupConfirm(group['name'])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await appState.deleteFeeGroup(group['id']);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(l10n.delete, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showGroupDialog(BuildContext context, AppLocalizations l10n, {Map<String, dynamic>? group}) {
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
                  await appState.addFeeGroup(data);
                } else {
                  await appState.updateFeeGroup(group['id'], data);
                }
                if (context.mounted) {
                  Navigator.pop(context);
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
