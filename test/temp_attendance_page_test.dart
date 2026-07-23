import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/temp/attendance_api_client.dart';
import 'package:gesture_detector/temp/attendance_employee.dart';
import 'package:gesture_detector/temp/attendance_history_client.dart';
import 'package:gesture_detector/temp/attendance_page.dart';
import 'package:gesture_detector/temp/attendance_profile.dart';
import 'package:gesture_detector/temp/attendance_profile_client.dart';
import 'package:gesture_detector/temp/attendance_store.dart';
import 'package:gesture_detector/temp/attendance_sync_service.dart';
import 'package:gesture_detector/temp/employee_selection_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final fixedNow = DateTime(2026, 7, 23, 9, 5, 7);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('opening screen lists three employees and requires selection', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.selectionApp(now: fixedNow));
    await tester.pump();

    expect(find.text('Mostakima Akter Mita'), findsOneWidget);
    expect(find.text('Tamanna'), findsOneWidget);
    expect(find.text('Mir Sultan'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('continueToAttendanceButton')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Mir selection loads server profile and opens attendance page', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final profileClient = _FakeProfileClient();
    final harness = _Harness(profileClient: profileClient);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.selectionApp(now: fixedNow));
    await tester.tap(find.byKey(const Key('employeeSelector_2109058928')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('continueToAttendanceButton')));
    await _pumpUntilFound(tester, find.text('Today’s Attendance'));

    expect(profileClient.profileEmployees.single.apiEmployeeId, '2109058928');
    expect(profileClient.imageFiles.single, 'e3_30_f3_44_74_03/profile.png');
    expect(find.byKey(const Key('selectedEmployeeName')), findsOneWidget);
    expect(find.text('ID: TG0650'), findsOneWidget);
    expect(find.byKey(const Key('attendanceProfilePhoto')), findsOneWidget);
    expect(find.byKey(const Key('workTypePanel')), findsOneWidget);
    expect(find.text('Face Attendance'), findsOneWidget);
    expect(find.text('Today’s Attendance'), findsOneWidget);
    expect(find.byKey(const Key('attendanceBackButton')), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(AttendancePage))).canPop(),
      isFalse,
    );
  });

  testWidgets('profile failure blocks navigation and Retry succeeds', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final profileClient = _FakeProfileClient(failuresRemaining: 1);
    final harness = _Harness(profileClient: profileClient);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.selectionApp(now: fixedNow));
    await tester.tap(find.byKey(const Key('employeeSelector_2109058928')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('continueToAttendanceButton')));
    await _pumpUntilFound(tester, find.byKey(const Key('profileLoadError')));

    expect(find.byKey(const Key('profileLoadError')), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Today’s Attendance'), findsNothing);

    await tester.tap(find.byKey(const Key('continueToAttendanceButton')));
    await _pumpUntilFound(tester, find.text('Today’s Attendance'));

    expect(profileClient.profileEmployees, hasLength(2));
    expect(find.text('Today’s Attendance'), findsOneWidget);
  });

  testWidgets('rapid Continue taps start one profile request', (tester) async {
    await _useTallTestSurface(tester);
    final profileClient = _ControlledProfileClient();
    final harness = _Harness(profileClient: profileClient);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.selectionApp(now: fixedNow));
    await tester.tap(find.byKey(const Key('employeeSelector_2109058928')));
    await tester.pump();
    final button = find.byKey(const Key('continueToAttendanceButton'));
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();

    expect(profileClient.fetchCalls, 1);
    profileClient.complete();
    await _pumpUntilFound(tester, find.text('Today’s Attendance'));
    expect(find.text('Today’s Attendance'), findsOneWidget);
  });

  testWidgets('attendance page preserves original layout and work-type radio', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.attendanceApp(now: fixedNow));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.white);
    expect(find.byKey(const Key('attendanceBackButton')), findsNothing);
    final panel = tester.widget<Container>(
      find.byKey(const Key('workTypePanel')),
    );
    final decoration = panel.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(10));
    expect(find.text('Select Work Type'), findsOneWidget);
    expect(find.text('Onsite'), findsOneWidget);
    expect(find.text('09:05:07 AM'), findsOneWidget);

    final onsiteChecked = find.descendant(
      of: find.byKey(const Key('onsiteWorkType')),
      matching: find.byIcon(Icons.radio_button_checked),
    );
    expect(onsiteChecked, findsOneWidget);
    await tester.tap(find.byKey(const Key('homeWorkType')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('homeWorkType')),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );
  });

  testWidgets('pending punch is gray and becomes blue after background sync', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final api = _ControlledPunchApiClient();
    final harness = _Harness(apiClient: api);
    addTearDown(harness.dispose);
    final pending = await harness.store.savePendingPunch(
      employeeId: attendanceEmployees.last.apiEmployeeId,
      deviceMac: attendanceEmployees.last.deviceMac,
      punchedAt: fixedNow,
    );

    await tester.pumpWidget(harness.attendanceApp(now: fixedNow));
    await tester.pump();
    final pendingText = tester.widget<Text>(
      find.byKey(Key('punchTime_${pending.id}')),
    );
    expect(pendingText.style?.color, attendancePending);

    final sync = harness.syncService.syncAllPending();
    await api.started.future;
    api.complete(const AttendanceApiResult(statusCode: 200));
    await sync;
    await tester.pump();
    await tester.pump();

    final syncedText = tester.widget<Text>(
      find.byKey(Key('punchTime_${pending.id}')),
    );
    expect(syncedText.style?.color, attendancePrimary);
  });

  testWidgets(
    'startup reconciles server history before retrying pending punches',
    (tester) async {
      await _useTallTestSurface(tester);
      final historyClient = _ControlledHistoryClient();
      final api = _RecordingPunchApiClient(
        const AttendanceApiResult(statusCode: 200),
      );
      final harness = _Harness(historyClient: historyClient, apiClient: api);
      addTearDown(harness.dispose);
      final employee = attendanceEmployees.last;
      final pending = await harness.store.savePendingPunch(
        employeeId: employee.apiEmployeeId,
        deviceMac: employee.deviceMac,
        punchedAt: DateTime(2026, 7, 23, 8, 1, 40),
      );

      await tester.pumpWidget(harness.attendanceApp(now: fixedNow));
      await historyClient.started.future;
      expect(api.requests, isEmpty);

      historyClient.complete(<String>['08:01']);
      await _pumpUntilFound(tester, find.byKey(Key('punchTime_${pending.id}')));
      await tester.pump();

      expect(api.requests, isEmpty);
      final syncedText = tester.widget<Text>(
        find.byKey(Key('punchTime_${pending.id}')),
      );
      expect(syncedText.style?.color, attendancePrimary);
      expect(historyClient.requests.single.employeeId, employee.apiEmployeeId);
      expect(historyClient.requests.single.macId, employee.deviceMac);
      expect(
        attendanceDateKey(historyClient.requests.single.date),
        '2026-07-23',
      );
    },
  );

  testWidgets('Refresh fetches authoritative server history again', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final historyClient = _SequenceHistoryClient(<Object>[
      <String>['08:01'],
      <String>['08:01', '09:10'],
    ]);
    final harness = _Harness(historyClient: historyClient);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.attendanceApp(now: fixedNow));
    await _pumpUntilFound(tester, find.text('08:01 AM'));
    await _pumpUntilButtonEnabled(
      tester,
      find.byKey(const Key('refreshAttendanceHistoryButton')),
    );

    await tester.tap(find.byKey(const Key('refreshAttendanceHistoryButton')));
    await _pumpUntilFound(tester, find.text('09:10 AM'));

    expect(historyClient.requests, hasLength(2));
    expect(
      historyClient.requests.every(
        (request) => request.employeeId == '2109058928',
      ),
      isTrue,
    );
  });

  testWidgets('failed history GET keeps local synced history unchanged', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final historyClient = _SequenceHistoryClient(<Object>[
      const AttendanceHistoryException('server unavailable'),
    ]);
    final harness = _Harness(historyClient: historyClient);
    addTearDown(harness.dispose);
    final employee = attendanceEmployees.last;
    final local = await harness.store.savePendingPunch(
      employeeId: employee.apiEmployeeId,
      deviceMac: employee.deviceMac,
      punchedAt: DateTime(2026, 7, 23, 8, 1),
    );
    await harness.store.markPunchSynced(local);

    await tester.pumpWidget(harness.attendanceApp(now: fixedNow));
    await _pumpUntilFound(tester, find.text('08:01 AM'));
    await _pumpUntilFound(
      tester,
      find.textContaining('Could not load server attendance'),
    );

    final punches = await harness.store.loadPunches(
      employeeId: employee.apiEmployeeId,
      deviceMac: employee.deviceMac,
      day: fixedNow,
    );
    expect(punches.single.id, local.id);
    expect(punches.single.status, AttendancePunchStatus.synced);
  });

  testWidgets('Refresh retries only the selected employee pending punches', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final historyClient = _SequenceHistoryClient(<Object>[
      const <String>[],
      const <String>[],
    ]);
    final api = _RecordingPunchApiClient(
      const AttendanceApiResult(statusCode: 503),
    );
    final harness = _Harness(historyClient: historyClient, apiClient: api);
    addTearDown(harness.dispose);
    final mir = attendanceEmployees.last;
    final tamanna = attendanceEmployees[1];
    await harness.store.savePendingPunch(
      employeeId: mir.apiEmployeeId,
      deviceMac: mir.deviceMac,
      punchedAt: DateTime(2026, 7, 23, 8),
    );
    await harness.store.savePendingPunch(
      employeeId: tamanna.apiEmployeeId,
      deviceMac: tamanna.deviceMac,
      punchedAt: DateTime(2026, 7, 23, 8, 30),
    );

    await tester.pumpWidget(harness.attendanceApp(now: fixedNow));
    await _pumpUntilButtonEnabled(
      tester,
      find.byKey(const Key('refreshAttendanceHistoryButton')),
    );
    expect(api.requests, hasLength(2));

    await tester.tap(find.byKey(const Key('refreshAttendanceHistoryButton')));
    await _pumpUntilCondition(tester, () => api.requests.length == 3);

    expect(api.requests.last.employeeId, mir.apiEmployeeId);
    expect(
      api.requests.where(
        (request) => request.employeeId == tamanna.apiEmployeeId,
      ),
      hasLength(1),
    );
  });

  testWidgets('date rollover fetches the new current day', (tester) async {
    await _useTallTestSurface(tester);
    var currentTime = DateTime(2026, 7, 23, 23, 59, 59);
    final historyClient = _SequenceHistoryClient(<Object>[
      const <String>[],
      <String>['00:01'],
    ]);
    final harness = _Harness(historyClient: historyClient);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.attendanceApp(now: currentTime, clock: () => currentTime),
    );
    await _pumpUntilButtonEnabled(
      tester,
      find.byKey(const Key('refreshAttendanceHistoryButton')),
    );
    currentTime = DateTime(2026, 7, 24, 0, 1);
    await tester.pump(const Duration(seconds: 1));
    await _pumpUntilFound(tester, find.text('12:01 AM'));

    expect(historyClient.requests, hasLength(2));
    expect(attendanceDateKey(historyClient.requests.last.date), '2026-07-24');
  });

  testWidgets('history displays newest punch first with original numbering', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final harness = _Harness();
    addTearDown(harness.dispose);
    final employee = attendanceEmployees.last;
    final first = await harness.store.savePendingPunch(
      employeeId: employee.apiEmployeeId,
      deviceMac: employee.deviceMac,
      punchedAt: DateTime(2026, 7, 23, 8, 10),
    );
    final second = await harness.store.savePendingPunch(
      employeeId: employee.apiEmployeeId,
      deviceMac: employee.deviceMac,
      punchedAt: DateTime(2026, 7, 23, 9, 20),
    );
    await harness.store.markPunchSynced(first);
    await harness.store.markPunchSynced(second);

    await tester.pumpWidget(harness.attendanceApp(now: fixedNow));
    await tester.pump();

    final history = find.byKey(const Key('attendancePunchHistory'));
    final texts = tester
        .widgetList<Text>(
          find.descendant(of: history, matching: find.byType(Text)),
        )
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(
      texts,
      containsAllInOrder(<String>[
        'Punch 2',
        '09:20 AM',
        'Punch 1',
        '08:10 AM',
      ]),
    );
  });

  testWidgets('failed verified punch is retained and shown pending', (
    tester,
  ) async {
    await _useTallTestSurface(tester);
    final harness = _Harness(
      apiClient: _ImmediatePunchApiClient(
        const AttendanceApiResult(statusCode: 503),
      ),
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.attendanceApp(now: fixedNow, faceVerifier: (_) async => true),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('faceAttendanceButton')));
    await tester.pump();
    await tester.pump();

    final pending = await harness.store.loadAllPendingPunches();
    expect(pending, hasLength(1));
    final text = tester.widget<Text>(
      find.byKey(Key('punchTime_${pending.single.id}')),
    );
    expect(text.style?.color, attendancePending);
    expect(find.textContaining('Punch saved as pending'), findsOneWidget);
  });

  testWidgets('cancelled verification never stores a punch', (tester) async {
    await _useTallTestSurface(tester);
    final harness = _Harness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.attendanceApp(now: fixedNow, faceVerifier: (_) async => false),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('faceAttendanceButton')));
    await tester.pump();

    expect(await harness.store.loadAllPendingPunches(), isEmpty);
  });
}

