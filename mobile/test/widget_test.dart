import 'package:app/core/arabic_numbers.dart';
import 'package:app/core/user_tag.dart';
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

void main() {
  group('Badges', () {
    test('are sorted in ascending requirement order', () {
      for (var i = 1; i < model.badges.length; i++) {
        expect(model.badges[i].requirement,
            greaterThan(model.badges[i - 1].requirement));
      }
    });

    test('badgeUnlockedAt returns the badge whose requirement equals count', () {
      expect(badgeUnlockedAt(10)?.title, 'مبتدئ');
      expect(badgeUnlockedAt(100000)?.title, 'الشفاعة المرجوة');
      expect(badgeUnlockedAt(11), isNull);
    });

    test('nextBadgeFor moves through the ladder correctly', () {
      expect(nextBadgeFor(0).requirement, 10);
      expect(nextBadgeFor(50).requirement, 100);
      expect(nextBadgeFor(100000).requirement, 100000); // capped at last
    });

    test('previousBadgeRequirement returns 0 below the first rung', () {
      expect(previousBadgeRequirement(0), 0);
      expect(previousBadgeRequirement(5), 0);
      expect(previousBadgeRequirement(10), 10);
      expect(previousBadgeRequirement(150), 100);
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
