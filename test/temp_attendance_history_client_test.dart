import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gesture_detector/temp/attendance_employee.dart';
import 'package:gesture_detector/temp/attendance_history_client.dart';

void main() {
  final endpoint = Uri.parse(
    'https://grozziie.zjweiting.com:3091/'
    'grozziie-attendance-debug/attendance/emp',
  );
  final day = DateTime(2026, 7, 23);

  test('builds exact current-day history URLs for all employees', () {
    expect(
      attendanceEmployees
          .map(
            (employee) => attendanceHistoryUri(
              endpoint: endpoint,
              employeeId: employee.apiEmployeeId,
              macId: employee.deviceMac,
              date: day,
            ).toString(),
          )
          .toList(),
      <String>[
        '${endpoint.toString()}'
            '?macId=08_2c_6d_f4_f4_99&empId=3531774223&date=2026-07-23',
        '${endpoint.toString()}'
            '?macId=08_2c_6d_f4_f4_99&empId=3531774258&date=2026-07-23',
        '${endpoint.toString()}'
            '?macId=e3_30_f3_44_74_03&empId=2109058928&date=2026-07-23',
      ],
    );
  });

  test('parses the supplied double-encoded checkIn response', () {
    final history = attendanceServerHistoryFromResponse(
      responseBody: jsonEncode(<Object?>[
        <String, Object?>{
          'empId': '2109058928',
          'macId': 'e3_30_f3_44_74_03',
          'date': '2026-07-23',
          'checkIn': '["08:01"]',
          'lunchTimeCheckIn': null,
          'lunchTimeCheckOut': null,
          'checkOut': null,
          'status': 'synced',
        },
      ]),
      employeeId: '2109058928',
      macId: 'e3_30_f3_44_74_03',
      date: day,
    );

    expect(history.employeeId, '2109058928');
    expect(history.macId, 'e3_30_f3_44_74_03');
    expect(history.date, day);
    expect(history.checkInTimes, <String>['08:01']);
  });

  test('aggregates records and preserves duplicate times', () {
    final history = attendanceServerHistoryFromResponse(
      responseBody: jsonEncode(<Object?>[
        <String, Object?>{
          'empId': '2109058928',
          'macId': 'e3_30_f3_44_74_03',
          'date': '2026-07-23',
          'checkIn': '["08:01","08:01"]',
        },
        <String, Object?>{
          'empId': '2109058928',
          'macId': 'e3_30_f3_44_74_03',
          'date': '2026-07-23',
          'checkIn': null,
        },
        <String, Object?>{
          'empId': '2109058928',
          'macId': 'e3_30_f3_44_74_03',
          'date': '2026-07-23',
          'checkIn': '',
        },
        <String, Object?>{
          'empId': '2109058928',
          'macId': 'e3_30_f3_44_74_03',
          'date': '2026-07-23',
          'checkIn': '["13:45"]',
        },
      ]),
      employeeId: '2109058928',
      macId: 'e3_30_f3_44_74_03',
      date: day,
    );

    expect(history.checkInTimes, <String>['08:01', '08:01', '13:45']);
  });

  test('accepts an empty server response as authoritative empty history', () {
    final history = attendanceServerHistoryFromResponse(
      responseBody: '[]',
      employeeId: '2109058928',
      macId: 'e3_30_f3_44_74_03',
      date: day,
    );

    expect(history.checkInTimes, isEmpty);
  });

  test('rejects malformed, mismatched, and invalid-time responses', () {
    expect(
      () => attendanceServerHistoryFromResponse(
        responseBody: '{bad json',
        employeeId: '2109058928',
        macId: 'e3_30_f3_44_74_03',
        date: day,
      ),
      throwsA(isA<AttendanceHistoryException>()),
    );
    expect(
      () => attendanceServerHistoryFromResponse(
        responseBody: jsonEncode(<Object?>[
          <String, Object?>{
            'empId': 'somebody-else',
            'macId': 'e3_30_f3_44_74_03',
            'date': '2026-07-23',
            'checkIn': '["08:01"]',
          },
        ]),
        employeeId: '2109058928',
        macId: 'e3_30_f3_44_74_03',
        date: day,
      ),
      throwsA(isA<AttendanceHistoryException>()),
    );
    expect(
      () => attendanceServerHistoryFromResponse(
        responseBody: jsonEncode(<Object?>[
          <String, Object?>{
            'empId': '2109058928',
            'macId': 'e3_30_f3_44_74_03',
            'date': '2026-07-23',
            'checkIn': '["24:00"]',
          },
        ]),
        employeeId: '2109058928',
        macId: 'e3_30_f3_44_74_03',
        date: day,
      ),
      throwsA(isA<AttendanceHistoryException>()),
    );
  });

  test('non-200 response is rejected', () async {
    final client = IoAttendanceHistoryClient(
      endpoint: endpoint,
      clientFactory: () => _FakeHttpClient(
        request: _FakeHttpClientRequest(
          _FakeHttpClientResponse(statusCode: 503, body: 'unavailable'),
        ),
      ),
    );

    await expectLater(
      client.fetchToday(
        employeeId: '2109058928',
        macId: 'e3_30_f3_44_74_03',
        date: day,
      ),
      throwsA(
        isA<AttendanceHistoryException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 503'),
        ),
      ),
    );
  });

  test('timeout and socket failures are converted to history errors', () async {
    final timeoutClient = IoAttendanceHistoryClient(
      endpoint: endpoint,
      timeout: const Duration(milliseconds: 1),
      clientFactory: () =>
          _FakeHttpClient(requestFuture: Completer<HttpClientRequest>().future),
    );
    await expectLater(
      timeoutClient.fetchToday(
        employeeId: '2109058928',
        macId: 'e3_30_f3_44_74_03',
        date: day,
      ),
      throwsA(
        isA<AttendanceHistoryException>().having(
          (error) => error.message,
          'message',
          contains('timed out'),
        ),
      ),
    );

    final socketClient = IoAttendanceHistoryClient(
      endpoint: endpoint,
      clientFactory: () =>
          _FakeHttpClient(requestError: const SocketException('offline')),
    );
    await expectLater(
      socketClient.fetchToday(
        employeeId: '2109058928',
        macId: 'e3_30_f3_44_74_03',
        date: day,
      ),
      throwsA(
        isA<AttendanceHistoryException>().having(
          (error) => error.message,
          'message',
          contains('offline'),
        ),
      ),
    );
  });
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({this.request, this.requestFuture, this.requestError});

  final HttpClientRequest? request;
  final Future<HttpClientRequest>? requestFuture;
  final Object? requestError;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    final error = requestError;
    if (error != null) return Future<HttpClientRequest>.error(error);
    return requestFuture ?? Future<HttpClientRequest>.value(request!);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.response);

  final HttpClientResponse response;

  @override
  Future<HttpClientResponse> close() async => response;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({required this.statusCode, required String body})
    : super(Stream<List<int>>.value(utf8.encode(body)));

  @override
  final int statusCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
