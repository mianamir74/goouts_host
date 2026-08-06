import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Money is ALWAYS an integer number of pence.
//
// Never a double. A double produces a booking that costs £249.99999997, and it
// will happen on a real customer's screen before it happens in a test.
//
// WHY A CLASS AND NOT AN EXTENSION TYPE
// An extension type would be zero cost, but it needs the inline-class feature
// from Dart 3.3 and this app declares sdk >=3.0.0. Rather than raise the SDK
// floor of a shipping app for one convenience, this is a plain immutable
// class. Same API, same type safety, negligible cost for money display.
// ─────────────────────────────────────────────────────────────────────────────
class Pence {
  final int value;
  const Pence(this.value);

  static const Pence zero = Pence(0);

  /// Reads a Firestore field. Defends against a double or a string arriving
  /// from older data or a hand edit in the console.
  static Pence fromFirestore(Object? v) {
    if (v == null) return zero;
    if (v is int) return Pence(v);
    if (v is num) return Pence(v.round());
    if (v is String) return Pence(int.tryParse(v) ?? 0);
    return zero;
  }

  Pence operator +(Pence o) => Pence(value + o.value);
  Pence operator -(Pence o) => Pence(value - o.value);
  Pence times(int n) => Pence(value * n);

  bool get isZero => value == 0;

  /// "£112.00". Formatting happens ONLY at the edge, never in the model.
  String get formatted =>
      NumberFormat.currency(locale: 'en_GB', symbol: '£', decimalDigits: 2)
          .format(value / 100);

  /// "£112" when whole, "£112.50" otherwise. For prices in lists.
  String get compact => value % 100 == 0
      ? '£${value ~/ 100}'
      : NumberFormat.currency(
              locale: 'en_GB', symbol: '£', decimalDigits: 2)
          .format(value / 100);

  @override
  bool operator ==(Object other) => other is Pence && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Pence($value)';
}
