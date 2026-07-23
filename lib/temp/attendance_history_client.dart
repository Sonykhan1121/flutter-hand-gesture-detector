import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'attendance_api_client.dart';

class AttendanceServerHistory {
  const AttendanceServerHistory({
    required this.employeeId,
    required this.macId,
    required this.date,
    required this.checkInTimes,
  });

  final String employeeId;
  final String macId;
  final DateTime date;
  final List<String> checkInTimes;
}

class AttendanceHistoryException implements Exception {
  const AttendanceHistoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AttendanceHistoryClient {
  Future<AttendanceServerHistory> fetchToday({
    required String employeeId,
    required String macId,
    required DateTime date,
  });
}

class IoAttendanceHistoryClient implements AttendanceHistoryClient {
  IoAttendanceHistoryClient({
    required this.endpoint,
    this.timeout = const Duration(seconds: 20),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final Uri endpoint;
  final Duration timeout;
  final HttpClient Function() _clientFactory;

  @override
  Future<AttendanceServerHistory> fetchToday({
    required String employeeId,
    required String macId,
    required DateTime date,
  }) async {
    final client = _clientFactory();
    try {
      final request = await client
          .getUrl(
            attendanceHistoryUri(
              endpoint: endpoint,
              employeeId: employeeId,
              macId: macId,
              date: date,
            ),
          )
          .timeout(timeout);
      final response = await request.close().timeout(timeout);
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw AttendanceHistoryException(
          'Attendance history server returned HTTP ${response.statusCode}.',
        );
      }
      return attendanceServerHistoryFromResponse(
        responseBody: responseBody,
        employeeId: employeeId,
        macId: macId,
        date: date,
      );
    } on AttendanceHistoryException {
      rethrow;
    } on TimeoutException {
      throw AttendanceHistoryException(
        'The attendance history server timed out after '
        '${timeout.inSeconds} seconds.',
      );
    } on SocketException catch (error) {
      throw AttendanceHistoryException('Network error: ${error.message}');
    } on HttpException catch (error) {
      throw AttendanceHistoryException('HTTP error: ${error.message}');
    } catch (error) {
      throw AttendanceHistoryException(
        'Attendance history request failed: $error',
      );
    } finally {
      client.close(force: true);
    }
  }
}

Uri attendanceHistoryUri({
  required Uri endpoint,
  required String employeeId,
  required String macId,
  required DateTime date,
}) {
  return endpoint.replace(
    queryParameters: <String, String>{
      'macId': macId,
      'empId': employeeId,
      'date': attendanceDateKey(date),
    },
  );
}

AttendanceServerHistory attendanceServerHistoryFromResponse({
  required String responseBody,
  required String employeeId,
  required String macId,
  required DateTime date,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(responseBody);
  } on FormatException {
    throw const AttendanceHistoryException(
      'Attendance history response is not valid JSON.',
    );
  }
  if (decoded is! List<dynamic>) {
    throw const AttendanceHistoryException(
      'Attendance history response must be a JSON list.',
    );
  }

  final expectedDate = attendanceDateKey(date);
  final checkInTimes = <String>[];
  for (final value in decoded) {
    if (value is! Map<String, dynamic>) {
      throw const AttendanceHistoryException(
        'Attendance history contains an invalid record.',
      );
    }
    final responseEmployeeId = value['empId']?.toString().trim();
    final responseMacId = value['macId']?.toString().trim();
    final responseDate = value['date']?.toString().trim();
    if (responseEmployeeId != employeeId ||
        responseMacId != macId ||
        responseDate != expectedDate) {
      throw const AttendanceHistoryException(
        'Attendance history does not match the selected employee and date.',
      );
    }

    final encodedCheckIn = value['checkIn'];
    if (encodedCheckIn == null) continue;
    if (encodedCheckIn is! String) {
      throw const AttendanceHistoryException(
        'Attendance history checkIn must be a JSON string.',
      );
    }
    if (encodedCheckIn.trim().isEmpty) continue;

    Object? decodedCheckIn;
    try {
      decodedCheckIn = jsonDecode(encodedCheckIn);
    } on FormatException {
      throw const AttendanceHistoryException(
        'Attendance history checkIn is not valid JSON.',
      );
    }
    if (decodedCheckIn is! List<dynamic>) {
      throw const AttendanceHistoryException(
        'Attendance history checkIn must contain a JSON list.',
      );
    }
    for (final time in decodedCheckIn) {
      if (time is! String || !_isValidServerTime(time)) {
        throw const AttendanceHistoryException(
          'Attendance history contains an invalid punch time.',
        );
      }
      checkInTimes.add(time);
    }
  }

  return AttendanceServerHistory(
    employeeId: employeeId,
    macId: macId,
    date: DateTime(date.year, date.month, date.day),
    checkInTimes: List<String>.unmodifiable(checkInTimes),
  );
}

bool _isValidServerTime(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}
