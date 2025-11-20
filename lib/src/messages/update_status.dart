/// Status of a transaction update
///
/// Indicates whether a reducer execution succeeded, failed, or ran out of energy.
sealed class UpdateStatus {}

/// Transaction committed successfully
class Committed extends UpdateStatus {
  @override
  String toString() => 'Committed()';
}

/// Transaction failed with an error
class Failed extends UpdateStatus {
  /// Error message describing why the transaction failed
  final String message;

  Failed(this.message);

  @override
  String toString() => 'Failed(message: $message)';
}

/// Transaction aborted due to insufficient energy budget
class OutOfEnergy extends UpdateStatus {
  /// Information about the energy budget that was exceeded
  final String budgetInfo;

  OutOfEnergy(this.budgetInfo);

  @override
  String toString() => 'OutOfEnergy(budgetInfo: $budgetInfo)';
}
