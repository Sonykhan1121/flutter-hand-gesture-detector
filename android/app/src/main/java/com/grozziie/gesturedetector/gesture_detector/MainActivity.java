package com.grozziie.gesturedetector.gesture_detector;

import android.content.ContentValues;
import android.database.Cursor;
import android.os.Build;
import android.provider.MediaStore;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String DOWNLOAD_CHANNEL = "smart_stand/downloads";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                DOWNLOAD_CHANNEL
        ).setMethodCallHandler((call, result) -> {
            if ("nextMovingDownUserId".equals(call.method)) {
                try {
                    result.success(nextMovingDownUserId());
                } catch (Exception error) {
                    result.error("USER_ID_FAILED", error.getMessage(), null);
                }
                return;
            }
            if (!"saveTextFile".equals(call.method)) {
                result.notImplemented();
                return;
            }

            String fileName = call.argument("fileName");
            String contents = call.argument("contents");
            if (fileName == null || contents == null) {
                result.error("INVALID_ARGUMENT", "fileName and contents are required", null);
                return;
            }

            try {
                result.success(saveJsonlToDownloads(fileName, contents));
            } catch (Exception error) {
                result.error("SAVE_FAILED", error.getMessage(), null);
            }
        });
    }

    private String nextMovingDownUserId() {
        int largestNumber = 999;
        Pattern filePattern = Pattern.compile("^user(\\d+)_direction_down_.*\\.jsonl$");

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            String[] projection = {MediaStore.Downloads.DISPLAY_NAME};
            String selection = MediaStore.Downloads.RELATIVE_PATH + "=?";
            String[] selectionArgs = {"Download/moving down/"};
            try (Cursor cursor = getContentResolver().query(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    projection,
                    selection,
                    selectionArgs,
                    null
            )) {
                if (cursor != null) {
                    int nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Downloads.DISPLAY_NAME);
                    while (cursor.moveToNext()) {
                        largestNumber = largestMovingDownNumber(
                                cursor.getString(nameColumn), filePattern, largestNumber
                        );
                    }
                }
            }
        } else {
            File folder = new File(
                    android.os.Environment.getExternalStoragePublicDirectory(
                            android.os.Environment.DIRECTORY_DOWNLOADS
                    ),
                    "moving down"
            );
            File[] files = folder.listFiles();
            if (files != null) {
                for (File file : files) {
                    largestNumber = largestMovingDownNumber(
                            file.getName(), filePattern, largestNumber
                    );
                }
            }
        }
        return "user" + (largestNumber + 1);
    }

    private int largestMovingDownNumber(String name, Pattern pattern, int currentLargest) {
        Matcher matcher = pattern.matcher(name);
        if (!matcher.matches()) return currentLargest;
        try {
            return Math.max(currentLargest, Integer.parseInt(matcher.group(1)));
        } catch (NumberFormatException ignored) {
            return currentLargest;
        }
    }

    private String saveJsonlToDownloads(String fileName, String contents) throws Exception {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContentValues values = new ContentValues();
            values.put(MediaStore.Downloads.DISPLAY_NAME, fileName);
            values.put(MediaStore.Downloads.MIME_TYPE, "application/x-ndjson");
            values.put(MediaStore.Downloads.RELATIVE_PATH, "Download/moving down");
            values.put(MediaStore.Downloads.IS_PENDING, 1);

            android.net.Uri uri = getContentResolver().insert(
                    MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                    values
            );
            if (uri == null) throw new IllegalStateException("Could not create download file");

            try (OutputStream output = getContentResolver().openOutputStream(uri)) {
                if (output == null) throw new IllegalStateException("Could not open download file");
                output.write(contents.getBytes(java.nio.charset.StandardCharsets.UTF_8));
            }

            values.clear();
            values.put(MediaStore.Downloads.IS_PENDING, 0);
            getContentResolver().update(uri, values, null, null);
            return "Download/moving down/" + fileName;
        }

        File folder = new File(
                android.os.Environment.getExternalStoragePublicDirectory(
                        android.os.Environment.DIRECTORY_DOWNLOADS
                ),
                "moving down"
        );
        if (!folder.exists() && !folder.mkdirs()) {
            throw new IllegalStateException("Could not create moving down folder");
        }
        File destination = new File(folder, fileName);
        try (FileOutputStream output = new FileOutputStream(destination)) {
            output.write(contents.getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }
        return destination.getAbsolutePath();
    }
}
