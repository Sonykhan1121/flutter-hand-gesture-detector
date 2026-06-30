#!/usr/bin/env bash

set -u

REQUIRED_PAGE_KB=16
REQUIRED_ELF_EXP=14

START_DIR="$(pwd)"
SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd)"

if [ -d "$SCRIPT_DIR/android" ]; then
  cd "$SCRIPT_DIR" || exit 2
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

print_usage() {
  cat <<'USAGE'
Usage:
  ./check_16kb_support.command [path/to/app.apk|path/to/app.aab]

If no file is provided, the script checks the newest .apk or .aab under:
  build/app/outputs/

Exit codes:
  0 = supported
  1 = not supported
  2 = inconclusive because one or more required tools/checks were missing
USAGE
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf 'WARN: %s\n' "$1"
}

info() {
  printf 'INFO: %s\n' "$1"
}

command_path() {
  command -v "$1" 2>/dev/null || true
}

local_properties_value() {
  local key="$1"
  if [ -f "android/local.properties" ]; then
    sed -n "s/^${key}=//p" android/local.properties | tail -n 1
  fi
}

find_android_sdk() {
  local sdk_dir

  sdk_dir="$(local_properties_value "sdk.dir")"
  if [ -n "${sdk_dir:-}" ] && [ -d "$sdk_dir" ]; then
    printf '%s\n' "$sdk_dir"
    return
  fi

  if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
    printf '%s\n' "$ANDROID_SDK_ROOT"
    return
  fi

  if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
    printf '%s\n' "$ANDROID_HOME"
    return
  fi

  if [ -d "$HOME/Library/Android/sdk" ]; then
    printf '%s\n' "$HOME/Library/Android/sdk"
    return
  fi

  if [ -d "$HOME/Android/Sdk" ]; then
    printf '%s\n' "$HOME/Android/Sdk"
  fi
}

find_zipalign() {
  local from_path sdk_dir found

  from_path="$(command_path zipalign)"
  if [ -n "$from_path" ]; then
    printf '%s\n' "$from_path"
    return
  fi

  sdk_dir="$1"
  if [ -n "$sdk_dir" ] && [ -d "$sdk_dir/build-tools" ]; then
    found="$(find "$sdk_dir/build-tools" -path '*/zipalign' -type f 2>/dev/null | sort | tail -n 1)"
    if [ -n "$found" ]; then
      printf '%s\n' "$found"
    fi
  fi
}

find_llvm_objdump() {
  local from_path sdk_dir found

  from_path="$(command_path llvm-objdump)"
  if [ -n "$from_path" ]; then
    printf '%s\n' "$from_path"
    return
  fi

  sdk_dir="$1"
  if [ -n "$sdk_dir" ] && [ -d "$sdk_dir/ndk" ]; then
    found="$(find "$sdk_dir/ndk" -path '*/bin/llvm-objdump' -type f 2>/dev/null | sort | tail -n 1)"
    if [ -n "$found" ]; then
      printf '%s\n' "$found"
    fi
  fi
}

file_mtime() {
  stat -f '%m' "$1" 2>/dev/null || stat -c '%Y' "$1" 2>/dev/null || printf '0\n'
}

find_latest_artifact() {
  if [ ! -d "build/app/outputs" ]; then
    return
  fi

  find build/app/outputs -type f \( -name '*.apk' -o -name '*.aab' \) -print 2>/dev/null |
    while IFS= read -r file; do
      printf '%s %s\n' "$(file_mtime "$file")" "$file"
    done |
    sort -nr |
    head -n 1 |
    sed 's/^[0-9][0-9]* //'
}

absolute_arg_path() {
  local path="$1"
  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *) printf '%s/%s\n' "$START_DIR" "$path" ;;
  esac
}

artifact_extension() {
  printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]'
}

artifact_size() {
  du -h "$1" 2>/dev/null | awk '{print $1}'
}

list_native_libraries() {
  unzip -Z1 "$1" 2>/dev/null | grep -E '(^|/)lib/[^/]+/[^/]+\.so$' || true
}

abi_from_entry() {
  local entry="$1"
  local after_lib="${entry#*lib/}"

  if [ "$after_lib" = "$entry" ]; then
    printf 'unknown'
  else
    printf '%s' "${after_lib%%/*}"
  fi
}

