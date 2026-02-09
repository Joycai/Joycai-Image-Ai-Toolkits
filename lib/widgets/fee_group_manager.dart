import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/fee_group.dart';
import '../state/app_state.dart';

enum FeeGroupManagerMode {
  section,
  fullPage
}

class FeeGroupManager extends StatelessWidget {
  final FeeGroupManagerMode mode;

  const FeeGroupManager({
    super.key,
    this.mode = FeeGroupManagerMode.section,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
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
              onPressed: () => _showGroupDialog(context, appState, l10n),
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
        final billingMode = group.billingMode;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              billingMode == 'request' ? Icons.ads_click : Icons.token,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(group.name),
            subtitle: Text(billingMode == 'request'
              ? '\$${group.requestPrice}/Req'
              : 'In: \$${group.inputPrice}/M | Out: \$${group.outputPrice}/M'
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _showGroupDialog(context, appState, l10n, group: group),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, appState, l10n, group),
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
          onPressed: () => _showGroupDialog(context, appState, l10n),
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
          onPressed: () => _showGroupDialog(context, appState, l10n),
          icon: const Icon(Icons.add),
          label: Text(l10n.addFeeGroup),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, AppState appState, AppLocalizations l10n, FeeGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteFeeGroupConfirm(group.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await appState.deleteFeeGroup(group.id!);
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

  void _showGroupDialog(BuildContext context, AppState appState, AppLocalizations l10n, {FeeGroup? group}) {
    final nameCtrl = TextEditingController(text: group?.name ?? '');
    final inputPriceCtrl = TextEditingController(text: (group?.inputPrice ?? 0.0).toString());
    final outputPriceCtrl = TextEditingController(text: (group?.outputPrice ?? 0.0).toString());
    final requestPriceCtrl = TextEditingController(text: (group?.requestPrice ?? 0.0).toString());
    String billingMode = group?.billingMode ?? 'token';

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
                  await appState.updateFeeGroup(group.id!, data);
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