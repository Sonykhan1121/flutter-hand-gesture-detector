import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/temp/attendance_api_client.dart';
import 'package:gesture_detector/temp/attendance_employee.dart';
import 'package:gesture_detector/temp/attendance_store.dart';
import 'package:gesture_detector/temp/attendance_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('historical attendance API contract', () {
    test('uses the selected employee and double-encoded check-in value', () {
      final request = AttendancePunchRequest(
        employeeId: '2109058928',
        macId: 'e3_30_f3_44_74_03',
        punchedAt: DateTime(2026, 7, 23, 9, 5),
      );

      expect(request.toJson(), <String, Object?>{
        'empId': '2109058928',
        'macId': 'e3_30_f3_44_74_03',
        'date': '2026-07-23',
        'checkIn': '["09:05"]',
        'checkOut': null,
        'lunchTimeCheckIn': null,
        'lunchTimeCheckOut': null,
        'status': 'synced',
      });
      expect(
        jsonEncode(request.toJson()),
        contains(r'"checkIn":"[\"09:05\"]"'),
      );
    });

    test('only HTTP 200 is considered successful', () {
      expect(const AttendanceApiResult(statusCode: 200).isSuccess, isTrue);
      expect(const AttendanceApiResult(statusCode: 201).isSuccess, isFalse);
      expect(const AttendanceApiResult(statusCode: null).isSuccess, isFalse);
    });
  });

  group('SharedPreferencesAttendanceStore', () {
    late SharedPreferencesAttendanceStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = SharedPreferencesAttendanceStore();
    });

    test('stores pending state and marks only that record synced', () async {
      final first = await store.savePendingPunch(
        employeeId: '2109058928',
        deviceMac: 'e3_30_f3_44_74_03',
        punchedAt: DateTime(2026, 7, 23, 9, 5),
      );
      final second = await store.savePendingPunch(
        employeeId: '2109058928',
        deviceMac: 'e3_30_f3_44_74_03',
        punchedAt: DateTime(2026, 7, 23, 13, 30),
      );

      await store.markPunchSynced(first);
      final punches = await store.loadPunches(
        employeeId: '2109058928',
        deviceMac: 'e3_30_f3_44_74_03',
        day: first.punchedAt,
      );

      expect(punches, hasLength(2));
      expect(punches.first.status, AttendancePunchStatus.synced);
      expect(punches.last.id, second.id);
      expect(punches.last.status, AttendancePunchStatus.pending);
      expect(
        (await store.loadAllPendingPunches()).map((punch) => punch.id),
        <String>[punches.last.id],
      );
    });

    test('keeps employee and date histories separate', () async {
      final mostakima = DateTime(2026, 7, 23, 8, 30);
      final tamanna = DateTime(2026, 7, 23, 9, 10);
      final nextDay = DateTime(2026, 7, 24, 8);

      await store.savePendingPunch(
        employeeId: '3531774223',
        deviceMac: '08_2c_6d_f4_f4_99',
        punchedAt: mostakima,
      );
      await store.savePendingPunch(
        employeeId: '3531774258',
        deviceMac: '08_2c_6d_f4_f4_99',
        punchedAt: tamanna,
      );
      await store.savePendingPunch(
        employeeId: '3531774223',
        deviceMac: '08_2c_6d_f4_f4_99',
        punchedAt: nextDay,
      );

      expect(
        await store.loadPunches(
          employeeId: '3531774223',
          deviceMac: '08_2c_6d_f4_f4_99',
          day: mostakima,
        ),
        hasLength(1),
      );
      expect(
        await store.loadPunches(
          employeeId: '3531774258',
          deviceMac: '08_2c_6d_f4_f4_99',
          day: mostakima,
        ),
        hasLength(1),
      );
      expect(
        await store.loadPunches(
          employeeId: '3531774223',
          deviceMac: '08_2c_6d_f4_f4_99',
          day: nextDay,
        ),
        hasLength(1),
      );
    });

    test('migrates timestamp-only values as synced without retrying', () async {
      final day = DateTime(2026, 7, 23, 8, 30);
      SharedPreferences.setMockInitialValues(<String, Object>{
        attendanceStorageKey('3531774223', day): <String>[
          day.toIso8601String(),
        ],
      });
      store = SharedPreferencesAttendanceStore();

      final punches = await store.loadPunches(
        employeeId: '3531774223',
        deviceMac: '08_2c_6d_f4_f4_99',
        day: day,
      );

      expect(punches, hasLength(1));
      expect(punches.single.status, AttendancePunchStatus.synced);
      expect(await store.loadAllPendingPunches(), isEmpty);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences
            .getStringList(attendanceStorageKey('3531774223', day))!
            .single,
        contains('"status":"synced"'),
      );
    });

    test(
      'server history replaces stale synced punches and preserves pending',
      () async {
        final day = DateTime(2026, 7, 23);
        final stale = await store.savePendingPunch(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          punchedAt: DateTime(2026, 7, 23, 7),
        );
        await store.markPunchSynced(stale);
        final matchingPending = await store.savePendingPunch(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          punchedAt: DateTime(2026, 7, 23, 8, 1, 45),
        );
        final unmatchedPending = await store.savePendingPunch(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          punchedAt: DateTime(2026, 7, 23, 9, 30),
        );

        final result = await store.reconcileServerPunches(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          day: day,
          checkInTimes: <String>['08:01', '08:01', '13:45'],
        );

        expect(result.punches, hasLength(4));
        expect(result.punches.where((punch) => punch.id == stale.id), isEmpty);
        expect(
          result.punches
              .singleWhere((punch) => punch.id == matchingPending.id)
              .status,
          AttendancePunchStatus.synced,
        );
        expect(result.newlySynced.map((punch) => punch.id), <String>[
          matchingPending.id,
        ]);
        expect(
          result.punches
              .singleWhere((punch) => punch.id == unmatchedPending.id)
              .status,
          AttendancePunchStatus.pending,
        );
        expect(
          result.punches
              .where(
                (punch) =>
                    punch.punchedAt.hour == 8 && punch.punchedAt.minute == 1,
              )
              .length,
          2,
        );
        expect(
          (await store.loadAllPendingPunches()).map((punch) => punch.id),
          <String>[unmatchedPending.id],
        );
      },
    );

    test(
      'matching prefers pending and server empty clears only synced',
      () async {
        final day = DateTime(2026, 7, 23);
        final synced = await store.savePendingPunch(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          punchedAt: DateTime(2026, 7, 23, 8, 1),
        );
        await store.markPunchSynced(synced);
        final pending = await store.savePendingPunch(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          punchedAt: DateTime(2026, 7, 23, 8, 1, 30),
        );

        var result = await store.reconcileServerPunches(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          day: day,
          checkInTimes: <String>['08:01'],
        );

        expect(result.punches, hasLength(1));
        expect(result.punches.single.id, pending.id);
        expect(result.punches.single.status, AttendancePunchStatus.synced);

        final laterPending = await store.savePendingPunch(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          punchedAt: DateTime(2026, 7, 23, 10),
        );
        result = await store.reconcileServerPunches(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          day: day,
          checkInTimes: const <String>[],
        );

        expect(result.punches, hasLength(1));
        expect(result.punches.single.id, laterPending.id);
        expect(result.punches.single.isPending, isTrue);
      },
    );

    test('reconciliation never changes another employee or date', () async {
      final otherEmployee = await store.savePendingPunch(
        employeeId: '3531774258',
        deviceMac: '08_2c_6d_f4_f4_99',
        punchedAt: DateTime(2026, 7, 23, 9),
      );
      final previousDay = await store.savePendingPunch(
        employeeId: '2109058928',
        deviceMac: 'e3_30_f3_44_74_03',
        punchedAt: DateTime(2026, 7, 22, 9),
      );

      await store.reconcileServerPunches(
        employeeId: '2109058928',
        deviceMac: 'e3_30_f3_44_74_03',
        day: DateTime(2026, 7, 23),
        checkInTimes: const <String>[],
      );

      expect(
        (await store.loadAllPendingPunches()).map((punch) => punch.id),
        containsAll(<String>[otherEmployee.id, previousDay.id]),
      );
    });

    test(
      'concurrent reconciliation and pending save cannot lose data',
      () async {
        final day = DateTime(2026, 7, 23);
        final reconciliation = store.reconcileServerPunches(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          day: day,
          checkInTimes: const <String>[],
        );
        final saved = store.savePendingPunch(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          punchedAt: DateTime(2026, 7, 23, 11),
        );

        await Future.wait<Object>(<Future<Object>>[reconciliation, saved]);
        final punches = await store.loadPunches(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          day: day,
        );

        expect(punches, hasLength(1));
        expect(punches.single.isPending, isTrue);
      },
    );
  });

  group('AttendanceSyncService', () {
    late SharedPreferencesAttendanceStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = SharedPreferencesAttendanceStore();
    });

    test(
      'record is pending before the API completes, then becomes synced',
      () async {
        final api = _CompletingApiClient();
        final service = AttendanceSyncService(store: store, apiClient: api);
        final employee = attendanceEmployees.last;
        final punchedAt = DateTime(2026, 7, 23, 9, 5);

        final submission = service.recordAndSubmit(
          employee: employee,
          punchedAt: punchedAt,
        );
        await api.started.future;
        final whileWaiting = await store.loadPunches(
          employeeId: employee.apiEmployeeId,
          deviceMac: employee.deviceMac,
          day: punchedAt,
        );
        expect(whileWaiting.single.status, AttendancePunchStatus.pending);

        api.complete(const AttendanceApiResult(statusCode: 200));
        final outcome = await submission;
        final afterSuccess = await store.loadPunches(
          employeeId: employee.apiEmployeeId,
          deviceMac: employee.deviceMac,
          day: punchedAt,
        );

        expect(outcome.isSynced, isTrue);
        expect(afterSuccess.single.status, AttendancePunchStatus.synced);
        expect(await store.loadAllPendingPunches(), isEmpty);
        await service.dispose();
      },
    );

    test('non-200 and thrown failures remain pending', () async {
      final api = _SequenceApiClient(<Object>[
        const AttendanceApiResult(statusCode: 503),
        StateError('offline'),
      ]);
      final service = AttendanceSyncService(store: store, apiClient: api);
      final employee = attendanceEmployees.last;

      final unavailable = await service.recordAndSubmit(
        employee: employee,
        punchedAt: DateTime(2026, 7, 23, 9),
      );
      final offline = await service.recordAndSubmit(
        employee: employee,
        punchedAt: DateTime(2026, 7, 23, 10),
      );

      expect(unavailable.isSynced, isFalse);
      expect(offline.isSynced, isFalse);
      expect(await store.loadAllPendingPunches(), hasLength(2));
      await service.dispose();
    });

    test(
      'startup sync is chronological and preserves original identity',
      () async {
        final latePunch = await store.savePendingPunch(
          employeeId: '3531774258',
          deviceMac: '08_2c_6d_f4_f4_99',
          punchedAt: DateTime(2026, 7, 23, 11),
        );
        final earlyPunch = await store.savePendingPunch(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          punchedAt: DateTime(2026, 7, 22, 8, 15),
        );
        final api = _SequenceApiClient(<Object>[
          const AttendanceApiResult(statusCode: 200),
          const AttendanceApiResult(statusCode: 500),
        ]);
        final service = AttendanceSyncService(store: store, apiClient: api);

        await service.syncAllPending();

        expect(api.requests.map((request) => request.employeeId), <String>[
          earlyPunch.employeeId,
          latePunch.employeeId,
        ]);
        expect(api.requests.first.macId, earlyPunch.deviceMac);
        expect(api.requests.first.punchedAt, earlyPunch.punchedAt);
        final remaining = await store.loadAllPendingPunches();
        expect(remaining.map((punch) => punch.id), <String>[latePunch.id]);
        await service.dispose();
      },
    );

    test(
      'simultaneous sync requests never submit one punch concurrently',
      () async {
        final punch = await store.savePendingPunch(
          employeeId: '2109058928',
          deviceMac: 'e3_30_f3_44_74_03',
          punchedAt: DateTime(2026, 7, 23, 9),
        );
        final api = _CompletingApiClient();
        final service = AttendanceSyncService(store: store, apiClient: api);

        final all = service.syncAllPending();
        await api.started.future;
        final selected = service.syncPendingForEmployee(punch.employeeId);
        await Future<void>.delayed(Duration.zero);
        expect(api.requests, hasLength(1));

        api.complete(const AttendanceApiResult(statusCode: 200));
        await Future.wait<void>(<Future<void>>[all, selected]);
        expect(api.requests, hasLength(1));
        await service.dispose();
      },
    );
  });
}

class _CompletingApiClient implements AttendanceApiClient {
  final Completer<void> started = Completer<void>();
  final Completer<AttendanceApiResult> _result =
      Completer<AttendanceApiResult>();
  final List<AttendancePunchRequest> requests = <AttendancePunchRequest>[];

  void complete(AttendanceApiResult result) => _result.complete(result);

  @override
  Future<AttendanceApiResult> submitPunch(AttendancePunchRequest request) {
    requests.add(request);
    if (!started.isCompleted) started.complete();
    return _result.future;
  }
}

class _SequenceApiClient implements AttendanceApiClient {
  _SequenceApiClient(this.results);

  final List<Object> results;
  final List<AttendancePunchRequest> requests = <AttendancePunchRequest>[];

  @override
  Future<AttendanceApiResult> submitPunch(
    AttendancePunchRequest request,
  ) async {
    requests.add(request);
    final result = results.removeAt(0);
    if (result is AttendanceApiResult) return result;
    throw result;
  }
}