check_zipalign() {
  local artifact="$1"
  local zipalign="$2"
  local output status details

  if [ -z "$zipalign" ]; then
    warn "Cannot verify APK zip alignment because zipalign was not found. Install Android SDK Build-Tools 35.0.0 or newer."
    return
  fi

  output="$("$zipalign" -c -P "$REQUIRED_PAGE_KB" -v 4 "$artifact" 2>&1)"
  status=$?

  if [ "$status" -eq 0 ]; then
    pass "APK zip alignment passes: zipalign -c -P ${REQUIRED_PAGE_KB} -v 4"
  else
    fail "APK zip alignment failed. Uncompressed .so files are not aligned to ${REQUIRED_PAGE_KB} KB boundaries."
    details="$(printf '%s\n' "$output" | awk '!/\(OK/ { print }' | tail -n 40)"
    if [ -n "$details" ]; then
      printf '%s\n' "$details" | sed 's/^/  /'
    fi
  fi
}

check_aab_config() {
  local artifact="$1"
  local bundletool="$2"
  local output status alignment_lines

  if [ -z "$bundletool" ]; then
    warn "Cannot verify AAB bundle config because bundletool was not found. Install bundletool and rerun this script."
    return
  fi

  output="$("$bundletool" dump config --bundle="$artifact" 2>&1)"
  status=$?

  if [ "$status" -ne 0 ]; then
    warn "bundletool could not read the AAB config."
    printf '%s\n' "$output" | tail -n 20 | sed 's/^/  /'
    return
  fi

  alignment_lines="$(printf '%s\n' "$output" | grep 'alignment' || true)"

  if printf '%s\n' "$output" | grep -q 'PAGE_ALIGNMENT_16K'; then
    pass "AAB bundle config requests PAGE_ALIGNMENT_16K."
    printf '%s\n' "$alignment_lines" | sed 's/^/  /'
  elif printf '%s\n' "$output" | grep -q 'PAGE_ALIGNMENT_4K'; then
    fail "AAB bundle config requests PAGE_ALIGNMENT_4K, so APKs generated from this bundle can be 4 KB aligned."
    printf '%s\n' "$alignment_lines" | sed 's/^/  /'
  elif [ -n "$alignment_lines" ]; then
    warn "AAB bundle config has an unknown alignment value."
    printf '%s\n' "$alignment_lines" | sed 's/^/  /'
  else
    warn "AAB bundle config does not show native-library page alignment. Upgrade Android Gradle Plugin to 8.5.1+ or verify generated APKs with zipalign."
  fi
}

