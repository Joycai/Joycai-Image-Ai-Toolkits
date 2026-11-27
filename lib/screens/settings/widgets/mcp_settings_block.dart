import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/files/directory_access_service.dart';
import '../../../state/mcp_server_state.dart';
import '../../../widgets/ui/app_breathing_dot.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_dialog.dart';
import '../../../widgets/ui/app_icon_button.dart';
import '../../../widgets/ui/app_segmented_control.dart';
import '../../../widgets/ui/app_snackbar.dart';
import '../../../widgets/ui/app_switch.dart';
import '../../../widgets/ui/app_text_field.dart';
import '../../../widgets/ui/dashed_border.dart';
import 'settings_layout.dart';

enum _McpFoldersView { list, text }

/// MCP server settings card with live status dashboard, token reveal/copy,
/// dual-view allowed folder list/text editor, and guarded action footer.
class McpSettingsBlock extends StatefulWidget {
  const McpSettingsBlock({
    super.key,
    required this.server,
    this.isMobile = false,
    this.onPickFolder,
  });

  final McpServerState server;
  final bool isMobile;
  final Future<String?> Function()? onPickFolder;

  @override
  State<McpSettingsBlock> createState() => _McpSettingsBlockState();
}

class _McpSettingsBlockState extends State<McpSettingsBlock> {
  final TextEditingController _port = TextEditingController();
  final TextEditingController _folders = TextEditingController();
  final TextEditingController _newFolder = TextEditingController();

  late String _lastSyncedPort;
  late String _lastSyncedFolders;

  _McpFoldersView _foldersView = _McpFoldersView.list;
  bool _addingFolder = false;
  bool _newFolderRecursive = true;
  bool _tokenVisible = false;
  bool _copiedEndpoint = false;
  bool _copiedToken = false;
  bool _copiedConfig = false;

  @override
  void initState() {
    super.initState();
    _syncFromServer(force: true);
    widget.server.addListener(_onServerChanged);
  }

