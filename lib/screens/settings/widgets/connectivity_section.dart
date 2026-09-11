import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../widgets/api_key_field.dart';
import '../../../widgets/app_setting_row.dart';
import '../../../widgets/app_text_field.dart';
import 'settings_layout.dart';

/// `E1 · 1c` right: the proxy and the MCP server, each one column-coloured
/// group holding its switch and the fields under it. A field whose switch is
/// off stays exactly where it is, greyed onto the track colour, so turning
/// the switch on never moves the page.
class ConnectivitySection extends StatefulWidget {
  final bool isMobile;
  const ConnectivitySection({super.key, this.isMobile = false});

  @override
  State<ConnectivitySection> createState() => _ConnectivitySectionState();
}

class _ConnectivitySectionState extends State<ConnectivitySection> {
  final DatabaseService _db = DatabaseService();

  bool _proxyEnabled = false;
  final TextEditingController _proxyUrlController = TextEditingController();
  final TextEditingController _proxyUsernameController = TextEditingController();
  final TextEditingController _proxyPasswordController = TextEditingController();
  final TextEditingController _mcpPortController = TextEditingController();

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
    _mcpPortController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _proxyEnabled = (await _db.getSetting('proxy_enabled')) == 'true';
    _proxyUrlController.text = await _db.getSetting('proxy_url') ?? '';
    _proxyUsernameController.text = await _db.getSetting('proxy_username') ?? '';
    _proxyPasswordController.text = await _db.getSetting('proxy_password') ?? '';

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final Widget username = SettingsField(
      label: l10n.proxyUsername,
      enabled: _proxyEnabled,
      child: AppTextField(
        controller: _proxyUsernameController,
        enabled: _proxyEnabled,
        onChanged: (v) => _db.saveSetting('proxy_username', v),
      ),
    );
    final Widget password = SettingsField(
      label: l10n.proxyPassword,
      enabled: _proxyEnabled,
      child: ApiKeyField(
        controller: _proxyPasswordController,
        onChanged: (v) => _db.saveSetting('proxy_password', v),
      ),
    );

    return SettingsSections(
      children: [
        SettingsBlock(
          caption: l10n.proxySettings,
          child: SettingsGroup(
            ruled: false,
            children: [
              AppToggleRow(
                title: l10n.enableProxy,
                description: l10n.proxyAppliesToAll,
                value: _proxyEnabled,
                onChanged: (v) {
                  setState(() => _proxyEnabled = v);
                  _db.saveSetting('proxy_enabled', v.toString());
                },
              ),
              SettingsField(
                label: l10n.proxyUrl,
                enabled: _proxyEnabled,
                child: AppTextField(
                  controller: _proxyUrlController,
                  enabled: _proxyEnabled,
                  hint: '127.0.0.1:7890',
                  onChanged: (v) => _db.saveSetting('proxy_url', v),
                ),
              ),
              if (widget.isMobile) ...[
                username,
                password,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: username),
                    const SizedBox(width: 8),
                    Expanded(child: password),
                  ],
                ),
            ],
          ),
        ),
        SettingsBlock(
          caption: l10n.mcpServerSettings,
          child: SettingsGroup(
            ruled: false,
            children: [
              AppToggleRow(
                title: l10n.enableMcpServer,
                description: '${l10n.mcpServerDesc}\n${l10n.mcpComingSoon}',
                value: false,
                onChanged: null,
              ),
              // Held in place, disabled, for as long as the server is: the
              // switch above cannot be turned on in this version.
              SettingsField(
                label: l10n.port,
                enabled: false,
                child: AppTextField(controller: _mcpPortController, enabled: false),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
