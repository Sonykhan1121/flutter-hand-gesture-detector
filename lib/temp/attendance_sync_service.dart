import 'dart:async';

import 'attendance_api_client.dart';
import 'attendance_employee.dart';
import 'attendance_store.dart';

class AttendanceSubmissionOutcome {
  const AttendanceSubmissionOutcome({
    required this.punch,
    required this.apiResult,
  });

  final StoredAttendancePunch punch;
  final AttendanceApiResult apiResult;

  bool get isSynced => punch.status == AttendancePunchStatus.synced;
}

class AttendanceSyncService {
  AttendanceSyncService({
    required this.store,
    required this.apiClient,
    this.enabled = true,
  });

  final AttendanceStore store;
  final AttendanceApiClient apiClient;
  final bool enabled;

  final StreamController<StoredAttendancePunch> _changes =
      StreamController<StoredAttendancePunch>.broadcast();
  final Map<String, Future<AttendanceSubmissionOutcome>> _activeSubmissions =
      <String, Future<AttendanceSubmissionOutcome>>{};
  Future<void>? _fullSync;
  bool _disposed = false;

  Stream<StoredAttendancePunch> get changes => _changes.stream;

  Future<AttendanceSubmissionOutcome> recordAndSubmit({
    required AttendanceEmployee employee,
    required DateTime punchedAt,
  }) async {
    final pending = await store.savePendingPunch(
      employeeId: employee.apiEmployeeId,
      deviceMac: employee.deviceMac,
      punchedAt: punchedAt,
    );
    _emit(pending);
    if (!enabled) {
      return AttendanceSubmissionOutcome(
        punch: pending,
        apiResult: const AttendanceApiResult(
          statusCode: null,
          errorMessage: 'Live punch submission is disabled.',
        ),
      );
    }
    return _submitOne(pending);
  }

  Future<void> syncAllPending() {
    if (!enabled) return Future<void>.value();
    final running = _fullSync;
    if (running != null) return running;

    late final Future<void> operation;
    operation = _loadAndSync().whenComplete(() {
      if (identical(_fullSync, operation)) {
        _fullSync = null;
      }
    });
    _fullSync = operation;
    return operation;
  }

  Future<void> syncPendingForEmployee(String employeeId) async {
    if (!enabled) return;
    final running = _fullSync;
    if (running != null) {
      await running;
    }
    await _loadAndSync(employeeId: employeeId);
  }

  Future<AttendanceReconciliationResult> reconcileServerHistory({
    required AttendanceEmployee employee,
    required DateTime day,
    required List<String> checkInTimes,
  }) async {
    final result = await store.reconcileServerPunches(
      employeeId: employee.apiEmployeeId,
      deviceMac: employee.deviceMac,
      day: day,
      checkInTimes: checkInTimes,
    );
    for (final punch in result.newlySynced) {
      _emit(punch);
    }
    return result;
  }

  Future<void> _loadAndSync({String? employeeId}) async {
    final pending = await store.loadAllPendingPunches();
    final selected = employeeId == null
        ? pending
        : pending
              .where((punch) => punch.employeeId == employeeId)
              .toList(growable: false);
    for (final punch in selected) {
      await _submitOne(punch);
    }
  }

  Future<AttendanceSubmissionOutcome> _submitOne(StoredAttendancePunch punch) {
    final active = _activeSubmissions[punch.id];
    if (active != null) return active;

    late final Future<AttendanceSubmissionOutcome> operation;
    operation = _performSubmission(punch).whenComplete(() {
      if (identical(_activeSubmissions[punch.id], operation)) {
        _activeSubmissions.remove(punch.id);
      }
    });
    _activeSubmissions[punch.id] = operation;
    return operation;
  }

  Future<AttendanceSubmissionOutcome> _performSubmission(
    StoredAttendancePunch punch,
  ) async {
    AttendanceApiResult result;
    try {
      result = await apiClient.submitPunch(
        AttendancePunchRequest(
          employeeId: punch.employeeId,
          macId: punch.deviceMac,
          punchedAt: punch.punchedAt,
        ),
      );
    } catch (error) {
      result = AttendanceApiResult(
        statusCode: null,
        errorMessage: 'Attendance request failed: $error',
      );
    }

    if (!result.isSuccess) {
      return AttendanceSubmissionOutcome(punch: punch, apiResult: result);
    }

    try {
      final synced = await store.markPunchSynced(punch);
      _emit(synced);
      return AttendanceSubmissionOutcome(punch: synced, apiResult: result);
    } catch (error) {
      return AttendanceSubmissionOutcome(
        punch: punch,
        apiResult: AttendanceApiResult(
          statusCode: null,
          responseBody: result.responseBody,
          errorMessage:
              'The server accepted the punch, but local sync status could '
              'not be updated: $error',
        ),
      );
    }
  }

  void _emit(StoredAttendancePunch punch) {
    if (!_disposed) _changes.add(punch);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
  }
}
