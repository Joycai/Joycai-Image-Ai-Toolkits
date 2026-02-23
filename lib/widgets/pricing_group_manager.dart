import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/responsive.dart';
import '../l10n/app_localizations.dart';
import '../models/pricing_group.dart';
import '../state/app_state.dart';

enum PricingGroupManagerMode {
  section,
  fullPage
}

class PricingGroupManager extends StatelessWidget {
  final PricingGroupManagerMode mode;

  const PricingGroupManager({
    super.key,
    this.mode = PricingGroupManagerMode.section,
  });

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final l10n = AppLocalizations.of(context)!;
    final groups = appState.allPricingGroups;
    final isMobile = Responsive.isMobile(context);

    if (groups.isEmpty) {
      return _buildEmptyState(context, appState, l10n);
    }

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = mode == PricingGroupManagerMode.section 
            ? 1 
            : (constraints.maxWidth > 900 ? 3 : (constraints.maxWidth > 600 ? 2 : 1));
        
        return GridView.builder(
          shrinkWrap: mode == PricingGroupManagerMode.section,
          physics: mode == PricingGroupManagerMode.section ? const NeverScrollableScrollPhysics() : null,
          padding: mode == PricingGroupManagerMode.fullPage ? const EdgeInsets.all(24) : EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 140,
          ),
          itemCount: groups.length,
          itemBuilder: (context, index) => _buildGroupCard(context, groups[index], appState, l10n),
        );
      },
    );

    if (mode == PricingGroupManagerMode.fullPage) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: isMobile ? FloatingActionButton.extended(
          onPressed: () => _showGroupEditor(context, appState, l10n),
          icon: const Icon(Icons.add),
          label: Text(l10n.addFeeGroup),
        ) : null,
        body: Column(
          children: [
            if (!isMobile)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.feeGroups, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                        Text(l10n.feeGroupDesc, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13)),
                      ],
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () => _showGroupEditor(context, appState, l10n),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addFeeGroup),
                    ),
                  ],
                ),
              ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.feeGroupDesc, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12))),
            IconButton(
              onPressed: () => _showGroupEditor(context, appState, l10n),
              icon: const Icon(Icons.add_circle_outline, size: 20),
              tooltip: l10n.addFeeGroup,
            ),
          ],
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, AppState appState, AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.monetization_on_outlined, size: 64, color: Theme.of(context).colorScheme.primary.withAlpha(150)),
            ),
            const SizedBox(height: 24),
            Text(l10n.noFeeGroups, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(l10n.feeGroupDesc, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _showGroupEditor(context, appState, l10n),
              icon: const Icon(Icons.add),
              label: Text(l10n.addFeeGroup),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(BuildContext context, PricingGroup group, AppState appState, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    final isToken = group.billingMode == 'token';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showGroupEditor(context, appState, l10n, group: group),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isToken ? Colors.blue : Colors.purple).withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isToken ? Icons.token_outlined : Icons.ads_click, size: 14, color: isToken ? Colors.blue : Colors.purple),
                        const SizedBox(width: 4),
                        Text(
                          isToken ? l10n.tokenBilling : l10n.requestBilling,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isToken ? Colors.blue : Colors.purple),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDelete(context, appState, l10n, group),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              if (isToken) ...[
                _buildPriceRow(l10n.inputPrice, group.inputPrice, "M", colorScheme),
                _buildPriceRow(l10n.outputPrice, group.outputPrice, "M", colorScheme),
              ] else ...[
                _buildPriceRow(l10n.requestPrice, group.requestPrice, "Req", colorScheme),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, double price, String unit, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: colorScheme.outline)),
          Text("\$${price.toStringAsFixed(4)} / $unit", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppState appState, AppLocalizations l10n, PricingGroup group) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.deleteFeeGroupConfirm(group.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await appState.deletePricingGroup(group.id!);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  void _showGroupEditor(BuildContext context, AppState appState, AppLocalizations l10n, {PricingGroup? group}) {
    if (Responsive.isMobile(context)) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => _PricingGroupEditor(appState: appState, l10n: l10n, group: group, isMobile: true),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(group == null ? l10n.addFeeGroup : l10n.editFeeGroup),
          content: SizedBox(
            width: 450,
            child: _PricingGroupEditor(appState: appState, l10n: l10n, group: group, isMobile: false),
          ),
        ),
      );
    }
  }
}

