import 'package:app/core/arabic_numbers.dart';
import 'package:app/core/committed_days_controller.dart';
import 'package:app/core/prefs.dart';
import 'package:app/core/user_tag.dart';
import 'package:app/data/today_riyadh.dart';
import 'package:app/features/onboarding/onboarding_screen.dart';
import 'package:app/features/profile/widgets/badge_card.dart';
import 'package:app/features/profile/widgets/profile_header.dart';
import 'package:app/models/badge.dart' hide Badge;
import 'package:app/models/badge.dart' as model show badges;
import 'package:app/models/leaderboard_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Badges', () {
    test('are sorted in ascending requirement order', () {
      for (var i = 1; i < model.badges.length; i++) {
        expect(model.badges[i].requirement,
            greaterThan(model.badges[i - 1].requirement));
      }
    });

    test('badgeUnlockedAt fires when a tap crosses a requirement', () {
      expect(badgeUnlockedAt(9, 10)?.title, 'مبتدئ');
      expect(badgeUnlockedAt(99999, 100000)?.title, 'الشفاعة المرجوة');
      expect(badgeUnlockedAt(999999, 1000000)?.title, 'مليون صلاة');
      // No rung between 10 and 11 → nothing fires.
      expect(badgeUnlockedAt(10, 11), isNull);
      // Robust to a multi-rung jump (e.g. the lifetime migration): returns the
      // highest rung crossed, not null.
      expect(badgeUnlockedAt(0, 1000000)?.title, 'مليون صلاة');
    });

    test('nextBadgeFor moves through the ladder correctly', () {
      expect(nextBadgeFor(0).requirement, 10);
      expect(nextBadgeFor(50).requirement, 100);
      expect(nextBadgeFor(100000).requirement, 250000);
      expect(nextBadgeFor(1000000).requirement, 1000000); // capped at last
    });

    test('previousBadgeRequirement returns 0 below the first rung', () {
      expect(previousBadgeRequirement(0), 0);
      expect(previousBadgeRequirement(5), 0);
      expect(previousBadgeRequirement(10), 10);
      expect(previousBadgeRequirement(150), 100);
    });
  });

  group('Riyadh timezone (UTC+3)', () {
    test('date string rolls at Riyadh midnight, not UTC midnight', () {
      // 20:00 UTC = 23:00 Riyadh — still the same Riyadh day.
      expect(riyadhDateStringAt(DateTime.utc(2024, 1, 1, 20)), '2024-01-01');
      // 21:30 UTC = 00:30 Riyadh next day — already rolled over.
      expect(riyadhDateStringAt(DateTime.utc(2024, 1, 1, 21, 30)), '2024-01-02');
      // Month/year boundary.
      expect(riyadhDateStringAt(DateTime.utc(2024, 12, 31, 21)), '2025-01-01');
    });

    test('delay to next Riyadh midnight is correct', () {
      // 21:00 UTC == 00:00 Riyadh, so the next reset is exactly 24h away.
      expect(
        delayToNextRiyadhMidnightAt(DateTime.utc(2024, 1, 1, 21)),
        const Duration(hours: 24),
      );
      // One hour before reset.
      expect(
        delayToNextRiyadhMidnightAt(DateTime.utc(2024, 1, 1, 20)),
        const Duration(hours: 1),
      );
    });
  });

  group('Prefs migration', () {
    test('seeds lifetimeCount from a pre-migration localCount', () async {
      SharedPreferences.setMockInitialValues({'sallou_local_count': 4200});
      final prefs = await Prefs.load();
      expect(prefs.lifetimeCount, 4200);
    });

    test('does not clobber an existing lifetimeCount', () async {
      SharedPreferences.setMockInitialValues({
        'sallou_local_count': 50,
        'sallou_lifetime_count': 9000,
      });
      final prefs = await Prefs.load();
      expect(prefs.lifetimeCount, 9000);
    });
  });

  group('Committed days streak', () {
    /// Local calendar day [offset] days from today, formatted the way the
    /// controller stores it.
    String day(int offset) {
      final now = DateTime.now();
      final d = DateTime(now.year, now.month, now.day + offset);
      final mm = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      return '${d.year}-$mm-$dd';
    }

    Future<ProviderContainer> containerWith({
      int? streak,
      String? lastActive,
    }) async {
      SharedPreferences.setMockInitialValues({
        // Already migrated — otherwise Prefs.load() wipes the seeded run.
        'sallou_streak_reset_v1': true,
        if (streak != null) 'sallou_committed_days': streak,
        if (lastActive != null) 'sallou_last_active_utc_day': lastActive,
      });
      final prefs = await Prefs.load();
      return ProviderContainer(
        overrides: [prefsProvider.overrideWithValue(prefs)],
      );
    }

    test('is zero on a fresh install', () async {
      final c = await containerWith();
      expect(c.read(committedDaysProvider), 0);
    });

    test('shows the stored run when the user was active today', () async {
      final c = await containerWith(streak: 5, lastActive: day(0));
      expect(c.read(committedDaysProvider), 5);
    });

    test('survives a day with no tap yet — yesterday keeps the run alive',
        () async {
      final c = await containerWith(streak: 5, lastActive: day(-1));
      expect(c.read(committedDaysProvider), 5);
    });

    test('resets to zero once a full day is missed', () async {
      final c = await containerWith(streak: 5, lastActive: day(-2));
      expect(c.read(committedDaysProvider), 0);
      // ...and stays zero however long the user stays away.
      final c2 = await containerWith(streak: 5, lastActive: day(-30));
      expect(c2.read(committedDaysProvider), 0);
    });

    test('extends the run on the first tap of a new day', () async {
      final c = await containerWith(streak: 5, lastActive: day(-1));
      await c.read(committedDaysProvider.notifier).recordActive(day(0));
      expect(c.read(committedDaysProvider), 6);
    });

    test('starts a new run at 1 after a break', () async {
      final c = await containerWith(streak: 12, lastActive: day(-4));
      await c.read(committedDaysProvider.notifier).recordActive(day(0));
      expect(c.read(committedDaysProvider), 1);
    });

    test('counts a day once however many times it is tapped', () async {
      final c = await containerWith(streak: 3, lastActive: day(-1));
      final notifier = c.read(committedDaysProvider.notifier);
      await notifier.recordActive(day(0));
      await notifier.recordActive(day(0));
      await notifier.recordActive(day(0));
      expect(c.read(committedDaysProvider), 4);
    });

    test('credits background taps to the day they were sent on', () async {
      // Bubble-only user: tapped yesterday without opening the app, opens it
      // today. Yesterday earned its day, so today's tap can extend the run.
      final c = await containerWith(streak: 2, lastActive: day(-3));
      final notifier = c.read(committedDaysProvider.notifier);
      await notifier.recordActive(day(-1));
      expect(c.read(committedDaysProvider), 1);
      await notifier.recordActive(day(0));
      expect(c.read(committedDaysProvider), 2);
    });

    test('a late batch older than the last active day cannot rewrite the run',
        () async {
      final c = await containerWith(streak: 4, lastActive: day(0));
      await c.read(committedDaysProvider.notifier).recordActive(day(-2));
      expect(c.read(committedDaysProvider), 4);
    });

    group('migration off the old lifetime tally', () {
      test('drops the old count to zero', () async {
        SharedPreferences.setMockInitialValues({
          'sallou_committed_days': 40,
          'sallou_last_active_utc_day': day(0),
        });
        final prefs = await Prefs.load();
        expect(prefs.committedDays, 0);
        // The stamp goes too, so today can still start a run.
        expect(prefs.lastActiveUtcDay, isNull);
      });

      test("today's tap starts the new run at 1", () async {
        SharedPreferences.setMockInitialValues({
          'sallou_committed_days': 40,
          'sallou_last_active_utc_day': day(0),
        });
        final prefs = await Prefs.load();
        final c = ProviderContainer(
          overrides: [prefsProvider.overrideWithValue(prefs)],
        );
        expect(c.read(committedDaysProvider), 0);
        await c.read(committedDaysProvider.notifier).recordActive(day(0));
        expect(c.read(committedDaysProvider), 1);
      });

      test('runs once — a migrated run is never wiped again', () async {
        SharedPreferences.setMockInitialValues({'sallou_committed_days': 40});
        await Prefs.load();
        final prefs = await Prefs.load();
        await prefs.setCommittedDays(3);
        await prefs.setLastActiveUtcDay(day(0));
        expect((await Prefs.load()).committedDays, 3);
      });
    });
  });

  group('Quick-tap setup one-shot', () {
    test('defaults to not-yet-offered on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      expect(prefs.quickTapSetupDone, isFalse);
    });

    test('stays done once offered, so the permission is never re-asked',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await Prefs.load();
      await prefs.setQuickTapSetupDone(true);
      expect(prefs.quickTapSetupDone, isTrue);
      expect((await Prefs.load()).quickTapSetupDone, isTrue);
    });
  });

  group('Arabic numbers', () {
    test('formats with Arabic-Indic digits', () {
      // 0-9 use Eastern Arabic digits in the 'ar' locale.
      expect(formatArabic(0).contains('٠'), isTrue);
      expect(formatArabic(123).runes.length, 3);
    });
  });

  group('LeaderboardEntry', () {
    test('parses from Firestore data', () {
      final e = LeaderboardEntry.fromFirestore('uid1', {'name': 'Ahmed', 'count': 42});
      expect(e.uid, 'uid1');
      expect(e.name, 'Ahmed');
      expect(e.count, 42);
    });

    test('survives missing fields', () {
      final e = LeaderboardEntry.fromFirestore('uid2', {});
      expect(e.name, '');
      expect(e.count, 0);
    });
  });

  group('MyRank', () {
    test('isInTopList true for top 50', () {
      expect(const MyRank(uid: 'u', rank: 1, count: 9999, name: 'A').isInTopList, isTrue);
      expect(const MyRank(uid: 'u', rank: 50, count: 100, name: 'A').isInTopList, isTrue);
      expect(const MyRank(uid: 'u', rank: 51, count: 99, name: 'A').isInTopList, isFalse);
      expect(const MyRank(uid: 'u', rank: null, count: 0, name: 'A').isInTopList, isFalse);
    });
  });

  group('userTag', () {
    test('returns 4 Arabic-Indic digits', () {
      final tag = userTag('abc123');
      expect(tag.length, 4);
      const arabicIndic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
      for (final ch in tag.split('')) {
        expect(arabicIndic.contains(ch), isTrue, reason: 'unexpected char: $ch');
      }
    });

    test('is deterministic for the same uid', () {
      expect(userTag('some-uid-xyz'), userTag('some-uid-xyz'));
    });

    test('typically differs for different uids', () {
      // Not a guarantee (1/10000 collision rate by design), but should hold for
      // these specific strings.
      expect(userTag('uid-a'), isNot(equals(userTag('uid-b'))));
    });
  });

  group('OnboardingScreen', () {
    testWidgets('renders title, prompt, and submit button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const OnboardingScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('صلوا عليه'), findsOneWidget);
      expect(find.text('توكلنا على الله'), findsOneWidget);
    });
  });

  group('Profile widgets', () {
    testWidgets('ProfileHeader shows the user name and count', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: ProfileHeader(userName: 'أحمد', count: 1234),
        ),
      ));
      await tester.pump();

      expect(find.text('أحمد'), findsOneWidget);
      expect(find.textContaining('١'), findsWidgets); // Arabic-Indic digits
      expect(find.text('حصيلتك:'), findsOneWidget);
    });

    testWidgets('BadgeCard locked state renders progress bar', (tester) async {
      final firstBadge = model.badges.first;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: BadgeCard(badge: firstBadge, count: 5),
          ),
        ),
      ));
      await tester.pump();

      expect(find.text(firstBadge.title), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('BadgeCard unlocked state hides progress bar', (tester) async {
      final firstBadge = model.badges.first;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: BadgeCard(badge: firstBadge, count: firstBadge.requirement),
          ),
        ),
      ));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
