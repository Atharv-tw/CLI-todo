import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/voice.dart';

void main() {
  group('speech into a box the user is also editing', () {
    late SpokenDraft draft;
    late String box;

    /// What the box holds after the engine reports [said].
    String hear(String said) => box = draft.merge(box, said) ?? box;

    setUp(() {
      draft = SpokenDraft();
      box = '';
    });

    test('speech is added after what was already written', () {
      draft.begin(box = 'Woke at seven.');
      expect(hear('went for a'), 'Woke at seven. went for a');
      // The engine refines its last words; the spoken part is replaced, not repeated.
      expect(hear('went for a run'), 'Woke at seven. went for a run');
    });

    test('what the user deletes stays deleted when the mic is turned off', () {
      draft.begin(box);
      hear('I skipped the workout and felt bad about it');
      box = 'I skipped the workout'; // deleted by hand, mic still on
      // Turning the mic off makes the engine report the same words again.
      expect(draft.merge(box, 'I skipped the workout and felt bad about it'), isNull);
    });

    test('after an edit, only what is said from then on is added', () {
      draft.begin(box);
      hear('I skipped the workout and felt bad about it');
      box = 'I skipped the workout.';
      expect(hear('I skipped the workout and felt bad about it but did DSA'), 'I skipped the workout. but did DSA');
      expect(hear('I skipped the workout and felt bad about it but did DSA for an hour'),
          'I skipped the workout. but did DSA for an hour');
    });

    test('a word the engine was still finishing when the edit was made is not cut in half', () {
      draft.begin(box);
      hear('woke up la');
      box = 'Woke up';
      expect(hear('woke up late today'), 'Woke up late today');
    });

    test('typing before any speech arrives is kept', () {
      draft.begin(box = 'Idea:');
      box = 'Idea: flashcards';
      expect(hear('from lecture tabs'), 'Idea: flashcards from lecture tabs');
    });

    test('clearing the box and speaking again starts clean', () {
      draft.begin(box);
      hear('nothing worth keeping');
      box = '';
      expect(draft.merge(box, 'nothing worth keeping'), isNull);
      expect(hear('nothing worth keeping start over'), 'start over');
    });

    test('no space is added after a line break', () {
      draft.begin(box = 'First line\n');
      expect(hear('second line'), 'First line\nsecond line');
    });
  });

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