class _PricingGroupEditor extends StatefulWidget {
  final AppState appState;
  final AppLocalizations l10n;
  final PricingGroup? group;
  final bool isMobile;

  const _PricingGroupEditor({
    required this.appState,
    required this.l10n,
    this.group,
    required this.isMobile,
  });

  @override
  State<_PricingGroupEditor> createState() => _PricingGroupEditorState();
}

class _PricingGroupEditorState extends State<_PricingGroupEditor> {
  late TextEditingController nameCtrl;
  late TextEditingController inputPriceCtrl;
  late TextEditingController outputPriceCtrl;
  late TextEditingController requestPriceCtrl;
  late String billingMode;

  @override
  void initState() {
    super.initState();
    final g = widget.group;
    nameCtrl = TextEditingController(text: g?.name ?? '');
    inputPriceCtrl = TextEditingController(text: (g?.inputPrice ?? 0.0).toString());
    outputPriceCtrl = TextEditingController(text: (g?.outputPrice ?? 0.0).toString());
    requestPriceCtrl = TextEditingController(text: (g?.requestPrice ?? 0.0).toString());
    billingMode = g?.billingMode ?? 'token';
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    inputPriceCtrl.dispose();
    outputPriceCtrl.dispose();
    requestPriceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    
    final content = SingleChildScrollView(
      padding: widget.isMobile ? const EdgeInsets.all(24) : EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isMobile) ...[
            Text(widget.group == null ? l10n.addFeeGroup : l10n.editFeeGroup, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
          ],
          TextField(
            controller: nameCtrl, 
            decoration: InputDecoration(
              labelText: l10n.groupName,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: billingMode,
            items: [
              DropdownMenuItem(value: 'token', child: Text(l10n.perToken)),
              DropdownMenuItem(value: 'request', child: Text(l10n.perRequest)),
            ],
            onChanged: (v) => setState(() => billingMode = v!),
            decoration: InputDecoration(
              labelText: l10n.billingMode,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 24),
          if (billingMode == 'token') ...[
            Row(
              children: [
                Expanded(child: _buildPriceField(inputPriceCtrl, l10n.inputPrice, "\$/M")),
                const SizedBox(width: 16),
                Expanded(child: _buildPriceField(outputPriceCtrl, l10n.outputPrice, "\$/M")),
              ],
            ),
          ] else
            _buildPriceField(requestPriceCtrl, l10n.requestPrice, "\$/Req"),
          
          if (widget.isMobile) ...[
            const SizedBox(height: 40),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: Text(widget.group == null ? l10n.add : l10n.save),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: Text(l10n.cancel),
            ),
          ],
        ],
      ),
    );

    if (widget.isMobile) return content;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _save,
              child: Text(widget.group == null ? l10n.add : l10n.save),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPriceField(TextEditingController ctrl, String label, String suffix) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _save() async {
    final data = {
      'name': nameCtrl.text.trim().isEmpty ? "Unnamed Group" : nameCtrl.text.trim(),
      'billing_mode': billingMode,
      'input_price': double.tryParse(inputPriceCtrl.text) ?? 0.0,
      'output_price': double.tryParse(outputPriceCtrl.text) ?? 0.0,
      'request_price': double.tryParse(requestPriceCtrl.text) ?? 0.0,
    };
    if (widget.group == null) {
      await widget.appState.addPricingGroup(data);
    } else {
      await widget.appState.updatePricingGroup(widget.group!.id!, data);
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }
}
