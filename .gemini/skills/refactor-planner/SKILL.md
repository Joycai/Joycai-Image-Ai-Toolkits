---
name: refactor-planner
description: Analyzes the codebase to identify duplicate logic, complex methods, performance bottlenecks, and readability issues. Generates a structured refactoring plan to improve code quality, resource utilization, and adherence to standards.
---

# Refactor Planner

This skill guides the analysis of a codebase to produce a high-quality refactoring and improvement plan. It focuses on technical debt reduction and architectural health.

## Analysis Workflow

### 1. Identify Duplicate Logic & Bloat
- **Search for similar patterns**: Use `search_file_content` to find repeated strings, similar utility functions, or duplicated UI components.
- **Check for "God" classes**: Look for files with high line counts (e.g., >500 lines) using `run_shell_command("ls -l lib/**/*.dart")` or similar.
- **Common Service logic**: Check if multiple screens are implementing their own database or API logic instead of using a shared service.

### 2. Spot Complex & "Smelly" Code
- **Method Length**: Identify functions longer than 50-80 lines.
- **Deep Nesting**: Look for deeply nested `if/else` or `try/catch` blocks.
- **State management duplication**: Check if `notifyListeners()` is called excessively or if local `StatefulWidget` state could be moved to a central provider.

### 3. Performance & Resource Audit
- **Database Access**: Look for repetitive queries inside loops or missing indexes.
- **Stream/Timer management**: Ensure all `StreamSubscription` and `Timer` objects are properly cancelled in `dispose()`.
- **UI Rebuilds**: Identify large `build` methods that could be broken down into smaller `StatelessWidget`s to minimize rebuild impact.

### 4. Readability & Standards
- **Naming**: Ensure consistent camelCase for variables and PascalCase for classes.
- **Hardcoded values**: Identify magic numbers or strings that should be in `constants.dart` or `app_en.arb`.
- **Linting**: Run `flutter analyze` and identify patterns of ignored warnings.

## Output Format: The Refactoring Plan

When this skill is used, produce a report with the following sections:

1.  **Overview**: High-level summary of the codebase health.
2.  **Proposed Cleanups (Deduplication)**: Specific files and lines where logic can be merged.
3.  **Complex Method Refactoring**: List of specific methods to break down.
4.  **Performance & Resource Optimization**: Identified bottlenecks and proposed fixes (e.g., adding caching, fixing leaks).
5.  **Standardization**: Naming, localization, and linting improvements.
6.  **Implementation Priority**: Step-by-step roadmap (High/Medium/Low priority).

## Useful Search Commands
- Find large files: `powershell -Command "Get-ChildItem -Recurse lib/*.dart | Where-Object { $_.Length -gt 20kb }"`
- Find todos: `search_file_content("TODO")`
- Find potential leaks: `search_file_content("StreamSubscription")` then check for `cancel()` in the same file.