class _Harness {
  _Harness({
    AttendanceProfileClient? profileClient,
    AttendanceApiClient? apiClient,
    this.historyClient,
  }) : profileClient = profileClient ?? _FakeProfileClient(),
       apiClient =
           apiClient ??
           _ImmediatePunchApiClient(
             const AttendanceApiResult(statusCode: 200),
           ) {
    store = SharedPreferencesAttendanceStore();
    syncService = AttendanceSyncService(
      store: store,
      apiClient: this.apiClient,
    );
  }

  final AttendanceProfileClient profileClient;
  final AttendanceApiClient apiClient;
  final AttendanceHistoryClient? historyClient;
  late final SharedPreferencesAttendanceStore store;
  late final AttendanceSyncService syncService;

  Widget selectionApp({required DateTime now}) {
    return MaterialApp(
      home: EmployeeSelectionPage(
        profileClient: profileClient,
        historyClient: historyClient,
        store: store,
        syncService: syncService,
        clock: () => now,
        faceVerifier: (_) async => false,
      ),
    );
  }

  Widget attendanceApp({
    required DateTime now,
    Future<bool> Function(BuildContext)? faceVerifier,
    AttendanceClock? clock,
  }) {
    return MaterialApp(
      home: AttendancePage(
        employee: attendanceEmployees.last,
        profile: AttendanceProfile(
          displayName: 'Mir Sultan',
          companyId: 'TG0650',
          imageFile: 'e3_30_f3_44_74_03/profile.png',
          imageBytes: _testPng,
        ),
        store: store,
        syncService: syncService,
        historyClient: historyClient,
        clock: clock ?? () => now,
        faceVerifier: faceVerifier ?? (_) async => false,
      ),
    );
  }

