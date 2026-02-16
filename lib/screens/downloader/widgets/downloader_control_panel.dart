import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../state/app_state.dart';
import '../../../widgets/api_key_field.dart';
import '../../../widgets/chat_model_selector.dart';

class DownloaderControlPanel extends StatelessWidget {
  final TextEditingController urlController;
  final TextEditingController requirementController;
  final TextEditingController cookieController;
  final TextEditingController prefixController;
  final TextEditingController manualHtmlController;
  final bool isAnalyzing;
  final VoidCallback onAnalyze;
  final VoidCallback onSaveHtml;
  final VoidCallback onPasteHtml;
  final VoidCallback onImportCookie;

  const DownloaderControlPanel({
    super.key,
    required this.urlController,
    required this.requirementController,
    required this.cookieController,
    required this.prefixController,
    required this.manualHtmlController,
    required this.isAnalyzing,
    required this.onAnalyze,
    required this.onSaveHtml,
    required this.onPasteHtml,
    required this.onImportCookie,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final appState = Provider.of<AppState>(context);
    final state = appState.downloaderState;
    final colorScheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCard(
            colorScheme,
            child: Column(
              children: [
                TextField(
                  controller: urlController,
                  decoration: InputDecoration(
                    labelText: l10n.websiteUrl,
                    hintText: l10n.websiteUrlHint,
                    prefixIcon: const Icon(Icons.link),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: requirementController,
                  decoration: InputDecoration(
                    labelText: l10n.whatToFind,
                    hintText: l10n.whatToFindHint,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                ChatModelSelector(
                  selectedModelId: state.selectedModelPk,
                  label: l10n.analysisModel,
                  prefixIcon: Icons.psychology,
                  onChanged: (v) => state.setState(selectedModelPk: v),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          _buildCard(
            colorScheme,
            title: l10n.manualHtmlMode,
            trailing: Switch(
              value: state.isManualHtml,
              onChanged: (v) => state.setState(isManualHtml: v),
            ),
            child: state.isManualHtml ? Column(
              children: [
                TextField(
                  controller: manualHtmlController,
                  decoration: InputDecoration(
                    labelText: l10n.manualHtmlHint,
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 4,
                  readOnly: true,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(onPressed: onPasteHtml, icon: const Icon(Icons.paste, size: 18), label: Text(l10n.pasteFromClipboard)),
                    TextButton.icon(
                      onPressed: () { state.setState(manualHtml: ''); manualHtmlController.clear(); }, 
                      icon: const Icon(Icons.clear, size: 18), 
                      label: Text(l10n.clear),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ) : const SizedBox.shrink(),
          ),

          const SizedBox(height: 20),

          ExpansionTile(
            title: Text(l10n.advancedOptions, style: const TextStyle(fontWeight: FontWeight.bold)),
            leading: const Icon(Icons.settings_suggest),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: prefixController,
                      decoration: InputDecoration(labelText: l10n.filenamePrefix, border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ApiKeyField(
                            controller: cookieController,
                            label: l10n.cookiesHint,
                            maxLines: 3,
                            onChanged: (v) {},
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (val) {
                            if (val == 'import') onImportCookie();
                            if (val == 'history') _showCookieHistory(context, state, l10n);
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'import',
                              child: ListTile(
                                leading: const Icon(Icons.upload_file),
                                title: Text(l10n.importCookieFile),
                                dense: true,
                              ),
                            ),
                            if (state.cookieHistory.isNotEmpty)
                              PopupMenuItem(
                                value: 'history',
                                child: ListTile(
                                  leading: const Icon(Icons.history),
                                  title: Text(l10n.cookieHistory),
                                  dense: true,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),
          
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: isAnalyzing ? null : onAnalyze,
              icon: isAnalyzing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.analytics),
              label: Text(isAnalyzing ? l10n.analyzing : l10n.findImages),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isAnalyzing ? null : onSaveHtml,
              icon: const Icon(Icons.html),
              label: Text(l10n.saveOriginHtml),
            ),
          ),

          if (state.logs.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(l10n.logs, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 150,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: state.logs.length,
                itemBuilder: (context, i) => Text(state.logs[i], style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(ColorScheme colorScheme, {Widget? child, String? title, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withAlpha(100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (title case final String t) Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  if (trailing case final Widget w) w,
                ],
              ),
            ),
          if (child case final Widget c) c,
        ],
      ),
    );
  }

  void _showCookieHistory(BuildContext context, dynamic state, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: state.cookieHistory.map<Widget>((h) => ListTile(
          leading: const Icon(Icons.history),
          title: Text(h['host']),
          onTap: () {
            cookieController.text = h['cookies'];
            state.setState(cookies: h['cookies']);
            Navigator.pop(context);
          },
        )).toList(),
      ),
    );
  }
}
