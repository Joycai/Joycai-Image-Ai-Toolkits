import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../core/app_semantic_colors.dart';
import '../../../core/app_theme.dart';
import '../../../core/design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/system/proxy_probe_service.dart';
import '../../../state/app_state.dart';
import '../../../widgets/ui/api_key_field.dart';
import '../../../widgets/ui/app_button.dart';
import '../../../widgets/ui/app_switch.dart';
import '../../../widgets/ui/app_text_field.dart';
import 'mcp_settings_block.dart';
import 'settings_layout.dart';

/// Connectivity settings: global proxy accordion card + local MCP server card.
class ConnectivitySection extends StatefulWidget {
  const ConnectivitySection({
    super.key,
    this.isMobile = false,
    this.probeService = const ProxyProbeService(),
  });

  final bool isMobile;
  final ProxyProbeService probeService;

  @override
  State<ConnectivitySection> createState() => _ConnectivitySectionState();
}

class _ConnectivitySectionState extends State<ConnectivitySection> {
  bool _proxyEnabled = false;
  bool _probing = false;
  ProxyProbeResult? _probeResult;
  final TextEditingController _proxyUrlController = TextEditingController();
  final TextEditingController _proxyUsernameController = TextEditingController();
  final TextEditingController _proxyPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _proxyUrlController.dispose();
    _proxyUsernameController.dispose();
    _proxyPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final enabled = (await appState.getSetting('proxy_enabled')) == 'true';
    final url = await appState.getSetting('proxy_url') ?? '';
    final username = await appState.getSetting('proxy_username') ?? '';
    final password = await appState.getSetting('proxy_password') ?? '';
    if (!mounted) return;
    _proxyUrlController.text = url;
    _proxyUsernameController.text = username;
    _proxyPasswordController.text = password;
    setState(() => _proxyEnabled = enabled);
  }

  Future<void> _testProxy() async {
    if (_probing) return;
    setState(() {
      _probing = true;
      _probeResult = null;
    });
    final result = await widget.probeService.test(_proxyUrlController.text);
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probeResult = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;
    final appState = context.read<AppState>();

    final Widget proxyUrlField = SettingsFieldScope(
      child: AppTextField(
        key: const Key('proxy-url'),
        controller: _proxyUrlController,
        hint: '127.0.0.1:7890',
        keyboardType: TextInputType.url,
        style: textTheme.bodyMedium?.mono,
        onChanged: (value) {
          if (_probeResult != null) setState(() => _probeResult = null);
          appState.saveSetting('proxy_url', value);
        },
      ),
    );

    final Widget testButton = AppButton(
      key: const Key('proxy-test-button'),
      variant: AppButtonVariant.secondary,
      icon: Icons.wifi_tethering_rounded,
      label: _probing ? l10n.proxyTesting : l10n.proxyTestConnection,
      loading: _probing,
      fullWidth: widget.isMobile,
      onPressed: _probing ? null : _testProxy,
    );

    final Widget username = SettingsField(
      label: l10n.proxyUsername,
      child: AppTextField(
        key: const Key('proxy-username'),
        controller: _proxyUsernameController,
        onChanged: (v) => appState.saveSetting('proxy_username', v),
      ),
    );

    final Widget password = SettingsField(
      label: l10n.proxyPassword,
      child: ApiKeyField(
        key: const Key('proxy-password'),
        controller: _proxyPasswordController,
        onChanged: (v) => appState.saveSetting('proxy_password', v),
      ),
    );

    return SettingsSections(
      children: [
        SettingsBlock(
          caption: l10n.proxySettings,
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
                                    l10n.enableProxy,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  _ProxyStatusPill(
                                    label: _proxyEnabled
                                        ? l10n.proxyStatusEnabled
                                        : l10n.proxyStatusDisabled,
                                    active: _proxyEnabled,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.proxyAppliesToAll,
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
                          key: const Key('proxy-enabled-switch'),
                          value: _proxyEnabled,
                          onChanged: (value) {
                            setState(() {
                              _proxyEnabled = value;
                              if (!value) _probeResult = null;
                            });
                            appState.saveSetting('proxy_enabled', value.toString());
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                ClipRect(
                  child: AnimatedSize(
                    duration: AppMotion.sceneOf(context),
                    curve: AppMotion.enter,
                    alignment: Alignment.topCenter,
                    child: !_proxyEnabled
                        ? const SizedBox(width: double.infinity, height: 0)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.all(AppSpace.s16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      l10n.proxyUrl,
                                      style: textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w400,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpace.s4),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final stacked =
                                            widget.isMobile || constraints.maxWidth < 460;
                                        if (stacked) {
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              proxyUrlField,
                                              const SizedBox(height: AppSpace.s10),
                                              AppButton(
                                                key: const Key('proxy-test-button'),
                                                variant: AppButtonVariant.secondary,
                                                icon: Icons.wifi_tethering_rounded,
                                                label: _probing
                                                    ? l10n.proxyTesting
                                                    : l10n.proxyTestConnection,
                                                loading: _probing,
                                                fullWidth: true,
                                                onPressed: _probing ? null : _testProxy,
                                              ),
                                            ],
                                          );
                                        }
                                        return Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Expanded(child: proxyUrlField),
                                            const SizedBox(width: AppSpace.s10),
                                            testButton,
                                          ],
                                        );
                                      },
                                    ),
                                    if (_probeResult != null) ...[
                                      const SizedBox(height: AppSpace.s6),
                                      _ProxyProbeBanner(result: _probeResult!),
                                    ],
                                    const SizedBox(height: AppSpace.s16),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final stacked =
                                            widget.isMobile || constraints.maxWidth < 460;
                                        if (stacked) {
                                          return Column(
                                            crossAxisAlignment: CrossAxisAlignment.stretch,
                                            children: [
                                              username,
                                              const SizedBox(height: AppSpace.s10),
                                              password,
                                            ],
                                          );
                                        }
                                        return Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(child: username),
                                            const SizedBox(width: AppSpace.s10),
                                            Expanded(child: password),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        McpSettingsBlock(server: appState.mcpServer, isMobile: widget.isMobile),
      ],
    );
  }
}

class _ProxyStatusPill extends StatelessWidget {
  const _ProxyStatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? colorScheme.accentTint : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: active ? colorScheme.accentRing : colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 2),
        child: Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: active ? colorScheme.onAccentTint : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ProxyProbeBanner extends StatelessWidget {
  const _ProxyProbeBanner({required this.result});

  final ProxyProbeResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = context.semantic;
    final l10n = AppLocalizations.of(context)!;

    final bool ok = result.isReachable;
    final Color bg = ok ? semantic.successContainer : colorScheme.errorContainer;
    final Color fg = ok ? semantic.onSuccessContainer : colorScheme.onErrorContainer;
    final IconData icon = ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded;
    final String message = switch (result.status) {
      ProxyProbeStatus.reachable => l10n.proxyTestSuccess(result.latencyMs ?? 0),
      ProxyProbeStatus.invalidAddress => l10n.proxyTestInvalidAddress,
      ProxyProbeStatus.timedOut => l10n.proxyTestTimedOut,
      ProxyProbeStatus.refused => l10n.proxyTestRefused,
      ProxyProbeStatus.failed => l10n.proxyTestFailed,
    };

    return DecoratedBox(
      key: const Key('proxy-probe-result'),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s6),
        child: Row(
          children: [
            Icon(icon, size: AppSize.iconSm, color: fg),
            const SizedBox(width: AppSpace.s6),
            Expanded(
              child: Text(message, style: textTheme.bodySmall?.copyWith(color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}
