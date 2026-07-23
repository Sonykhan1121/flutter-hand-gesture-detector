import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_api_client.dart';

enum AttendancePunchStatus { pending, synced }

class StoredAttendancePunch {
  const StoredAttendancePunch({
    required this.id,
    required this.employeeId,
    required this.deviceMac,
    required this.punchedAt,
    required this.status,
  });

  final String id;
  final String employeeId;
  final String deviceMac;
  final DateTime punchedAt;
  final AttendancePunchStatus status;

  bool get isPending => status == AttendancePunchStatus.pending;

  StoredAttendancePunch copyWith({AttendancePunchStatus? status}) {
    return StoredAttendancePunch(
      id: id,
      employeeId: employeeId,
      deviceMac: deviceMac,
      punchedAt: punchedAt,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'employeeId': employeeId,
      'deviceMac': deviceMac,
      'punchedAt': punchedAt.toIso8601String(),
      'status': status.name,
    };
  }

  static StoredAttendancePunch? tryFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id']?.toString() ?? '';
    final employeeId = value['employeeId']?.toString() ?? '';
    final deviceMac = value['deviceMac']?.toString() ?? '';
    final punchedAt = DateTime.tryParse(value['punchedAt']?.toString() ?? '');
    final status = switch (value['status']?.toString()) {
      'pending' => AttendancePunchStatus.pending,
      'synced' => AttendancePunchStatus.synced,
      _ => null,
    };
    if (id.isEmpty ||
        employeeId.isEmpty ||
        deviceMac.isEmpty ||
        punchedAt == null ||
        status == null) {
      return null;
    }
    return StoredAttendancePunch(
      id: id,
      employeeId: employeeId,
      deviceMac: deviceMac,
      punchedAt: punchedAt,
      status: status,
    );
  }
}

abstract interface class AttendanceStore {
  Future<List<StoredAttendancePunch>> loadPunches({
    required String employeeId,
    required String deviceMac,
    required DateTime day,
  });

  Future<StoredAttendancePunch> savePendingPunch({
    required String employeeId,
    required String deviceMac,
    required DateTime punchedAt,
  });

  Future<StoredAttendancePunch> markPunchSynced(StoredAttendancePunch punch);

  Future<AttendanceReconciliationResult> reconcileServerPunches({
    required String employeeId,
    required String deviceMac,
    required DateTime day,
    required List<String> checkInTimes,
  });

  Future<List<StoredAttendancePunch>> loadAllPendingPunches();
}

class AttendanceReconciliationResult {
  const AttendanceReconciliationResult({
    required this.punches,
    required this.newlySynced,
  });

  final List<StoredAttendancePunch> punches;
  final List<StoredAttendancePunch> newlySynced;
}

class SharedPreferencesAttendanceStore implements AttendanceStore {
  SharedPreferencesAttendanceStore({SharedPreferences? preferences})
    : _preferences = preferences;

  static const _storagePrefix = 'temp_attendance_';

  SharedPreferences? _preferences;
  int _idSerial = 0;
  Future<void> _mutationTail = Future<void>.value();

  Future<SharedPreferences> get _prefs async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  @override
  Future<List<StoredAttendancePunch>> loadPunches({
    required String employeeId,
    required String deviceMac,
    required DateTime day,
  }) {
    return _serialized(() async {
      final preferences = await _prefs;
      final key = attendanceStorageKey(employeeId, day);
      return _readDay(
        preferences: preferences,
        key: key,
        employeeId: employeeId,
        deviceMac: deviceMac,
        migrateLegacyValues: true,
      );
    });
  }

  @override
  Future<StoredAttendancePunch> savePendingPunch({
    required String employeeId,
    required String deviceMac,
    required DateTime punchedAt,
  }) {
    return _serialized(() async {
      final preferences = await _prefs;
      final key = attendanceStorageKey(employeeId, punchedAt);
      final punches = await _readDay(
        preferences: preferences,
        key: key,
        employeeId: employeeId,
        deviceMac: deviceMac,
        migrateLegacyValues: true,
      );
      final punch = StoredAttendancePunch(
        id: '$employeeId-${punchedAt.microsecondsSinceEpoch}-${_idSerial++}',
        employeeId: employeeId,
        deviceMac: deviceMac,
        punchedAt: punchedAt,
        status: AttendancePunchStatus.pending,
      );
      await _writeDay(preferences, key, <StoredAttendancePunch>[
        ...punches,
        punch,
      ]);
      return punch;
    });
  }

  @override
  Future<StoredAttendancePunch> markPunchSynced(StoredAttendancePunch punch) {
    return _serialized(() async {
      final preferences = await _prefs;
      final key = attendanceStorageKey(punch.employeeId, punch.punchedAt);
      final punches = await _readDay(
        preferences: preferences,
        key: key,
        employeeId: punch.employeeId,
        deviceMac: punch.deviceMac,
        migrateLegacyValues: true,
      );
      var found = false;
      final updated = punches
          .map((entry) {
            if (entry.id != punch.id) return entry;
            found = true;
            return entry.copyWith(status: AttendancePunchStatus.synced);
          })
          .toList(growable: false);
      if (!found) {
        throw StateError('Pending punch ${punch.id} no longer exists.');
      }
      await _writeDay(preferences, key, updated);
      return punch.copyWith(status: AttendancePunchStatus.synced);
    });
  }

