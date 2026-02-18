import 'package:flutter/material.dart';

import '../../services/file_permission_service.dart';

class PermissionPlaceholder extends StatelessWidget {
  final VoidCallback onReAuthorize;
  final String? customMessage;

  const PermissionPlaceholder({
    super.key,
    required this.onReAuthorize,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final service = FilePermissionService();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_person_outlined,
              size: 64,
              color: colorScheme.error.withAlpha(150),
            ),
            const SizedBox(height: 16),
            Text(
              service.getPermissionErrorMessage(),
              style: TextStyle(
                color: colorScheme.error,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              customMessage ?? service.getPermissionInstructions(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onReAuthorize,
              icon: const Icon(Icons.folder_open),
              label: Text(service.getReAuthorizeButtonLabel()),
            ),
          ],
        ),
      ),
    );
  }
}
