class AppConfig {
  const AppConfig._();

  /// Minimum confidence (0.0 - 1.0) required to accept a prediction.
  /// If the model's top class confidence is below this, we treat it as
  /// "no known fabric detected" and block the output.
  static double minConfidenceToAccept = 0.6;
}
