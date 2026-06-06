import 'package:flutter_test/flutter_test.dart';
import 'package:csv/csv.dart';

void main() {
  test('test csv converter', () {
    expect(CsvDecoder, isNotNull);
  });
}
