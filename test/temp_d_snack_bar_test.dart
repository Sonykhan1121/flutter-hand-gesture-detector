import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/temp/constants/colors.dart';
import 'package:gesture_detector/temp/global_context.dart';
import 'package:gesture_detector/temp/utils/d_snack_bar.dart';
import 'package:iconsax/iconsax.dart';

void main() {
  testWidgets(
    'DSnackBar renders supplied success, information, and error styles',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: GlobalContext.navigatorKey,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );

      DSnackBar.successSnackBar(
        name: 'Mir Sultan',
        title: 'You punched successfully.',
      );
      await tester.pump();

      _expectSnackBar(
        tester,
        background: DColors.sSuccessBackground,
        stroke: DColors.sSuccessStroke,
        icon: Iconsax.check,
      );
      expect(find.text('Mir Sultan'), findsOneWidget);
      expect(find.text('You punched successfully.'), findsOneWidget);

      DSnackBar.errorSnackBar(title: 'This must wait.');
      await tester.pump();
      expect(find.text('This must wait.'), findsNothing);

      ScaffoldMessenger.of(
        GlobalContext.context!,
      ).hideCurrentSnackBar(reason: SnackBarClosedReason.hide);
      await tester.pumpAndSettle();
      await tester.pump();

      DSnackBar.informationSnackBar(title: 'Punch saved as pending.');
      await tester.pump();
      _expectSnackBar(
        tester,
        background: DColors.sInfoBackground,
        stroke: DColors.sInfoStroke,
        icon: Iconsax.warning_2,
      );

      ScaffoldMessenger.of(
        GlobalContext.context!,
      ).hideCurrentSnackBar(reason: SnackBarClosedReason.hide);
      await tester.pumpAndSettle();
      await tester.pump();

      DSnackBar.errorSnackBar(title: 'Server unavailable.');
      await tester.pump();
      _expectSnackBar(
        tester,
        background: DColors.sErrorBackground,
        stroke: DColors.sErrorStroke,
        icon: Icons.error,
      );
    },
  );
}

void _expectSnackBar(
  WidgetTester tester, {
  required Color background,
  required Color stroke,
  required IconData icon,
}) {
  final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
  final shape = snackBar.shape! as RoundedRectangleBorder;
  expect(snackBar.backgroundColor, background);
  expect(snackBar.behavior, SnackBarBehavior.floating);
  expect(snackBar.margin, const EdgeInsets.all(20));
  expect(shape.borderRadius, BorderRadius.circular(8));
  expect(shape.side.color, stroke);
  expect(find.byIcon(icon), findsOneWidget);
}
