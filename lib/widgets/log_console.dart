import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

class LogConsoleWidget extends StatelessWidget {
  const LogConsoleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final ScrollController scrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    });

    return Container(
      height: 150,
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListView.builder(
        controller: scrollController,
        itemCount: appState.logs.length,
        itemBuilder: (context, index) {
          final log = appState.logs[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                children: [
                  TextSpan(text: '[${log.timestamp.toIso8601String().split('T').last.substring(0, 8)}] ', style: const TextStyle(color: Colors.grey)),
                  if (log.taskId != null)
                    TextSpan(text: '[${log.taskId!.substring(0, 8)}] ', style: const TextStyle(color: Colors.cyan)),
                  TextSpan(text: '[${log.level}] ', style: TextStyle(color: _getLevelColor(log.level), fontWeight: FontWeight.bold)),
                  TextSpan(text: log.message, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          );
        },
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
