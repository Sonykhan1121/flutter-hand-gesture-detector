# Attendance Application

The attendance implementation now lives under `lib/temp/` and is launched by
the canonical Flutter entry point:

```bash
fvm flutter run
```

## Employees

| Selection name | Employee ID | Device MAC |
| --- | --- | --- |
| Mostakima Akter Mita | `3531774223` | `08_2c_6d_f4_f4_99` |
| Tamanna | `3531774258` | `08_2c_6d_f4_f4_99` |
| Mir Sultan | `2109058928` | `e3_30_f3_44_74_03` |

After selection, the app loads the employee profile and downloads its
`imageFile`. The displayed company ID is the trimmed value after `|` in the
profile email. A trailing server suffix such as `<1` is removed from the
displayed name.

The first successful employee selection is saved in `SharedPreferences`.
Later launches skip the three-person selector, fetch that employee's latest
profile and photo, and open attendance automatically. If the saved employee no
longer exists, the preference is cleared. If automatic profile or photo loading
fails, the selector reappears with Retry so the user is not locked out. The
attendance page has no employee-change back button and replaces the selector
route, so system back navigation cannot reveal employee selection again.

## Punch synchronization

Live punch submission is enabled in `lib/main.dart`. A verified punch is saved
to `SharedPreferences` as pending before the network request begins:

- HTTP 200 changes it to synced.
- Timeouts, network errors, server errors, and non-200 responses keep it
  pending.
- Pending punches are gray in the attendance strip.
- Pending punches retry in chronological order at application startup.
- Refresh retries pending punches for the currently selected employee.

The stored punch retains its original employee ID, MAC, date, and time for
every retry. Previously stored timestamp-only history is migrated as synced and
is never submitted again.

When the attendance page opens, it also loads the selected employee's
current-day `checkIn` history from the server. Server punches are authoritative
for synced entries on that date: matching pending punches become synced,
unmatched pending punches remain gray, and stale local synced entries are
removed. The same server refresh runs from the Refresh button and when the
calendar day changes. If the history request fails, the saved local history is
left unchanged and pending submission retries still run.

## Face verification

Face Attendance uses the front camera and on-device ML Kit face detection. It
requires exactly one continuously visible face for two seconds, then returns
to attendance and records the punch. This verifies face presence only; it is
not biometric identity matching and does not save face images.
