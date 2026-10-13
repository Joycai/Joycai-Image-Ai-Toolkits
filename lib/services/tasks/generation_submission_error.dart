class GenerationSubmissionError implements Exception {
  const GenerationSubmissionError(this.code, this.message, {this.field});
  final String code;
  final String message;
  final String? field;
  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (field != null) 'field': field,
  };
}
