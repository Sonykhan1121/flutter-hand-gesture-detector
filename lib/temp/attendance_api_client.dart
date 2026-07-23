import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// All fields needed by the historical punch endpoint.
class AttendancePunchRequest {
  const AttendancePunchRequest({
    required this.employeeId,
    required this.macId,
    required this.punchedAt,
  });

  final String employeeId;
  final String macId;
  final DateTime punchedAt;

  Map<String, Object?> toJson() {
    final date = _dateKey(punchedAt);
    final time =
        '${_twoDigits(punchedAt.hour)}:${_twoDigits(punchedAt.minute)}';

    return <String, Object?>{
      'empId': employeeId,
      'macId': macId,
      'date': date,
      // The old server expects a JSON array stored inside a JSON string.
      'checkIn': jsonEncode(<String>[time]),
      'checkOut': null,
      'lunchTimeCheckIn': null,
      'lunchTimeCheckOut': null,
      'status': 'synced',
    };
  }
}

class AttendanceApiResult {
  const AttendanceApiResult({
    required this.statusCode,
    this.responseBody = '',
    this.errorMessage,
  });

  final int? statusCode;
  final String responseBody;
  final String? errorMessage;

  bool get isSuccess => statusCode == HttpStatus.ok;
}

abstract interface class AttendanceApiClient {
  Future<AttendanceApiResult> submitPunch(AttendancePunchRequest request);
}

/// `dart:io` implementation kept inside the temporary target.
class IoAttendanceApiClient implements AttendanceApiClient {
  IoAttendanceApiClient({
    required this.endpoint,
    this.timeout = const Duration(seconds: 20),
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final Uri endpoint;
  final Duration timeout;
  final HttpClient Function() _clientFactory;

  @override
  Future<AttendanceApiResult> submitPunch(AttendancePunchRequest punch) async {
    final client = _clientFactory();
    try {
      final request = await client.postUrl(endpoint).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(punch.toJson()));

      final response = await request.close().timeout(timeout);
      final responseBody = await utf8.decoder
          .bind(response)
          .join()
          .timeout(timeout);
      return AttendanceApiResult(
        statusCode: response.statusCode,
        responseBody: responseBody,
      );
    } on TimeoutException {
      return const AttendanceApiResult(
        statusCode: null,
        errorMessage: 'The attendance server timed out after 20 seconds.',
      );
    } on SocketException catch (error) {
      return AttendanceApiResult(
        statusCode: null,
        errorMessage: 'Network error: ${error.message}',
      );
    } on HttpException catch (error) {
      return AttendanceApiResult(
        statusCode: null,
        errorMessage: 'HTTP error: ${error.message}',
      );
    } catch (error) {
      return AttendanceApiResult(
        statusCode: null,
        errorMessage: 'Attendance request failed: $error',
      );
    } finally {
      client.close(force: true);
    }
  }
}

String attendanceDateKey(DateTime value) => _dateKey(value);

String _dateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${_twoDigits(value.month)}-${_twoDigits(value.day)}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
