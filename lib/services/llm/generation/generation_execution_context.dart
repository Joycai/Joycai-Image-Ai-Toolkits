import '../llm_types.dart';

/// Runtime-only controls. Never part of GenerationRequest or task JSON.
class GenerationExecutionContext {
  const GenerationExecutionContext({this.isCancelled, this.abortTrigger});
  final bool Function()? isCancelled;
  final Future<void>? abortTrigger;

  Map<String, dynamic> get legacyOptions => {
    if (isCancelled != null) llmCancellationProbeKey: isCancelled,
    if (abortTrigger != null) llmAbortTriggerKey: abortTrigger,
  };
}
