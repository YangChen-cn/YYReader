#!/usr/bin/env bash

# Shared helpers for producing an app bundle that does not retain paths from the
# machine that built it. This file is sourced by the build and release scripts.

portable_bundle_rpaths() {
  /usr/bin/otool -l "$1" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { reading_rpath = 1; next }
    reading_rpath && $1 == "path" { print $2; reading_rpath = 0 }
  '
}

portable_bundle_macho_files() {
  local app_bundle="$1"
  while IFS= read -r -d '' candidate; do
    if /usr/bin/file -b "$candidate" | /usr/bin/grep -q '^Mach-O'; then
      printf '%s\0' "$candidate"
    fi
  done < <(/usr/bin/find "$app_bundle/Contents" -type f -print0)
}

sanitize_portable_bundle() {
  local app_bundle="$1"
  local macho_file
  local rpath

  while IFS= read -r -d '' macho_file; do
    # Xcode embeds Swift AST/debug records that point back into DerivedData.
    # They are not needed by a runnable bundle and would disclose the build
    # machine path even after compiler prefix mapping.
    /usr/bin/strip -S "$macho_file"

    while IFS= read -r rpath; do
      case "$rpath" in
        @*|/usr/lib/swift)
          ;;
        /*)
          /usr/bin/install_name_tool -delete_rpath "$rpath" "$macho_file"
          ;;
      esac
    done < <(portable_bundle_rpaths "$macho_file")
  done < <(portable_bundle_macho_files "$app_bundle")
}

sign_portable_bundle() {
  local app_bundle="$1"
  local entitlements="$2"
  local executable_name
  local main_executable
  local macho_file

  executable_name="$(/usr/bin/plutil -extract CFBundleExecutable raw "$app_bundle/Contents/Info.plist")"
  main_executable="$app_bundle/Contents/MacOS/$executable_name"

  # install_name_tool invalidates every edited Mach-O signature. Sign embedded
  # code first so the outer app signature seals the final nested-code state.
  while IFS= read -r -d '' macho_file; do
    if [[ "$macho_file" != "$main_executable" ]]; then
      /usr/bin/codesign --force --sign - --timestamp=none "$macho_file"
    fi
  done < <(portable_bundle_macho_files "$app_bundle")

  /usr/bin/codesign \
    --force \
    --sign - \
    --timestamp=none \
    --entitlements "$entitlements" \
    "$app_bundle"
}

verify_portable_bundle() {
  local app_bundle="$1"
  local source_root="$2"
  local macho_file
  local dependency
  local rpath

  if LC_ALL=C /usr/bin/grep -aR -l -F "$source_root" "$app_bundle" >/dev/null 2>&1; then
    echo "bundle contains the source checkout path: $source_root" >&2
    return 1
  fi
  if LC_ALL=C /usr/bin/grep -aR -l -E '/Users/[^/]+/' "$app_bundle" >/dev/null 2>&1; then
    echo "bundle contains a development-machine user path" >&2
    return 1
  fi

  while IFS= read -r -d '' macho_file; do
    while IFS= read -r rpath; do
      case "$rpath" in
        @*|/usr/lib/swift)
          ;;
        *)
          echo "bundle contains a non-portable rpath: $rpath" >&2
          return 1
          ;;
      esac
    done < <(portable_bundle_rpaths "$macho_file")

    while IFS= read -r dependency; do
      case "$dependency" in
        @*|/System/Library/*|/usr/lib/*)
          ;;
        *)
          echo "bundle contains a non-portable dependency: $dependency" >&2
          return 1
          ;;
      esac
    done < <(/usr/bin/otool -L "$macho_file" | /usr/bin/tail -n +2 | /usr/bin/awk '{ print $1 }')
  done < <(portable_bundle_macho_files "$app_bundle")
}
