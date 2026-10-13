import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/voice.dart';

void main() {
  test('pieces of a round join without doubling', () {
    // Google settles a piece, then reports the next from scratch.
    expect(SystemDictation.joinForTest('I woke up late', 'and skipped the workout'), 'I woke up late and skipped the workout');
    // Other recognisers repeat the whole round every time.
    expect(SystemDictation.joinForTest('I woke up', 'I woke up late today'), 'I woke up late today');
    // A final result that only restates the last piece adds nothing.
    expect(SystemDictation.joinForTest('I woke up late. Skipped the workout', 'skipped the workout.'), 'I woke up late. Skipped the workout');
    expect(SystemDictation.joinForTest('', 'hello'), 'hello');
    expect(SystemDictation.joinForTest('hello', ''), 'hello');
  });
}
