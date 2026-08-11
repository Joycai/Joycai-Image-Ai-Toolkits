import 'package:flutter/material.dart';

import '../../services/file_permission_service.dart';
import '../app_button.dart';

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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              customMessage ?? service.getPermissionInstructions(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            AppButton(
              label: service.getReAuthorizeButtonLabel(),
              icon: Icons.folder_open,
              onPressed: onReAuthorize,
            ),
          ],
        ),
      ),
    );
  }
}
