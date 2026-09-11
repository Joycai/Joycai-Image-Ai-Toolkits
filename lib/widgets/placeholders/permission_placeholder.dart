import 'package:flutter/material.dart';

import '../../core/app_semantic_colors.dart';
import '../../core/design_tokens.dart';
import '../../services/file_permission_service.dart';

/// A folder the app can no longer read (`A1 · 1f` 权限不可达, `01 · 1e`
/// macOS sandbox).
///
/// A 44px amber plate with a lock, what went wrong, how to fix it, and the one
/// action that does — not an error: nothing failed, access has to be granted
/// again.
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
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final semantic = AppSemanticColors.of(context);
    final service = FilePermissionService();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: semantic.warningContainer,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Icon(Icons.lock_outline, size: 24, color: semantic.warning),
              ),
              const SizedBox(height: AppSpace.s10),
              Text(
                service.getPermissionErrorMessage(),
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpace.s4),
              Text(
                customMessage ?? service.getPermissionInstructions(),
                textAlign: TextAlign.center,
                style: textTheme.bodySmall!.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: AppType.proseHeight,
                ),
              ),
              const SizedBox(height: AppSpace.s10),
              FilledButton(
                onPressed: onReAuthorize,
                child: Text(service.getReAuthorizeButtonLabel()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
