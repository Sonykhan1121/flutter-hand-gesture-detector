import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_api_client.dart';
import 'attendance_employee.dart';
import 'attendance_history_client.dart';
import 'attendance_page.dart';
import 'attendance_profile_client.dart';
import 'attendance_store.dart';
import 'attendance_sync_service.dart';
import 'employee_selection_page.dart';
import 'global_context.dart';

const attendancePunchApiUrl =
    'https://grozziie.zjweiting.com:3091/'
    'grozziie-attendance-debug/attendance/punch-update';
const attendanceProfileApiUrl =
    'https://grozziie.zjweiting.com:3091/'
    'grozziie-attendance-debug/employee/by/mac-employeId';
const attendanceImageApiUrl =
    'https://grozziie.zjweiting.com:3091/'
    'grozziie-attendance-debug/api/files/download/device-wise/image';
const attendanceHistoryApiUrl =
    'https://grozziie.zjweiting.com:3091/'
    'grozziie-attendance-debug/attendance/emp';
const rememberedAttendanceEmployeeKey = 'attendance_selected_employee_id';

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({
    super.key,
    this.enableLiveApi = true,
    this.store,
    this.apiClient,
    this.profileClient,
    this.historyClient,
    this.syncService,
    this.faceVerifier,
    this.clock,
  });

  final bool enableLiveApi;
  final AttendanceStore? store;
  final AttendanceApiClient? apiClient;
  final AttendanceProfileClient? profileClient;
  final AttendanceHistoryClient? historyClient;
  final AttendanceSyncService? syncService;
  final AttendanceFaceVerifier? faceVerifier;
  final AttendanceClock? clock;

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  late final AttendanceStore _store;
  late final AttendanceSyncService _syncService;
  late final AttendanceProfileClient _profileClient;
  late final AttendanceHistoryClient? _historyClient;
  late final bool _ownsSyncService;
  late final Future<AttendanceEmployee?> _rememberedEmployee;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? SharedPreferencesAttendanceStore();
    final punchEndpoint = Uri.parse(attendancePunchApiUrl);
    final apiClient =
        widget.apiClient ?? IoAttendanceApiClient(endpoint: punchEndpoint);
    _ownsSyncService = widget.syncService == null;
    _syncService =
        widget.syncService ??
        AttendanceSyncService(
          store: _store,
          apiClient: apiClient,
          enabled: widget.enableLiveApi,
        );
    _profileClient =
        widget.profileClient ??
        IoAttendanceProfileClient(
          profileEndpoint: Uri.parse(attendanceProfileApiUrl),
          imageEndpoint: Uri.parse(attendanceImageApiUrl),
        );
    _historyClient = widget.enableLiveApi
        ? widget.historyClient ??
              IoAttendanceHistoryClient(
                endpoint: Uri.parse(attendanceHistoryApiUrl),
              )
        : null;
    _rememberedEmployee = _loadRememberedEmployee();
  }

  Future<AttendanceEmployee?> _loadRememberedEmployee() async {
    final preferences = await SharedPreferences.getInstance();
    final employeeId = preferences.getString(rememberedAttendanceEmployeeKey);
    if (employeeId == null) return null;
    for (final employee in attendanceEmployees) {
      if (employee.apiEmployeeId == employeeId) return employee;
    }
    await preferences.remove(rememberedAttendanceEmployeeKey);
    return null;
  }

  Future<void> _rememberEmployee(AttendanceEmployee employee) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      rememberedAttendanceEmployeeKey,
      employee.apiEmployeeId,
    );
    if (!saved) {
      debugPrint('Could not remember attendance employee selection.');
    }
  }

  @override
  void dispose() {
    if (_ownsSyncService) {
      unawaited(_syncService.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: GlobalContext.navigatorKey,
      title: 'Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: attendancePrimary,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: FutureBuilder<AttendanceEmployee?>(
        future: _rememberedEmployee,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: CircularProgressIndicator(color: attendancePrimary),
              ),
            );
          }
          final remembered = snapshot.data;
          return EmployeeSelectionPage(
            profileClient: _profileClient,
            historyClient: _historyClient,
            store: _store,
            syncService: _syncService,
            faceVerifier: widget.faceVerifier,
            clock: widget.clock,
            initialEmployeeId: remembered?.apiEmployeeId,
            autoContinue: remembered != null,
            onEmployeeConfirmed: _rememberEmployee,
          );
        },
      ),
    );
  }
}
