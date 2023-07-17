///
/// When tracker get the error from server , it will send this exception to client
class TrackerException implements Exception {
  final dynamic failureReason;
  final String id;
  TrackerException(this.id, this.failureReason);

  @override
  String toString() {
    if (failureReason == null) {
      return 'TrackerException($id) - Unknown track error';
    }
    return 'TrackerException($id) - $failureReason';
  }
}
