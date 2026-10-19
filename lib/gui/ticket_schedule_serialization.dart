/// Serializes a calendar date as midnight in the app's Bangkok schedule zone.
///
/// Maintenance access ranges are stored at 00:00 Asia/Bangkok while PostgreSQL
/// runs in UTC. Sending a timezone-free local DateTime makes the server
/// interpret midnight as UTC and shifts a selected boundary by seven hours.
String bangkokDateBoundaryIso8601(DateTime date) {
  final utcMidnight = DateTime.utc(date.year, date.month, date.day);
  return utcMidnight.subtract(const Duration(hours: 7)).toIso8601String();
}
