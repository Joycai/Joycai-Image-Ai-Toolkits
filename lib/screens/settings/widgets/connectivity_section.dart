import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../services/database_service.dart';
import '../../../widgets/api_key_field.dart';
import '../../../widgets/app_section.dart';

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
  
  bool _mcpEnabled = false;
  final TextEditingController _mcpPortController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _proxyEnabled = (await _db.getSetting('proxy_enabled')) == 'true';
    _proxyUrlController.text = await _db.getSetting('proxy_url') ?? '';
    _proxyUsernameController.text = await _db.getSetting('proxy_username') ?? '';
    _proxyPasswordController.text = await _db.getSetting('proxy_password') ?? '';

    _mcpEnabled = (await _db.getSetting('mcp_enabled')) == 'true';
    _mcpPortController.text = await _db.getSetting('mcp_port') ?? '3000';

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        AppSection(
          title: l10n.proxySettings,
          children: [
            SwitchListTile(
              title: Text(l10n.enableProxy),
              value: _proxyEnabled,
              onChanged: (v) {
                setState(() => _proxyEnabled = v);
                _db.saveSetting('proxy_enabled', v.toString());
              },
            ),
            if (_proxyEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _proxyUrlController,
                      decoration: InputDecoration(
                        labelText: l10n.proxyUrl,
                        hintText: '127.0.0.1:7890',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) => _db.saveSetting('proxy_url', v),
                    ),
                    const SizedBox(height: 16),
                    if (widget.isMobile) ...[
                      TextField(
                        controller: _proxyUsernameController,
                        decoration: InputDecoration(
                          labelText: l10n.proxyUsername,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) => _db.saveSetting('proxy_username', v),
                      ),
                      const SizedBox(height: 16),
                      ApiKeyField(
                        controller: _proxyPasswordController,
                        label: l10n.proxyPassword,
                        onChanged: (v) => _db.saveSetting('proxy_password', v),
                      ),
                    ] else
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _proxyUsernameController,
                              decoration: InputDecoration(
                                labelText: l10n.proxyUsername,
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (v) => _db.saveSetting('proxy_username', v),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ApiKeyField(
                              controller: _proxyPasswordController,
                              label: l10n.proxyPassword,
                              onChanged: (v) => _db.saveSetting('proxy_password', v),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        AppSection(
          title: l10n.mcpServerSettings,
          children: [
            SwitchListTile(
              title: Text(l10n.enableMcpServer),
              value: _mcpEnabled,
              onChanged: (v) {
                setState(() => _mcpEnabled = v);
                _db.saveSetting('mcp_enabled', v.toString());
              },
            ),
            if (_mcpEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _mcpPortController,
                  decoration: InputDecoration(
                    labelText: l10n.port,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _db.saveSetting('mcp_port', v),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