  Future<void> dispose() => syncService.dispose();
}

class _FakeProfileClient implements AttendanceProfileClient {
  _FakeProfileClient({this.failuresRemaining = 0});

  int failuresRemaining;
  final List<AttendanceEmployee> profileEmployees = <AttendanceEmployee>[];
  final List<String> imageFiles = <String>[];

  @override
  Future<AttendanceProfileMetadata> fetchProfile(
    AttendanceEmployee employee,
  ) async {
    profileEmployees.add(employee);
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw const AttendanceProfileException('Profile server unavailable.');
    }
    return const AttendanceProfileMetadata(
      displayName: 'Mir Sultan',
      companyId: 'TG0650',
      imageFile: 'e3_30_f3_44_74_03/profile.png',
    );
  }

  @override
  Future<Uint8List> downloadImage(String imageFile) async {
    imageFiles.add(imageFile);
    return _testPng;
  }
}

class _ControlledProfileClient implements AttendanceProfileClient {
  final Completer<AttendanceProfileMetadata> _profile =
      Completer<AttendanceProfileMetadata>();
  int fetchCalls = 0;

  void complete() {
    _profile.complete(
      const AttendanceProfileMetadata(
        displayName: 'Mir Sultan',
        companyId: 'TG0650',
        imageFile: 'e3_30_f3_44_74_03/profile.png',
      ),
    );
  }