check_elf_alignment() {
  local artifact="$1"
  local objdump="$2"
  local native_libraries="$3"
  local temp_dir="$4"
  local checked=0
  local failed=0
  local entry out_file objdump_output load_lines line exp abi aligns bad_aligns

  if [ -z "$objdump" ]; then
    warn "Cannot verify ELF LOAD segment alignment because llvm-objdump was not found. Install Android NDK r28 or newer."
    return
  fi

  printf '\nELF LOAD segment details:\n'
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue

    checked=$((checked + 1))
    abi="$(abi_from_entry "$entry")"
    out_file="$temp_dir/$entry"
    mkdir -p "$(dirname "$out_file")"

    if ! unzip -p "$artifact" "$entry" > "$out_file" 2>/dev/null; then
      failed=$((failed + 1))
      printf '  FAIL  %-12s %s (could not extract)\n' "$abi" "$entry"
      continue
    fi

    objdump_output="$("$objdump" -p "$out_file" 2>&1)"
    load_lines="$(printf '%s\n' "$objdump_output" | grep '^[[:space:]]*LOAD ' || true)"

    if [ -z "$load_lines" ]; then
      failed=$((failed + 1))
      printf '  FAIL  %-12s %s (no LOAD segments found)\n' "$abi" "$entry"
      continue
    fi

    aligns=""
    bad_aligns=""
    while IFS= read -r line; do
      exp="$(printf '%s\n' "$line" | sed -n 's/.*align 2\*\*\([0-9][0-9]*\).*/\1/p')"
      [ -z "$exp" ] && continue
      aligns="${aligns}2**${exp} "
      if [ "$exp" -lt "$REQUIRED_ELF_EXP" ]; then
        bad_aligns="${bad_aligns}2**${exp} "
      fi
    done <<< "$load_lines"

    if [ -n "$bad_aligns" ]; then
      failed=$((failed + 1))
      printf '  FAIL  %-12s %s (bad LOAD alignments: %s; need >= 2**%s)\n' "$abi" "$entry" "$bad_aligns" "$REQUIRED_ELF_EXP"
    else
      printf '  PASS  %-12s %s (LOAD alignments: %s)\n' "$abi" "$entry" "$aligns"
    fi
  done <<< "$native_libraries"

  if [ "$checked" -eq 0 ]; then
    pass "No native .so libraries found. Java/Kotlin-only APKs/AABs normally support 16 KB page-size devices."
  elif [ "$failed" -eq 0 ]; then
    pass "ELF alignment passes for $checked native libraries. All LOAD segments are >= 2**${REQUIRED_ELF_EXP}."
  else
    fail "ELF alignment failed for $failed of $checked native libraries. Rebuild or update the listed native libraries."
  fi
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  print_usage
  exit 0
fi

ARTIFACT="${1:-}"
if [ -n "$ARTIFACT" ]; then
  ARTIFACT="$(absolute_arg_path "$ARTIFACT")"
else
  ARTIFACT="$(find_latest_artifact)"
fi

if [ -z "$ARTIFACT" ] || [ ! -f "$ARTIFACT" ]; then
  fail "No APK/AAB file found. Build one first, for example: flutter build apk --release"
  print_usage
  exit 1
fi

EXTENSION="$(artifact_extension "$ARTIFACT")"
if [ "$EXTENSION" != "apk" ] && [ "$EXTENSION" != "aab" ]; then
  fail "Unsupported file type: .$EXTENSION. Please pass an .apk or .aab file."
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  fail "unzip is required but was not found."
  exit 1
fi

if ! unzip -tq "$ARTIFACT" >/dev/null 2>&1; then
  fail "The file is not a readable APK/AAB zip archive: $ARTIFACT"
  exit 1
fi

ANDROID_SDK="$(find_android_sdk)"
ZIPALIGN="$(find_zipalign "$ANDROID_SDK")"
LLVM_OBJDUMP="$(find_llvm_objdump "$ANDROID_SDK")"
BUNDLETOOL="$(command_path bundletool)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/check-16kb.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

NATIVE_LIBRARIES="$(list_native_libraries "$ARTIFACT")"
NATIVE_COUNT="$(printf '%s\n' "$NATIVE_LIBRARIES" | sed '/^$/d' | wc -l | tr -d ' ')"

printf 'Android 16 KB support check\n'
printf '===========================\n'
info "Artifact: $ARTIFACT"
info "Type: .$EXTENSION"
info "Size: $(artifact_size "$ARTIFACT")"
info "Native .so libraries found: $NATIVE_COUNT"
if [ -n "$ANDROID_SDK" ]; then
  info "Android SDK: $ANDROID_SDK"
else
  warn "Android SDK was not found from android/local.properties, ANDROID_SDK_ROOT, ANDROID_HOME, or common defaults."
fi
if [ -n "$ZIPALIGN" ]; then info "zipalign: $ZIPALIGN"; fi
if [ -n "$LLVM_OBJDUMP" ]; then info "llvm-objdump: $LLVM_OBJDUMP"; fi
if [ -n "$BUNDLETOOL" ]; then info "bundletool: $BUNDLETOOL"; fi

printf '\nChecks:\n'
check_elf_alignment "$ARTIFACT" "$LLVM_OBJDUMP" "$NATIVE_LIBRARIES" "$TEMP_DIR"

if [ "$NATIVE_COUNT" -gt 0 ]; then
  if [ "$EXTENSION" = "apk" ]; then
    printf '\nAPK zip alignment details:\n'
    check_zipalign "$ARTIFACT" "$ZIPALIGN"
  else
    printf '\nAAB bundle config details:\n'
    check_aab_config "$ARTIFACT" "$BUNDLETOOL"
  fi
fi

printf '\nSummary:\n'
printf '  Pass: %s\n' "$PASS_COUNT"
printf '  Fail: %s\n' "$FAIL_COUNT"
printf '  Warn: %s\n' "$WARN_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  printf '\nRESULT: NOT 16 KB SUPPORTED\n'
  printf 'Reason: Fix the failed checks above, usually by upgrading AGP/NDK/Flutter plugins or replacing unaligned native SDK libraries.\n'
  exit 1
fi

if [ "$WARN_COUNT" -gt 0 ]; then
  printf '\nRESULT: INCONCLUSIVE\n'
  printf 'Reason: One or more required verification tools/checks were unavailable. Install the missing tools and rerun.\n'
  exit 2
fi

printf '\nRESULT: 16 KB SUPPORTED\n'
exit 0
