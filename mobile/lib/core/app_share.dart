import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'arabic_numbers.dart';

/// Where the share sheet sends people. Kept in one place so the header
/// button, the profile card, and anything added later can't drift apart —
/// and so a future iOS/App Store link only needs one edit.
const appStoreUrl =
    'https://play.google.com/store/apps/details?id=com.salawat.app';

/// Invite text with no personal count in it — used by the "share the app"
/// entry point, where the pitch is the app itself, not the user's score.
String appInviteText() =>
    'صلوا عليه — عدّاد الصلاة على النبي ﷺ\n'
    'انضم إلينا وشاركنا الأجر في الهدف العالمي 🌟\n'
    '$appStoreUrl';

/// Invite text that leads with the user's lifetime count, then the link.
String appInviteTextWithCount(int count) =>
    'أنا وصلت لـ ${formatArabic(count)} صلاة على النبي ﷺ! '
    'شاركني الأجر وتحداني في لوحة الشرف 🌟\n'
    '$appStoreUrl';

/// Opens the system share sheet. [context] is only used to anchor the sheet
/// on iPad, where an unanchored popover throws.
Future<void> shareApp(BuildContext context, String text) async {
  final box = context.findRenderObject() as RenderBox?;
  await Share.share(
    text,
    subject: 'صلوا عليه',
    sharePositionOrigin:
        box != null ? box.localToGlobal(Offset.zero) & box.size : null,
  );
}