  @override
  Future<AttendanceProfileMetadata> fetchProfile(AttendanceEmployee employee) {
    fetchCalls++;
    return _profile.future;
  }

  @override
  Future<Uint8List> downloadImage(String imageFile) async => _testPng;
}

class _ImmediatePunchApiClient implements AttendanceApiClient {
  _ImmediatePunchApiClient(this.result);

  final AttendanceApiResult result;

  @override
  Future<AttendanceApiResult> submitPunch(
    AttendancePunchRequest request,
  ) async {
    return result;
  }
}

class _ControlledPunchApiClient implements AttendanceApiClient {
  final Completer<void> started = Completer<void>();
  final Completer<AttendanceApiResult> _result =
      Completer<AttendanceApiResult>();

  void complete(AttendanceApiResult result) => _result.complete(result);

  @override
  Future<AttendanceApiResult> submitPunch(AttendancePunchRequest request) {
    if (!started.isCompleted) started.complete();
    return _result.future;
  }
}

class _HistoryRequest {
  const _HistoryRequest({
    required this.employeeId,
    required this.macId,
    required this.date,
  });

  final String employeeId;
  final String macId;
  final DateTime date;
}

class _ControlledHistoryClient implements AttendanceHistoryClient {
  final Completer<void> started = Completer<void>();
  final Completer<List<String>> _times = Completer<List<String>>();
  final List<_HistoryRequest> requests = <_HistoryRequest>[];