  @override
  Future<AttendanceReconciliationResult> reconcileServerPunches({
    required String employeeId,
    required String deviceMac,
    required DateTime day,
    required List<String> checkInTimes,
  }) {
    return _serialized(() async {
      final preferences = await _prefs;
      final key = attendanceStorageKey(employeeId, day);
      final localPunches = await _readDay(
        preferences: preferences,
        key: key,
        employeeId: employeeId,
        deviceMac: deviceMac,
        migrateLegacyValues: true,
      );
      final unmatchedLocal = List<StoredAttendancePunch>.from(localPunches);
      final reconciled = <StoredAttendancePunch>[];
      final newlySynced = <StoredAttendancePunch>[];
      final serverOccurrences = <String, int>{};

      for (final time in checkInTimes) {
        final serverTime = _parseServerTime(day, time);
        final occurrence = serverOccurrences.update(
          time,
          (value) => value + 1,
          ifAbsent: () => 0,
        );
        final matchIndex = _preferredLocalMatchIndex(
          unmatchedLocal,
          serverTime,
        );
        if (matchIndex >= 0) {
          final match = unmatchedLocal.removeAt(matchIndex);
          final synced = match.copyWith(status: AttendancePunchStatus.synced);
          reconciled.add(synced);
          if (match.isPending) newlySynced.add(synced);
          continue;
        }

        reconciled.add(
          StoredAttendancePunch(
            id:
                'server-$employeeId-${attendanceDateKey(day)}-'
                '${time.replaceAll(':', '')}-$occurrence',
            employeeId: employeeId,
            deviceMac: deviceMac,
            punchedAt: serverTime,
            status: AttendancePunchStatus.synced,
          ),
        );
      }

      reconciled.addAll(unmatchedLocal.where((punch) => punch.isPending));
      reconciled.sort((a, b) => a.punchedAt.compareTo(b.punchedAt));
      await _writeDay(preferences, key, reconciled);
      return AttendanceReconciliationResult(
        punches: List<StoredAttendancePunch>.unmodifiable(reconciled),
        newlySynced: List<StoredAttendancePunch>.unmodifiable(newlySynced),
      );
    });
  }

  @override
  Future<List<StoredAttendancePunch>> loadAllPendingPunches() {
    return _serialized(() async {
      final preferences = await _prefs;
      final pending = <StoredAttendancePunch>[];
      final keys = preferences.getKeys().where(
        (key) => key.startsWith(_storagePrefix),
      );
      for (final key in keys) {
        final values = preferences.getStringList(key) ?? const <String>[];
        for (final encoded in values) {
          try {
            final punch = StoredAttendancePunch.tryFromJson(
              jsonDecode(encoded),
            );
            if (punch != null && punch.isPending) {
              pending.add(punch);
            }
          } on FormatException {
            // Legacy ISO timestamps are already-synced history, never pending.
          }
        }
      }
      pending.sort((a, b) => a.punchedAt.compareTo(b.punchedAt));
      return pending;
    });
  }

  Future<List<StoredAttendancePunch>> _readDay({
    required SharedPreferences preferences,
    required String key,
    required String employeeId,
    required String deviceMac,
    required bool migrateLegacyValues,
  }) async {
    final values = preferences.getStringList(key) ?? const <String>[];
    final punches = <StoredAttendancePunch>[];
    var migrated = false;
    for (var index = 0; index < values.length; index++) {
      final encoded = values[index];
      StoredAttendancePunch? punch;
      try {
        punch = StoredAttendancePunch.tryFromJson(jsonDecode(encoded));
      } on FormatException {
        final legacyTime = DateTime.tryParse(encoded);
        if (legacyTime != null) {
          punch = StoredAttendancePunch(
            id:
                'legacy-$employeeId-'
                '${legacyTime.microsecondsSinceEpoch}-$index',
            employeeId: employeeId,
            deviceMac: deviceMac,
            punchedAt: legacyTime,
            status: AttendancePunchStatus.synced,
          );
          migrated = true;
        }
      }
      if (punch != null) punches.add(punch);
    }
    punches.sort((a, b) => a.punchedAt.compareTo(b.punchedAt));
    if (migrated && migrateLegacyValues) {
      await _writeDay(preferences, key, punches);
    }
    return punches;
  }

  Future<void> _writeDay(
    SharedPreferences preferences,
    String key,
    Iterable<StoredAttendancePunch> punches,
  ) async {
    final sorted = punches.toList()
      ..sort((a, b) => a.punchedAt.compareTo(b.punchedAt));
    final saved = await preferences.setStringList(
      key,
      sorted.map((punch) => jsonEncode(punch.toJson())).toList(growable: false),
    );
    if (!saved) {
      throw StateError('The local attendance punch could not be saved.');
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

String attendanceStorageKey(String employeeId, DateTime day) {
  return 'temp_attendance_${employeeId}_${attendanceDateKey(day)}';
}

DateTime _parseServerTime(DateTime day, String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    throw FormatException('Invalid server punch time: $value');
  }
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null ||
      minute == null ||
      hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59) {
    throw FormatException('Invalid server punch time: $value');
  }
  return DateTime(day.year, day.month, day.day, hour, minute);
}

int _preferredLocalMatchIndex(
  List<StoredAttendancePunch> punches,
  DateTime serverTime,
) {
  int? syncedMatch;
  for (var index = 0; index < punches.length; index++) {
    final punch = punches[index];
    if (punch.punchedAt.year != serverTime.year ||
        punch.punchedAt.month != serverTime.month ||
        punch.punchedAt.day != serverTime.day ||
        punch.punchedAt.hour != serverTime.hour ||
        punch.punchedAt.minute != serverTime.minute) {
      continue;
    }
    if (punch.isPending) return index;
    syncedMatch ??= index;
  }
  return syncedMatch ?? -1;
}
