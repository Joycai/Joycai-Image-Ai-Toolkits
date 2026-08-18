import 'package:flutter/material.dart';

class Responsive {
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1000;

  // `sizeOf`, not `of`. `MediaQuery.of` subscribes the caller to the whole
  // MediaQueryData, so every widget asking which breakpoint it is in also
  // rebuilt when the keyboard opened, the text scale changed, or a system
  // inset moved — none of which can change the answer. `sizeOf` depends on
  // the size aspect alone.

  static bool isMobile(BuildContext context) =>
      MediaQuery.sizeOf(context).width < mobileBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= mobileBreakpoint &&
      MediaQuery.sizeOf(context).width < tabletBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= tabletBreakpoint;

  static bool isNarrow(BuildContext context) =>
      MediaQuery.sizeOf(context).width < tabletBreakpoint;

  /// Returns a value based on the current screen size.
  static T value<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    required T desktop,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < mobileBreakpoint) return mobile;
    if (width < tabletBreakpoint) return tablet ?? desktop;
    return desktop;
  }
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < Responsive.mobileBreakpoint) {
          return mobile;
        }
        if (constraints.maxWidth < Responsive.tabletBreakpoint) {
          return tablet ?? desktop;
        }
        return desktop;
      },
    );
  }
}