  void complete(List<String> times) => _times.complete(times);

  @override
  Future<AttendanceServerHistory> fetchToday({
    required String employeeId,
    required String macId,
    required DateTime date,
  }) async {
    requests.add(
      _HistoryRequest(employeeId: employeeId, macId: macId, date: date),
    );
    if (!started.isCompleted) started.complete();
    final times = await _times.future;
    return AttendanceServerHistory(
      employeeId: employeeId,
      macId: macId,
      date: date,
      checkInTimes: times,
    );
  }
}

class _SequenceHistoryClient implements AttendanceHistoryClient {
  _SequenceHistoryClient(this.results);

  final List<Object> results;
  final List<_HistoryRequest> requests = <_HistoryRequest>[];

  @override
  Future<AttendanceServerHistory> fetchToday({
    required String employeeId,
    required String macId,
    required DateTime date,
  }) async {
    requests.add(
      _HistoryRequest(employeeId: employeeId, macId: macId, date: date),
    );
    final result = results.removeAt(0);
    if (result is List<String>) {
      return AttendanceServerHistory(
        employeeId: employeeId,
        macId: macId,
        date: date,
        checkInTimes: result,
      );
    }
    throw result;
  }
}

class _RecordingPunchApiClient implements AttendanceApiClient {
  _RecordingPunchApiClient(this.result);

  final AttendanceApiResult result;
  final List<AttendancePunchRequest> requests = <AttendancePunchRequest>[];

  @override
  Future<AttendanceApiResult> submitPunch(
    AttendancePunchRequest request,
  ) async {
    requests.add(request);
    return result;
  }
}

Future<void> _useTallTestSurface(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(tester.view.reset);
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

Future<void> _pumpUntilButtonEnabled(
  WidgetTester tester,
  Finder finder, {
  int attempts = 40,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    final button = tester.widget<OutlinedButton>(finder);
    if (button.onPressed != null) return;
  }
  fail('Timed out waiting for the expected button to become enabled.');
}

Future<void> _pumpUntilCondition(
  WidgetTester tester,
  bool Function() condition, {
  int attempts = 40,
}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) return;
  }
  fail('Timed out waiting for the expected condition.');
}

final Uint8List _testPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
  'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
