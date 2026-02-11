import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/log_entry.dart';
import '../state/app_state.dart';

class LogConsoleWidget extends StatefulWidget {
  final bool showHeader;
  const LogConsoleWidget({super.key, this.showHeader = true});

  @override
  State<LogConsoleWidget> createState() => _LogConsoleWidgetState();
}

class _LogConsoleWidgetState extends State<LogConsoleWidget> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _autoScroll = true;
  String? _filterLevel;
  String _searchQuery = "";
  bool _isSearchExpanded = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final isAtBottom = _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 10;
    if (_autoScroll != isAtBottom) {
      setState(() => _autoScroll = isAtBottom);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && _autoScroll) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final colorScheme = Theme.of(context).colorScheme;

    // Apply filters
    final filteredLogs = appState.logs.where((log) {
      final matchesLevel = _filterLevel == null || log.level == _filterLevel;
      final matchesSearch = _searchQuery.isEmpty || 
          log.message.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (log.taskId?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      return matchesLevel && matchesSearch;
    }).toList();

    // Trigger scroll after build if auto-scroll is enabled
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Column(
      children: [
        if (widget.showHeader) _buildToolbar(context, appState, colorScheme),
        Expanded(
          child: Container(
            color: const Color(0xFF121212),
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: filteredLogs.length,
              itemBuilder: (context, index) {
                return _LogLine(log: filteredLogs[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context, AppState appState, ColorScheme colorScheme) {
    return Container(
      height: 40,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Search
          if (_isSearchExpanded)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Filter logs...',
                    hintStyle: TextStyle(color: Colors.white.withAlpha(100), fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close, size: 14, color: Colors.white),
                      onPressed: () {
                        setState(() {
                          _searchQuery = "";
                          _searchController.clear();
                          _isSearchExpanded = false;
                        });
                      },
                    ),
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.search, size: 18, color: Colors.white70),
              onPressed: () => setState(() => _isSearchExpanded = true),
              tooltip: 'Search logs',
            ),

          if (!_isSearchExpanded) ...[
            const Spacer(),
            
            // Level Filter
            _buildLevelChip('ERR', 'ERROR', Colors.redAccent),
            _buildLevelChip('RUN', 'RUNNING', Colors.blueAccent),
            _buildLevelChip('SUC', 'SUCCESS', Colors.greenAccent),
            
            const VerticalDivider(width: 16, indent: 8, endIndent: 8, color: Colors.white24),

            IconButton(
              icon: const Icon(Icons.copy_all, size: 18, color: Colors.white70),
              onPressed: () {
                final text = appState.logs.map((l) => '[${l.level}] ${l.message}').join('\n');
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs copied to clipboard'), duration: Duration(seconds: 1)));
              },
              tooltip: 'Copy all',
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.white70),
              onPressed: () => appState.clearLogs(),
              tooltip: 'Clear',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLevelChip(String label, String level, Color color) {
    final isSelected = _filterLevel == level;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ActionChip(
        label: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : color)),
        backgroundColor: isSelected ? color.withAlpha(100) : Colors.transparent,
        side: BorderSide(color: color.withAlpha(isSelected ? 255 : 100)),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: () {
          setState(() {
            _filterLevel = isSelected ? null : level;
          });
        },
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final LogEntry log;
  const _LogLine({required this.log});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.4),
          children: [
            TextSpan(
              text: '[${log.timestamp.toIso8601String().split('T').last.substring(0, 8)}] ', 
              style: const TextStyle(color: Colors.grey)
            ),
            if (log.taskId != null)
              TextSpan(
                text: '[${log.taskId!.length > 8 ? log.taskId!.substring(0, 8) : log.taskId}] ', 
                style: const TextStyle(color: Colors.cyan)
              ),
            TextSpan(
              text: '[${log.level}] ', 
              style: TextStyle(color: _getLevelColor(log.level), fontWeight: FontWeight.bold)
            ),
            TextSpan(
              text: log.message, 
              style: TextStyle(color: log.level == 'ERROR' ? Colors.red[100] : Colors.white70)
            ),
          ],
        ),
      ),
    );
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'ERROR': return Colors.redAccent;
      case 'RUNNING': return Colors.blueAccent;
      case 'SUCCESS': return Colors.greenAccent;
      default: return Colors.amberAccent;
    }
  }
}