import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/main.dart' as app_main;
import 'package:gesture_detector/temp/attendance_api_client.dart';
import 'package:gesture_detector/temp/attendance_app.dart';
import 'package:gesture_detector/temp/attendance_employee.dart';
import 'package:gesture_detector/temp/attendance_history_client.dart';
import 'package:gesture_detector/temp/attendance_profile.dart';
import 'package:gesture_detector/temp/attendance_profile_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('canonical app enables live punch submission', () {
    expect(app_main.enableLiveApi, isTrue);
  });

  testWidgets('first launch opens on three-person selection', (tester) async {
    await tester.pumpWidget(
      AttendanceApp(
        profileClient: _UnusedProfileClient(),
        apiClient: _UnusedApiClient(),
      ),
    );
    await _pumpUntilFound(tester, find.text('Select Employee'));

    expect(find.text('Select Employee'), findsOneWidget);
    expect(find.text('Mostakima Akter Mita'), findsOneWidget);
    expect(find.text('Tamanna'), findsOneWidget);
    expect(find.text('Mir Sultan'), findsOneWidget);
    final continueButton = tester.widget<FilledButton>(
      find.byKey(const Key('continueToAttendanceButton')),
    );
    expect(continueButton.onPressed, isNull);
  });

  testWidgets('successful first selection remembers the employee', (
    tester,
  ) async {
    final profileClient = _SuccessfulProfileClient();
    await tester.pumpWidget(
      AttendanceApp(
        profileClient: profileClient,
        apiClient: _UnusedApiClient(),
        historyClient: _EmptyHistoryClient(),
      ),
    );
    await _pumpUntilFound(tester, find.text('Select Employee'));

    await tester.tap(find.byKey(const Key('employeeSelector_2109058928')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('continueToAttendanceButton')));
    await _pumpUntilFound(tester, find.text('Today’s Attendance'));

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(rememberedAttendanceEmployeeKey),
      '2109058928',
    );
    expect(profileClient.requestedEmployees.single.apiEmployeeId, '2109058928');
  });

  testWidgets('saved employee skips selection on later launches', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      rememberedAttendanceEmployeeKey: '2109058928',
    });
    final profileClient = _SuccessfulProfileClient();

    await tester.pumpWidget(
      AttendanceApp(
        profileClient: profileClient,
        apiClient: _UnusedApiClient(),
        historyClient: _EmptyHistoryClient(),
      ),
    );
    await _pumpUntilFound(tester, find.text('Today’s Attendance'));

    expect(find.text('Select Employee'), findsNothing);
    expect(find.text('Mir Sultan'), findsOneWidget);
    expect(find.text('ID: TG0650'), findsOneWidget);
    expect(profileClient.requestedEmployees.single.apiEmployeeId, '2109058928');
  });

  testWidgets('invalid saved employee is cleared and selection is shown', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      rememberedAttendanceEmployeeKey: 'not-an-employee',
    });

    await tester.pumpWidget(
      AttendanceApp(
        profileClient: _UnusedProfileClient(),
        apiClient: _UnusedApiClient(),
      ),
    );
    await _pumpUntilFound(tester, find.text('Select Employee'));

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey(rememberedAttendanceEmployeeKey), isFalse);
    expect(find.text('Select Employee'), findsOneWidget);
  });

  testWidgets('failed automatic profile load returns to employee selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      rememberedAttendanceEmployeeKey: '2109058928',
    });

    await tester.pumpWidget(
      AttendanceApp(
        profileClient: _FailingProfileClient(),
        apiClient: _UnusedApiClient(),
      ),
    );
    await _pumpUntilFound(tester, find.byKey(const Key('profileLoadError')));

    expect(find.text('Select Employee'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Today’s Attendance'), findsNothing);
  });
}

class _UnusedProfileClient implements AttendanceProfileClient {
  @override
  Future<Uint8List> downloadImage(String imageFile) {
    throw UnimplementedError();
  }

  @override
  Future<AttendanceProfileMetadata> fetchProfile(AttendanceEmployee employee) {
    throw UnimplementedError();
  }
}

class _UnusedApiClient implements AttendanceApiClient {
  @override
  Future<AttendanceApiResult> submitPunch(AttendancePunchRequest request) {
    throw UnimplementedError();
  }
}

class _SuccessfulProfileClient implements AttendanceProfileClient {
  final List<AttendanceEmployee> requestedEmployees = <AttendanceEmployee>[];

  @override
  Future<Uint8List> downloadImage(String imageFile) async => _testPng;

  @override
  Future<AttendanceProfileMetadata> fetchProfile(
    AttendanceEmployee employee,
  ) async {
    requestedEmployees.add(employee);
    return const AttendanceProfileMetadata(
      displayName: 'Mir Sultan',
      companyId: 'TG0650',
      imageFile: 'e3_30_f3_44_74_03/profile.png',
    );
  }
}

class _FailingProfileClient implements AttendanceProfileClient {
  @override
  Future<Uint8List> downloadImage(String imageFile) {
    throw UnimplementedError();
  }

  @override
  Future<AttendanceProfileMetadata> fetchProfile(AttendanceEmployee employee) {
    throw const AttendanceProfileException('Profile server unavailable.');
  }
}

class _EmptyHistoryClient implements AttendanceHistoryClient {
  @override
  Future<AttendanceServerHistory> fetchToday({
    required String employeeId,
    required String macId,
    required DateTime date,
  }) async {
    return AttendanceServerHistory(
      employeeId: employeeId,
      macId: macId,
      date: date,
      checkInTimes: const <String>[],
    );
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 40,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for the expected widget.');
}

final Uint8List _testPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
