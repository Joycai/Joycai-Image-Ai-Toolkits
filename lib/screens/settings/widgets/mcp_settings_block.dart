import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/mcp_server_state.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_setting_row.dart';
import '../../../widgets/ui/app_text_field.dart';
import 'settings_layout.dart';

class McpSettingsBlock extends StatefulWidget {
  const McpSettingsBlock({super.key, required this.server});
  final McpServerState server;
  @override
  State<McpSettingsBlock> createState() => _McpSettingsBlockState();
}

class _McpSettingsBlockState extends State<McpSettingsBlock> {
  final _port = TextEditingController();
  final _folders = TextEditingController();
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _port.text = '${server.port}';
    _folders.text = server.roots.join('\n');
  }

  @override
  void dispose() {
    _port.dispose();
    _folders.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final ready = server.supported && server.loaded && !server.busy;
        final error = switch (server.errorCode) {
          'port' => l10n.mcpInvalidPort,
          'folder' => l10n.mcpInvalidFolder,
          'bind' => l10n.mcpPortBusy,
          null => null,
          _ => l10n.mcpSettingsError,
        };
        return SettingsBlock(
          caption: l10n.mcpServerSettings,
          child: SettingsGroup(
            ruled: false,
            children: [
              AppToggleRow(
                title: l10n.enableMcpServer,
                description: server.supported ? l10n.mcpLocalDescription : l10n.mcpDesktopOnly,
                value: server.enabled,
                onChanged: ready
                    ? (value) => value
                          ? server.configure(
                              enable: value,
                              portText: _port.text,
                              folders: _folders.text,
                            )
                          : server.disable()
                    : null,
              ),
              Text(
                server.busy
                    ? l10n.mcpChanging
                    : server.running
                    ? l10n.mcpRunning
                    : l10n.mcpStopped,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (server.running) SelectableText(server.endpoint),
              if (error != null)
                Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              SettingsField(
                label: l10n.port,
                child: AppTextField(
                  key: const Key('mcp-port'),
                  controller: _port,
                  enabled: ready,
                  keyboardType: TextInputType.number,
                ),
              ),
              SettingsField(
                label: l10n.mcpReferenceFolders,
                child: AppTextField(
                  key: const Key('mcp-folders'),
                  controller: _folders,
                  enabled: ready,
                  maxLines: 3,
                  hint: l10n.mcpFoldersHint,
                ),
              ),
              Text(l10n.mcpCredentialNote, style: Theme.of(context).textTheme.bodySmall),
              Wrap(
                spacing: AppSpace.s10,
                runSpacing: AppSpace.s10,
                children: [
                  AppButton(
                    label: l10n.mcpApply,
                    size: AppButtonSize.compact,
                    onPressed: ready
                        ? () async {
                            setState(() => _copied = false);
                            await server.configure(
                              enable: server.enabled,
                              portText: _port.text,
                              folders: _folders.text,
                            );
                          }
                        : null,
                  ),
                  AppButton(
                    label: _copied ? l10n.mcpCopied : l10n.mcpCopyConfiguration,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.compact,
                    onPressed: ready
                        ? () async {
                            await Clipboard.setData(
                              ClipboardData(text: server.clientConfiguration),
                            );
                            if (mounted) setState(() => _copied = true);
                          }
                        : null,
                  ),
                  AppButton(
                    label: l10n.mcpRotateToken,
                    variant: AppButtonVariant.text,
                    size: AppButtonSize.compact,
                    onPressed: ready
                        ? () async {
                            setState(() => _copied = false);
                            await server.rotateToken();
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