  @override
  void didUpdateWidget(McpSettingsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.server != widget.server) {
      oldWidget.server.removeListener(_onServerChanged);
      _syncFromServer(force: true);
      widget.server.addListener(_onServerChanged);
    }
  }

  @override
  void dispose() {
    widget.server.removeListener(_onServerChanged);
    _port.dispose();
    _folders.dispose();
    _newFolder.dispose();
    super.dispose();
  }

  void _syncFromServer({bool force = false}) {
    final serverPort = '${widget.server.port}';
    final serverFolders = widget.server.roots.join('\n');
    if (force) {
      _lastSyncedPort = serverPort;
      _lastSyncedFolders = serverFolders;
      _port.text = serverPort;
      _folders.text = serverFolders;
      return;
    }
    if (_port.text == _lastSyncedPort && serverPort != _lastSyncedPort) {
      _port.text = serverPort;
      _lastSyncedPort = serverPort;
    }
    if (_folders.text == _lastSyncedFolders && serverFolders != _lastSyncedFolders) {
      _folders.text = serverFolders;
      _lastSyncedFolders = serverFolders;
    }
  }

  void _onServerChanged() {
    if (!mounted) return;
    _syncFromServer();
    setState(() {});
  }

  static List<String> _parseLines(String text) =>
      text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  static bool _isDirectOnlyRule(String line) => line.endsWith('/*') && !line.endsWith('/**');

  bool get _isDirty =>
      _port.text.trim() != '${widget.server.port}' ||
      _parseLines(_folders.text).join('\n') != widget.server.roots.join('\n');

  String get _previewEndpoint {
    final parsed = int.tryParse(_port.text.trim());
    if (parsed != null && parsed >= 1024 && parsed <= 65535) {
      return 'http://127.0.0.1:$parsed/mcp';
    }
    return widget.server.endpoint;
  }

  Future<void> _copyEndpoint(AppLocalizations l10n) async {
    await Clipboard.setData(ClipboardData(text: _previewEndpoint));
    if (!mounted) return;
    setState(() {
      _copiedEndpoint = true;
      _copiedToken = false;
      _copiedConfig = false;
    });
    AppSnackBar.success(context, l10n.mcpEndpointCopied);
  }

  Future<void> _copyToken(AppLocalizations l10n) async {
    final token = widget.server.token;
    if (token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: token));
    if (!mounted) return;
    setState(() {
      _copiedToken = true;
      _copiedEndpoint = false;
      _copiedConfig = false;
    });
    AppSnackBar.success(context, l10n.mcpTokenCopied);
  }

  Future<void> _copyConfig() async {
    await Clipboard.setData(ClipboardData(text: widget.server.clientConfiguration));
    if (!mounted) return;
    setState(() {
      _copiedConfig = true;
      _copiedEndpoint = false;
      _copiedToken = false;
    });
  }

  Future<void> _pickNewFolder() async {
    final picked =
        await (widget.onPickFolder?.call() ??
            DirectoryAccessService.instance.pickDirectory(readOnly: true));
    if (!mounted || picked == null || picked.trim().isEmpty) return;
    _newFolder.text = picked.trim();
  }

  void _commitNewFolder() {
    var path = _newFolder.text.trim();
    if (path.isEmpty) return;
    if (!path.endsWith('/*') && !path.endsWith('/**')) {
      final clean = path.length > 1 && path.endsWith('/')
          ? path.substring(0, path.length - 1)
          : path;
      path = _newFolderRecursive ? '$clean/**' : '$clean/*';
    }
    final lines = _parseLines(_folders.text);
    if (!lines.contains(path)) {
      lines.add(path);
      _folders.text = lines.join('\n');
    }
    setState(() {
      _newFolder.clear();
      _addingFolder = false;
    });
  }

  void _removeFolderAt(int index) {
    final lines = _parseLines(_folders.text);
    if (index < 0 || index >= lines.length) return;
    lines.removeAt(index);
    setState(() => _folders.text = lines.join('\n'));
  }

  Future<void> _apply() async {
    setState(() {
      _copiedEndpoint = false;
      _copiedToken = false;
      _copiedConfig = false;
    });
    await widget.server.configure(
      enable: widget.server.enabled,
      portText: _port.text,
      folders: _folders.text,
    );
    if (!mounted) return;
    if (widget.server.errorCode == null) {
      _syncFromServer(force: true);
      setState(() {});
    }
  }

  Future<void> _confirmRotateToken(AppLocalizations l10n) async {
    final theme = Theme.of(context);
    final confirmed = await AppDialog.show<bool>(
      context,
      title: l10n.mcpRotateTokenConfirmTitle,
      icon: Icons.refresh_rounded,
      iconColor: theme.colorScheme.error,
      maxWidth: 440,
      content: Text(
        l10n.mcpRotateTokenConfirmBody,
        style: theme.textTheme.bodyMedium?.copyWith(height: AppType.proseHeight),
      ),
      actions: [
        AppButton(
          variant: AppButtonVariant.text,
          autofocus: true,
          label: l10n.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppButton(
          key: const Key('mcp-confirm-rotate-token'),
          variant: AppButtonVariant.destructive,
          label: l10n.mcpRotateToken,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _copiedConfig = false;
      _copiedToken = false;
    });
    await widget.server.rotateToken();
    if (!mounted) return;
    if (widget.server.errorCode == null) {
      AppSnackBar.success(context, l10n.mcpTokenRotated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.server;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final semantic = context.semantic;
    final l10n = AppLocalizations.of(context)!;

    final ready = server.supported && server.loaded && !server.busy;
    final error = switch (server.errorCode) {
      'port' => l10n.mcpInvalidPort,
      'folder' => l10n.mcpInvalidFolder,
      'bind' => l10n.mcpPortBusy,
      null => null,
      _ => l10n.mcpSettingsError,
    };

    final lines = _parseLines(_folders.text);

    return SettingsBlock(
      caption: l10n.mcpServerSettings,
      child: Material(
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.s16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Wrap(
                            spacing: AppSpace.s6,
                            runSpacing: AppSpace.s4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                l10n.enableMcpServer,
                                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                              ),
                              if (_isDirty && server.supported)
                                _UnsavedBadge(label: l10n.mcpUnsavedChanges),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            server.supported ? l10n.mcpLocalDescription : l10n.mcpDesktopOnly,
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              height: AppType.proseHeight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.s10),
                    AppSwitch(
                      key: const Key('mcp-enabled-switch'),
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
                  ],
                ),
              ),
            ),
            if (server.supported) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpace.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _McpStatusBar(
                      server: server,
                      endpoint: _previewEndpoint,
                      isMobile: widget.isMobile,
                      copied: _copiedEndpoint,
                      onCopy: ready ? () => _copyEndpoint(l10n) : null,
                    ),
                    const SizedBox(height: AppSpace.s16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stacked = widget.isMobile || constraints.maxWidth < 420;
                        final portField = SettingsField(
                          label: l10n.port,
                          enabled: ready,
                          child: AppTextField(
                            key: const Key('mcp-port'),
                            controller: _port,
                            enabled: ready,
                            keyboardType: TextInputType.number,
                            style: textTheme.bodyMedium?.mono,
                            onChanged: (_) => setState(() {}),
                          ),
                        );
                        final tokenField = _TokenField(
                          label: l10n.mcpAccessToken,
                          value: _tokenVisible ? server.token : server.maskedToken,
                          visible: _tokenVisible,
                          copied: _copiedToken,
                          enabled: ready && server.token.isNotEmpty,
                          onToggleVisibility: () => setState(() => _tokenVisible = !_tokenVisible),
                          onCopy: () => _copyToken(l10n),
                        );
                        if (stacked) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              portField,
                              const SizedBox(height: AppSpace.s10),
                              tokenField,
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 152, child: portField),
                            const SizedBox(width: AppSpace.s10),
                            Expanded(child: tokenField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSpace.s16),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.s10,
                      runSpacing: AppSpace.s6,
                      children: [
                        Text(
                          l10n.mcpReferenceFolders,
                          style: textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                            color: ready ? colorScheme.onSurfaceVariant : colorScheme.outline,
                          ),
                        ),
                        Wrap(
                          spacing: AppSpace.s6,
                          runSpacing: AppSpace.s6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppSegmentedControl<_McpFoldersView>(
                              key: const Key('mcp-folders-view'),
                              value: _foldersView,
                              compact: true,
                              style: AppSegmentStyle.raised,
                              track: AppSegmentTrack.outlined,
                              segments: [
                                AppSegment(
                                  value: _McpFoldersView.list,
                                  label: l10n.mcpFoldersViewList,
                                ),
                                AppSegment(
                                  value: _McpFoldersView.text,
                                  label: l10n.mcpFoldersViewText,
                                ),
                              ],
                              onChanged: (next) => setState(() {
                                _foldersView = next;
                                if (next == _McpFoldersView.text) _addingFolder = false;
                              }),
                            ),
                            if (_foldersView == _McpFoldersView.list)
                              AppButton(
                                key: const Key('mcp-add-folder-button'),
                                variant: AppButtonVariant.secondary,
                                size: AppButtonSize.compact,
                                icon: Icons.add_rounded,
                                label: l10n.mcpAddFolder,
                                onPressed: ready
                                    ? () => setState(() => _addingFolder = !_addingFolder)
                                    : null,
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.s6),
                    if (_foldersView == _McpFoldersView.list) ...[
                      ClipRect(
                        child: AnimatedSize(
                          duration: AppMotion.sceneOf(context),
                          curve: AppMotion.enter,
                          alignment: Alignment.topCenter,
                          child: !_addingFolder
                              ? const SizedBox(width: double.infinity, height: 0)
                              : Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpace.s6),
                                  child: _AddFolderComposer(
                                    controller: _newFolder,
                                    recursive: _newFolderRecursive,
                                    enabled: ready,
                                    onRecursiveChanged: (v) =>
                                        setState(() => _newFolderRecursive = v),
                                    onPickFolder: _pickNewFolder,
                                    onCancel: () => setState(() {
                                      _addingFolder = false;
                                      _newFolder.clear();
                                    }),
                                    onConfirm: _commitNewFolder,
                                  ),
                                ),
                        ),
                      ),
                      if (lines.isEmpty)
                        DashedBorder(
                          color: colorScheme.outlineVariant,
                          radius: AppRadius.control,
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpace.s16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.folder_off_outlined,
                                  size: AppSize.iconMd,
                                  color: colorScheme.outline,
                                ),
                                const SizedBox(width: AppSpace.s6),
                                Flexible(
                                  child: Text(
                                    l10n.mcpFoldersEmpty,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      height: AppType.proseHeight,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (int i, String line) in lines.indexed) ...[
                              if (i > 0) const SizedBox(height: AppSpace.s6),
                              _FolderRuleRow(
                                index: i,
                                line: line,
                                directOnly: _isDirectOnlyRule(line),
                                onRemove: ready ? () => _removeFolderAt(i) : null,
                              ),
                            ],
                          ],
                        ),
                    ] else ...[
                      SettingsFieldScope(
                        enabled: ready,
                        child: AppTextField(
                          key: const Key('mcp-folders'),
                          controller: _folders,
                          enabled: ready,
                          minLines: 3,
                          maxLines: 5,
                          hint: l10n.mcpFolderPathHint,
                          style: textTheme.bodyMedium?.mono,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: AppSpace.s6),
                      Text(
                        l10n.mcpFoldersHint,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: AppType.proseHeight,
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: AppSpace.s10),
                      DecoratedBox(
                        key: const Key('mcp-error-banner'),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          border: Border.all(color: colorScheme.error),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpace.s10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline_rounded,
                                size: AppSize.iconMd,
                                color: colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: AppSpace.s6),
                              Expanded(
                                child: Text(
                                  error,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onErrorContainer,
                                    height: AppType.proseHeight,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.s16),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: semantic.warningContainer,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpace.s10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: AppSize.iconMd,
                              color: semantic.onWarningContainer,
                            ),
                            const SizedBox(width: AppSpace.s6),
                            Expanded(
                              child: Text(
                                l10n.mcpCredentialNote,
                                style: textTheme.bodySmall?.copyWith(
                                  color: semantic.onWarningContainer,
                                  height: AppType.proseHeight,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              DecoratedBox(
                decoration: BoxDecoration(color: colorScheme.surface),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.s16,
                    vertical: AppSpace.s10,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final applyBtn = AppButton(
                        label: l10n.mcpApply,
                        size: AppButtonSize.compact,
                        loading: server.busy,
                        onPressed: ready ? _apply : null,
                      );
                      final copyBtn = AppButton(
                        label: _copiedConfig ? l10n.mcpCopied : l10n.mcpCopyConfiguration,
                        variant: AppButtonVariant.secondary,
                        size: AppButtonSize.compact,
                        onPressed: ready ? _copyConfig : null,
                      );
                      final rotateBtn = AppButton(
                        key: const Key('mcp-rotate-token'),
                        label: l10n.mcpRotateToken,
                        variant: AppButtonVariant.destructiveText,
                        size: AppButtonSize.compact,
                        icon: Icons.refresh_rounded,
                        onPressed: ready ? () => _confirmRotateToken(l10n) : null,
                      );

                      return SizedBox(
                        width: constraints.maxWidth,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: AppSpace.s10,
                          runSpacing: AppSpace.s6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Wrap(
                              spacing: AppSpace.s10,
                              runSpacing: AppSpace.s6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [applyBtn, copyBtn],
                            ),
                            rotateBtn,
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnsavedBadge extends StatelessWidget {
  const _UnsavedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2),
        child: Text(
          label,
          style: textTheme.labelSmall?.copyWith(color: semantic.onWarningContainer),
        ),
      ),
    );
  }
}

class _McpStatusBar extends StatelessWidget {
  const _McpStatusBar({
    required this.server,
    required this.endpoint,
    required this.isMobile,
    required this.copied,
    required this.onCopy,
  });

  final McpServerState server;
  final String endpoint;
  final bool isMobile;
  final bool copied;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;
    final l10n = AppLocalizations.of(context)!;

    final Color pillBg;
    final Color pillFg;
    final Color dotColor;
    final bool breathing;
    final String statusLabel;

    if (server.busy) {
      pillBg = colorScheme.accentTint;
      pillFg = colorScheme.onAccentTint;
      dotColor = colorScheme.primary;
      breathing = true;
      statusLabel = l10n.mcpChanging;
    } else if (server.running) {
      pillBg = semantic.successContainer;
      pillFg = semantic.onSuccessContainer;
      dotColor = semantic.success;
      breathing = true;
      statusLabel = l10n.mcpRunning;
    } else {
      pillBg = colorScheme.surfaceContainerHighest;
      pillFg = colorScheme.onSurfaceVariant;
      dotColor = colorScheme.outline;
      breathing = false;
      statusLabel = l10n.mcpStopped;
    }

    final pill = DecoratedBox(
      decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBreathingDot(color: dotColor, size: 7, breathing: breathing),
            const SizedBox(width: AppSpace.s6),
            Text(
              statusLabel,
              style: textTheme.labelSmall?.copyWith(color: pillFg, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );

    final endpointText = Tooltip(
      message: endpoint,
      child: Text(
        endpoint,
        key: const Key('mcp-endpoint-url'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.mono.copyWith(
          color: server.running ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
        ),
      ),
    );

    final copyButton = AppButton(
      key: const Key('mcp-copy-endpoint'),
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.compact,
      icon: copied ? Icons.check_rounded : Icons.content_copy_rounded,
      label: copied ? l10n.mcpCopied : l10n.mcpCopyEndpoint,
      onPressed: onCopy,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = isMobile || constraints.maxWidth < 460;
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: constraints.maxWidth,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.s6,
                      runSpacing: AppSpace.s6,
                      children: [pill, copyButton],
                    ),
                  ),
                  const SizedBox(height: AppSpace.s6),
                  endpointText,
                ],
              );
            }
            return Row(
              children: [
                pill,
                const SizedBox(width: AppSpace.s10),
                Expanded(child: endpointText),
                const SizedBox(width: AppSpace.s10),
                copyButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TokenField extends StatelessWidget {
  const _TokenField({
    required this.label,
    required this.value,
    required this.visible,
    required this.copied,
    required this.enabled,
    required this.onToggleVisibility,
    required this.onCopy,
  });

  final String label;
  final String value;
  final bool visible;
  final bool copied;
  final bool enabled;
  final VoidCallback onToggleVisibility;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w400,
            color: enabled ? colorScheme.onSurfaceVariant : colorScheme.outline,
          ),
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 38),
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpace.s10, right: AppSpace.s4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      key: const Key('mcp-token-value'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.mono.copyWith(
                        color: enabled ? colorScheme.onSurface : colorScheme.outline,
                      ),
                    ),
                  ),
                  AppIconButton(
                    key: const Key('mcp-token-visibility'),
                    outlined: false,
                    size: AppSize.compact,
                    icon: visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    tooltip: visible ? l10n.mcpHideToken : l10n.mcpRevealToken,
                    onPressed: enabled ? onToggleVisibility : null,
                  ),
                  AppIconButton(
                    key: const Key('mcp-token-copy'),
                    outlined: false,
                    size: AppSize.compact,
                    icon: copied ? Icons.check_rounded : Icons.content_copy_rounded,
                    tooltip: l10n.mcpCopyToken,
                    onPressed: enabled ? onCopy : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddFolderComposer extends StatelessWidget {
  const _AddFolderComposer({
    required this.controller,
    required this.recursive,
    required this.enabled,
    required this.onRecursiveChanged,
    required this.onPickFolder,
    required this.onCancel,
    required this.onConfirm,
  });

  final TextEditingController controller;
  final bool recursive;
  final bool enabled;
  final ValueChanged<bool> onRecursiveChanged;
  final VoidCallback onPickFolder;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: SettingsFieldScope(
                    enabled: enabled,
                    child: AppTextField(
                      key: const Key('mcp-add-folder-input'),
                      controller: controller,
                      enabled: enabled,
                      hint: l10n.mcpFolderPathHint,
                      style: textTheme.bodySmall?.mono,
                      onSubmitted: (_) => onConfirm(),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.s6),
                AppIconButton(
                  key: const Key('mcp-browse-folder-button'),
                  icon: Icons.folder_open_outlined,
                  tooltip: l10n.mcpBrowseFolder,
                  onPressed: enabled ? onPickFolder : null,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s6),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpace.s10,
              runSpacing: AppSpace.s6,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: enabled ? () => onRecursiveChanged(!recursive) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            key: const Key('mcp-add-folder-recursive'),
                            value: recursive,
                            onChanged: enabled ? (v) => onRecursiveChanged(v ?? true) : null,
                          ),
                        ),
                        const SizedBox(width: AppSpace.s6),
                        Text(l10n.mcpIncludeSubfolders, style: textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppButton(
                      variant: AppButtonVariant.text,
                      size: AppButtonSize.compact,
                      label: l10n.cancel,
                      onPressed: onCancel,
                    ),
                    const SizedBox(width: AppSpace.s6),
                    AppButton(
                      key: const Key('mcp-confirm-add-folder'),
                      variant: AppButtonVariant.primary,
                      size: AppButtonSize.compact,
                      label: l10n.add,
                      onPressed: enabled ? onConfirm : null,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderRuleRow extends StatelessWidget {
  const _FolderRuleRow({
    required this.index,
    required this.line,
    required this.directOnly,
    required this.onRemove,
  });

  final int index;
  final String line;
  final bool directOnly;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s10, AppSpace.s6, AppSpace.s4, AppSpace.s6),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: AppSize.iconMd, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpace.s6),
            Expanded(
              child: Tooltip(
                message: line,
                child: Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.mono,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.s6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: directOnly ? colorScheme.surfaceContainerHighest : colorScheme.accentTint,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2),
                child: Text(
                  directOnly ? l10n.mcpFolderDirectOnly : l10n.mcpFolderRecursive,
                  style: textTheme.labelSmall?.copyWith(
                    color: directOnly ? colorScheme.onSurfaceVariant : colorScheme.onAccentTint,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.s4),
            AppIconButton(
              key: Key('mcp-remove-folder-$index'),
              outlined: false,
              size: AppSize.compact,
              icon: Icons.close_rounded,
              tooltip: l10n.mcpRemoveFolder,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
