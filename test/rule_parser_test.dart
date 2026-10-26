import 'package:maya/brain/action.dart';
import 'package:maya/brain/rule_parser.dart';
import 'package:maya/services/apps.dart';
import 'package:maya/services/contacts.dart';
import 'package:maya/services/lists.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = RuleParser();
  final now = DateTime(2026, 10, 26, 10, 0);
  AssistantAction p(String s) => parser.parse(s, now: now);

  group('genius', () {
    test('several commands in one sentence', () {
      final a = p('set an alarm for 6 am and remind me to call Maa in 10 minutes');
      expect(a.type, ActionType.multi);
      expect(a.steps.length, 2);
      expect(a.steps[0].type, ActionType.alarm);
      expect(a.steps[1].type, ActionType.reminder);
    });
    test('"and" inside one command is not split', () {
      expect(p('what is the difference between rice and wheat').type, ActionType.answer);
    });
    test('remember and forget', () {
      final a = p('remember that my bike is parked on level B2');
      expect(a.type, ActionType.remember);
      expect(a.message, 'my bike is parked on level b2');
      expect(p('মনে রেখো গাড়ির চাবি আলমারিতে').type, ActionType.remember);
      expect(p('forget about the bike').type, ActionType.forget);
      expect(p('remember to call Maa at 6 pm').type, isNot(ActionType.remember));
    });
    test('repeating reminder', () {
      final a = p('remind me every day at 8 am to take medicine');
      expect(a.type, ActionType.reminder);
      expect(a.repeat, 'daily');
      expect(a.when?.hour, 8);
    });
    test('phone controls', () {
      expect(p('turn on the torch').setting, 'torch_on');
      expect(p('টর্চ বন্ধ করো').setting, 'torch_off');
      expect(p('volume up').setting, 'volume_up');
      expect(p('आवाज़ कम करो').setting, 'volume_down');
      expect(p('how much battery is left').setting, 'battery');
    });
    test('lists', () {
      final a = p('add milk, eggs and bread to my shopping list');
      expect(a.type, ActionType.list);
      expect(a.setting, 'add');
      expect(a.message, 'milk, eggs and bread');
      expect(p("what's on my shopping list").setting, 'read');
      expect(p('বাজারের লিস্টে ডিম আর দুধ যোগ করো').setting, 'add');
      expect(p('clear my shopping list').setting, 'clear');
    });
    test('messages', () {
      expect(p('read my messages').type, ActionType.readMessages);
      expect(p('মেসেজ পড়ো').type, ActionType.readMessages);
      final r = p('reply I am coming in 10 minutes');
      expect(r.type, ActionType.replyMessage);
      expect(r.message, 'i am coming in 10 minutes');
    });
  });

  group('calls', () {
    test('Bengali with the call word first', () {
      final a = p('কল কাজী নাসার');
      expect(a.type, ActionType.call);
      expect(a.contact, 'কাজী নাসার');
      expect(p('ফোন করো মাকে').contact, 'মা');
    });
    test('Hindi with the call word first', () {
      final a = p('कॉल राहुल');
      expect(a.type, ActionType.call);
      expect(a.contact, 'राहुल');
    });
    test('open WhatsApp only opens the app', () {
      expect(p('open WhatsApp').type, ActionType.openApp);
      expect(p('হোয়াটসঅ্যাপ খোলো').type, ActionType.openApp);
      expect(p('WhatsApp Rahul: I am late').type, ActionType.whatsapp);
    });
    test('English', () {
      final a = p('Call Rahul');
      expect(a.type, ActionType.call);
      expect(a.contact, 'rahul');
    });
    test('Bengali', () {
      final a = p('মা কে ফোন করো');
      expect(a.type, ActionType.call);
      expect(a.contact, 'মা');
    });
    test('Hindi', () {
      final a = p('माँ को फोन करो');
      expect(a.type, ActionType.call);
      expect(a.contact, 'माँ');
    });
  });

  group('timers', () {
    test('English', () {
      final a = p('10 minute timer');
      expect(a.type, ActionType.timer);
      expect(a.seconds, 600);
    });
    test('Bengali digits', () {
      final a = p('টাইমার ৫ মিনিট');
      expect(a.type, ActionType.timer);
      expect(a.seconds, 300);
    });
    test('Hindi', () {
      final a = p('10 मिनट का टाइमर');
      expect(a.type, ActionType.timer);
      expect(a.seconds, 600);
    });
  });

  group('alarms', () {
    test('English am', () {
      final a = p('Set an alarm for 6 am');
      expect(a.type, ActionType.alarm);
      expect((a.hour, a.minute), (6, 0));
    });
    test('English pm with minutes', () {
      final a = p('alarm at 7:30 pm');
      expect(a.type, ActionType.alarm);
      expect((a.hour, a.minute), (19, 30));
    });
    test('Bengali', () {
      final a = p('সকাল ৬টায় অ্যালার্ম দাও');
      expect(a.type, ActionType.alarm);
      expect((a.hour, a.minute), (6, 0));
    });
    test('Hindi', () {
      final a = p('सुबह 6 बजे का अलार्म लगाओ');
      expect(a.type, ActionType.alarm);
      expect((a.hour, a.minute), (6, 0));
    });
  });

  group('reminders', () {
    test('relative time', () {
      final a = p('remind me to pay bill in 10 minutes');
      expect(a.type, ActionType.reminder);
      expect(a.when, now.add(const Duration(minutes: 10)));
      expect(a.message, 'pay bill');
    });
    test('clock time ignores amounts', () {
      final a = p('remind me to pay 500 rupees at 6 pm');
      expect(a.type, ActionType.reminder);
      expect(a.when, DateTime(2026, 10, 26, 18, 0));
      expect(a.message, 'pay 500 rupees');
    });
  });

  group('apps, places and more', () {
    test('open app English', () {
      final a = p('open youtube');
      expect(a.type, ActionType.openApp);
      expect(a.app, 'youtube');
    });
    test('open app Bengali', () {
      final a = p('ইউটিউব খোলো');
      expect(a.type, ActionType.openApp);
      expect(a.app, 'ইউটিউব');
    });
    test('briefing', () => expect(p('Good morning').type, ActionType.briefing));
    test('weather', () {
      final a = p("How's the weather today?");
      expect(a.type, ActionType.weather);
      expect(a.place, isNull);
    });
    test('whatsapp with message', () {
      final a = p('WhatsApp Rahul: I will be late');
      expect(a.type, ActionType.whatsapp);
      expect(a.contact, 'rahul');
      expect(a.message, 'i will be late');
    });
    test('navigate', () {
      final a = p('navigate to berhampore station');
      expect(a.type, ActionType.navigate);
      expect(a.place, 'berhampore station');
    });
    test('ignores the wake word', () {
      final a = p('Hey Maya, call Rahul');
      expect(a.type, ActionType.call);
      expect(a.contact, 'rahul');
      expect(p('মায়া ১০ মিনিটের টাইমার').seconds, 600);
    });
    test('unknown becomes answer', () => expect(p('what is the capital of france').type, ActionType.answer));
  });

  group('helpers', () {
    test('normalize digits and dotted letters', () {
      expect(RuleParser.normalize('৬টায়'), '6টায়');
      expect(RuleParser.normalize('६ बजे'), '6 बजे');
    });
    test('app packages', () {
      expect(packageForApp('YouTube'), 'com.google.android.youtube');
      expect(packageForApp('phone pe'), 'com.phonepe.app');
      expect(packageForApp('ইউটিউব'), 'com.google.android.youtube');
      expect(packageForApp('some random thing'), isNull);
    });
    test('list names and items', () {
      expect(Lists.nameFor('বাজারের'), 'shopping');
      expect(Lists.nameFor('shopping'), 'shopping');
      expect(Lists.splitItems('milk, eggs and bread'), ['milk', 'eggs', 'bread']);
      expect(Lists.splitItems('ডিম আর দুধ'), ['ডিম', 'দুধ']);
    });
    test('names that sound alike', () {
      expect(ContactFinder.soundsLike('noushad', 'naushad ali'), greaterThan(0));
      expect(ContactFinder.soundsLike('nowshad', 'naushad'), greaterThan(0));
      expect(ContactFinder.soundsLike('নওশাদ', 'naushad'), greaterThan(0));
      expect(ContactFinder.soundsLike('rahul', 'naushad'), 0);
    });
    test('WhatsApp numbers', () {
      expect(ContactFinder.forWhatsApp('+91 98765-43210'), '919876543210');
      expect(ContactFinder.forWhatsApp('098765 43210'), '919876543210');
    });
    test('AI JSON is read safely', () {
      final a = AssistantAction.fromJson({'action': 'alarm', 'hour': '18', 'minute': 0, 'reply': 'Done'});
      expect(a.type, ActionType.alarm);
      expect(a.hour, 18);
      expect(a.reply, 'Done');
      expect(AssistantAction.fromJson({'action': 'fly'}).type, ActionType.answer);
    });
  });
}
