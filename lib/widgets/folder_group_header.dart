import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/design_tokens.dart';

/// The row over one folder's run of files in a grouped grid or list
/// (`A1 · 1a`, `A1b · 1d/1e`): a folder glyph, the full path in mono, and
/// the count at the end.
///
/// Fixed height on purpose. The folder outline computes where each header
/// sits instead of measuring it, so a header that grew with its text would
/// put every jump after it off by that growth. [height] is the row itself;
/// a host that pads above it adds that padding to [FolderOutlineSpy.layout]'s
/// header extent.
class FolderGroupHeader extends StatelessWidget {
  const FolderGroupHeader({
    super.key,
    required this.path,
    required this.count,
    this.height = height28,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpace.s16),
  });

  final String path;
  final int count;

  /// The row's height: 28 over a grid, 32 as a row in the browser's list.
  final double height;
  final EdgeInsetsGeometry padding;

  static const double height28 = 28;
  static const double height32 = 32;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      height: height,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: AppSize.iconMd, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpace.s6),
            Expanded(
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall!.mono.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: AppSpace.s6),
            Text(
              '$count',
              style: textTheme.labelSmall!.mono.copyWith(
                color: scheme.outline,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
