#!/bin/bash

# Liquid Voice release: a Developer ID signed, notarized, stapled app in a DMG.
#
# Usage:
#   scripts/release.sh                 # build, then package (same as ./build.sh dist)
#   scripts/release.sh build           # Release build only, signed to run locally (no keychain)
#   scripts/release.sh package [APP]   # sign, notarize, staple, DMG, verify an existing build
#   scripts/release.sh verify [APP] [DMG]
#
# The two halves can run on different Macs: `build` needs only Xcode 26 and no
# signing identity, so a build host can make the app; `package` needs the
# Developer ID identity and the notary profile in the login keychain.
#
# Environment:
#   LIQUIDVOICE_NOTARY_PROFILE   notarytool keychain profile (default: liquidvoice-notary)
#   LIQUIDVOICE_SIGN_IDENTITY    codesign identity (default: the one Developer ID Application
#                                identity in the keychain, of LIQUIDVOICE_DEVELOPMENT_TEAM if set)
#   LIQUIDVOICE_DEVELOPMENT_TEAM Team ID that picks among several Developer ID identities
#   LIQUIDVOICE_SKIP_NOTARIZE=1  sign and package without notarizing (signing check only;
#                                the result will not pass Gatekeeper on another Mac)
#   LIQUIDVOICE_DIST_DIR         output folder (default: <repo>/dist)
#   FLUIDVOICE_DERIVED_DATA_PATH DerivedData folder (default: <repo>/DerivedData)
#
# Never launch the built app. It is com.stage11.liquidvoice, the installed app's
# identity, and would write into the installed app's settings and data (CLAUDE.md).

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${FLUIDVOICE_DERIVED_DATA_PATH:-${PROJECT_DIR}/DerivedData}"
DIST_DIR="${LIQUIDVOICE_DIST_DIR:-${PROJECT_DIR}/dist}"
NOTARY_PROFILE="${LIQUIDVOICE_NOTARY_PROFILE:-liquidvoice-notary}"
TEAM="${LIQUIDVOICE_DEVELOPMENT_TEAM:-${FLUIDVOICE_DEVELOPMENT_TEAM:-}}"
SKIP_NOTARIZE="${LIQUIDVOICE_SKIP_NOTARIZE:-0}"
BUILT_APP="${DERIVED_DATA_PATH}/Build/Products/Release/Liquid Voice.app"
APP_NAME="Liquid Voice.app"
VOLUME_NAME="Liquid Voice"

IDENTITY=""

die() {
    printf >&2 '\nrelease: %s\n' "$1"
    shift
    local line
    for line in "$@"; do printf >&2 '  %s\n' "${line}"; done
    exit 1
}

step() { printf '\n==> %s\n' "$1"; }

# ---------------------------------------------------------------- preflight

resolve_identity() {
    if [ -n "${LIQUIDVOICE_SIGN_IDENTITY:-}" ]; then
        IDENTITY="${LIQUIDVOICE_SIGN_IDENTITY}"
    else
        local -a found=()
        local line
        while IFS= read -r line; do
            [ -n "${line}" ] && found+=("${line}")
        done < <(security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
            | { if [ -n "${TEAM}" ]; then grep -F "(${TEAM})" || true; else cat; fi; } \
            | sort -u)
        if [ "${#found[@]}" -eq 0 ]; then
            die "no Developer ID Application identity${TEAM:+ for team ${TEAM}} in the keychain." \
                "A download needs a Developer ID Application certificate (paid Apple Developer Program)." \
                "Create one in Xcode > Settings > Accounts > Manage Certificates, or at developer.apple.com," \
                "then check: security find-identity -v -p codesigning" \
                "To pick one by name, set LIQUIDVOICE_SIGN_IDENTITY."
        fi
        if [ "${#found[@]}" -gt 1 ]; then
            die "several Developer ID Application identities found; set LIQUIDVOICE_DEVELOPMENT_TEAM or LIQUIDVOICE_SIGN_IDENTITY:" \
                "${found[@]}"
        fi
        IDENTITY="${found[0]}"
    fi
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"${IDENTITY}\""; then
        die "the signing identity \"${IDENTITY}\" is not a valid codesigning identity in the keychain."
    fi
    echo "Signing identity: ${IDENTITY}"
}

check_notary_profile() {
    if [ "${SKIP_NOTARIZE}" = "1" ]; then
        echo "Notarization: skipped (LIQUIDVOICE_SKIP_NOTARIZE=1). The result will not pass Gatekeeper elsewhere."
        return
    fi
    local out
    if ! out="$(xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" 2>&1)"; then
        die "the notarytool keychain profile \"${NOTARY_PROFILE}\" is missing or does not work:" \
            "$(printf '%s' "${out}" | head -3)" \
            "" \
            "Store it once (an app-specific password from account.apple.com > Sign-In and Security):" \
            "  xcrun notarytool store-credentials ${NOTARY_PROFILE} --apple-id <apple-id> --team-id <team-id>" \
            "or with an App Store Connect API key:" \
            "  xcrun notarytool store-credentials ${NOTARY_PROFILE} --key <AuthKey_XXXX.p8> --key-id <key-id> --issuer <issuer-uuid>" \
            "Use another profile with LIQUIDVOICE_NOTARY_PROFILE, or sign only with LIQUIDVOICE_SKIP_NOTARIZE=1."
    fi
    echo "Notary profile: ${NOTARY_PROFILE}"
}

# ---------------------------------------------------------------- build

# Release build signed to run locally ("-"). That needs no certificate, so any Mac
# with Xcode 26 can build, yet Xcode still writes the app's real entitlements into
# the signature (Fluid.entitlements plus the hardened-runtime resource entitlements
# such as com.apple.security.device.audio-input). `package` re-signs with them.
run_build() {
    cd "${PROJECT_DIR}"
    step "Release build (signed to run locally; package re-signs it)"
    xcodebuild \
        -project Fluid.xcodeproj \
        -scheme Fluid \
        -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY=- \
        DEVELOPMENT_TEAM= \
        SDK_STAT_CACHE_ENABLE=NO \
        build
    [ -d "${BUILT_APP}" ] || die "the build succeeded but ${BUILT_APP} is missing."
    echo "Build product: ${BUILT_APP}"
    echo "Version: $(app_version "${BUILT_APP}") ($(app_build "${BUILT_APP}"))"
}

# ---------------------------------------------------------------- helpers

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }
app_version() { plist_value "$1/Contents/Info.plist" CFBundleShortVersionString; }
app_build() { plist_value "$1/Contents/Info.plist" CFBundleVersion; }

is_macho() { file -b "$1" 2>/dev/null | grep -q 'Mach-O'; }

# Writes the entitlements a signed item carries to $2, minus get-task-allow (which
# notarization rejects). Leaves $2 empty when there are none.
extract_entitlements() {
    local item="$1" out="$2"
    : > "${out}"
    codesign -d --entitlements - --xml "${item}" > "${out}" 2>/dev/null || : > "${out}"
    if [ -s "${out}" ]; then
        /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "${out}" >/dev/null 2>&1 || true
        if [ "$(/usr/libexec/PlistBuddy -c 'Print' "${out}" 2>/dev/null | wc -l | tr -d ' ')" -le 2 ]; then
            : > "${out}"
        fi
    fi
}

# The vendored CTranscribe.xcframework ships a malformed versioned-framework layout:
# Versions/Current is a real directory and the top-level entries are copies, not
# symlinks, so a signature over it never verifies. Same fix as build.sh
# (normalize_ctranscribe_framework), without the Apple Development re-sign.
normalize_ctranscribe_layout() {
    local fw="$1/Contents/Frameworks/CTranscribe.framework"
    [ -d "${fw}" ] || return 0
    [ -L "${fw}/Versions/Current" ] && return 0
    echo "Normalizing CTranscribe.framework layout..."
    rm -rf "${fw}/Versions/A"
    mv "${fw}/Versions/Current" "${fw}/Versions/A"
    ln -s "A" "${fw}/Versions/Current"
    local entry
    for entry in CTranscribe Resources Headers Modules; do
        if [ -e "${fw}/${entry}" ] && [ ! -L "${fw}/${entry}" ]; then
            rm -rf "${fw}/${entry}"
        fi
        if [ -e "${fw}/Versions/Current/${entry}" ]; then
            ln -sfn "Versions/Current/${entry}" "${fw}/${entry}"
        fi
    done
}

sign_item() {
    local item="$1" entitlements="$2"
    local -a args=(--force --timestamp --options runtime --sign "${IDENTITY}")
    [ -s "${entitlements}" ] && args+=(--entitlements "${entitlements}")
    codesign "${args[@]}" "${item}" || die "codesign failed on ${item}."
}

# Re-signs every nested piece of code inside out, then the app, each with the
# entitlements it was built with, the hardened runtime and a secure timestamp.
sign_app() {
    local app="$1"
    local main_exe ents list
    main_exe="${app}/Contents/MacOS/$(plist_value "${app}/Contents/Info.plist" CFBundleExecutable)"
    ents="$(mktemp -t liquidvoice-ents)"
    list="$(mktemp -t liquidvoice-code)"

    extract_entitlements "${app}" "${ents}"
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' "${ents}" 2>/dev/null)" != "true" ]; then
        rm -f "${ents}" "${list}"
        die "the built app lacks com.apple.security.device.audio-input; under the hardened runtime macOS would deny the microphone silently." \
            "Rebuild with scripts/release.sh build (it keeps Xcode's entitlements)."
    fi
    local app_ents="${ents}.app.plist"
    command cp -f "${ents}" "${app_ents}"

    normalize_ctranscribe_layout "${app}"

    # Nested code: bundles with an executable, and loose Mach-O files. Deepest first,
    # so each container is signed after everything it seals.
    {
        find "${app}/Contents" -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \
            -o -name '*.appex' -o -name '*.bundle' -o -name '*.plugin' \) -print
        find "${app}/Contents" -type f -perm -u+x -print
        find "${app}/Contents" -type f \( -name '*.dylib' -o -name '*.so' \) -print
    } | sort -u > "${list}"

    local item kind count=0
    while IFS= read -r item; do
        [ "${item}" = "${main_exe}" ] && continue
        if [ -d "${item}" ]; then
            # A resource-only bundle (no executable) holds no code to sign.
            case "${item}" in
                *.framework) [ -n "$(find "${item}" -maxdepth 3 -type f -perm -u+x -print -quit)" ] || continue ;;
                *) [ -n "$(plist_value "${item}/Contents/Info.plist" CFBundleExecutable)" ] || continue ;;
            esac
        else
            is_macho "${item}" || continue
        fi
        printf '%s\t%s\n' "$(printf '%s' "${item}" | tr -cd '/' | wc -c | tr -d ' ')" "${item}"
    done < "${list}" | sort -t $'\t' -k1,1nr -k2 | cut -f2- > "${list}.sorted"

    while IFS= read -r item; do
        extract_entitlements "${item}" "${ents}"
        sign_item "${item}" "${ents}"
        kind="file"
        [ -d "${item}" ] && kind="bundle"
        printf '  signed %-6s %s\n' "${kind}" "${item#"${app}/"}"
        count=$((count + 1))
    done < "${list}.sorted"

    sign_item "${app}" "${app_ents}"
    echo "  signed app    (${count} nested items)"
    rm -f "${ents}" "${app_ents}" "${list}" "${list}.sorted"

    codesign --verify --deep --strict --verbose=2 "${app}" || die "the signed app does not verify."
}

# Submits a file and waits. Prints the notary log and stops on anything but Accepted.
notarize() {
    local file="$1"
    local result status id
    result="$(mktemp -t liquidvoice-notary).json"
    echo "Submitting $(basename "${file}") to the notary service (this waits)..."
    if ! xcrun notarytool submit "${file}" --keychain-profile "${NOTARY_PROFILE}" \
        --wait --output-format json > "${result}"; then
        cat >&2 "${result}" || true
        die "notarytool submit failed for ${file}."
    fi
    status="$(plutil -extract status raw -o - "${result}" 2>/dev/null || true)"
    id="$(plutil -extract id raw -o - "${result}" 2>/dev/null || true)"
    echo "Notary submission ${id}: ${status}"
    if [ "${status}" != "Accepted" ]; then
        [ -n "${id}" ] && xcrun notarytool log "${id}" --keychain-profile "${NOTARY_PROFILE}" >&2 || true
        die "notarization of ${file} was not accepted (status: ${status:-unknown}). The log is above."
    fi
    rm -f "${result}"
}

make_dmg() {
    local app="$1" dmg="$2"
    local stage
    stage="$(mktemp -d -t liquidvoice-dmg)"
    ditto "${app}" "${stage}/${APP_NAME}"
    ln -s /Applications "${stage}/Applications"
    rm -f "${dmg}"
    hdiutil create -volname "${VOLUME_NAME}" -srcfolder "${stage}" -fs HFS+ \
        -format UDZO -imagekey zlib-level=9 -ov "${dmg}" >/dev/null \
        || die "hdiutil could not create ${dmg}."
    rm -rf "${stage}"
    codesign --force --timestamp --sign "${IDENTITY}" "${dmg}" || die "codesign failed on ${dmg}."
    echo "DMG: ${dmg}"
}

# ---------------------------------------------------------------- verify

run_verify() {
    local app="$1" dmg="${2:-}"
    local failed=0 out ents
    step "Verify"

    [ -d "${app}" ] || die "no app at ${app}."
    echo "-- codesign --verify --deep --strict ${app##*/}"
    codesign --verify --deep --strict --verbose=2 "${app}" 2>&1 || failed=1

    out="$(codesign -dvv "${app}" 2>&1)"
    printf '%s\n' "${out}" | grep -E '^(Identifier=|Authority=Developer ID Application|TeamIdentifier=|Timestamp=)' || true
    printf '%s\n' "${out}" | grep -q 'flags=.*runtime' || { echo "FAIL: hardened runtime is not on"; failed=1; }
    printf '%s\n' "${out}" | grep -q '^Authority=Developer ID Application' \
        || { echo "FAIL: not signed with a Developer ID Application identity"; failed=1; }

    ents="$(mktemp -t liquidvoice-ents)"
    codesign -d --entitlements - --xml "${app}" > "${ents}" 2>/dev/null || true
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' "${ents}" 2>/dev/null)" = "true" ]; then
        echo "Microphone entitlement present."
    else
        echo "FAIL: com.apple.security.device.audio-input missing"; failed=1
    fi
    if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "${ents}" >/dev/null 2>&1; then
        echo "FAIL: get-task-allow is set (notarization rejects it)"; failed=1
    fi
    rm -f "${ents}"

    if [ "${SKIP_NOTARIZE}" = "1" ]; then
        echo "-- Gatekeeper and stapler checks skipped: not notarized (LIQUIDVOICE_SKIP_NOTARIZE=1)."
        echo "   spctl, for reference (expected to say Unnotarized Developer ID):"
        spctl -a -vvv "${app}" 2>&1 | sed 's/^/   /' || true
    else
        echo "-- spctl -a -vvv ${app##*/}"
        spctl -a -vvv "${app}" 2>&1 || failed=1
        echo "-- xcrun stapler validate ${app##*/}"
        xcrun stapler validate "${app}" 2>&1 || failed=1
    fi

    if [ -n "${dmg}" ]; then
        [ -f "${dmg}" ] || die "no DMG at ${dmg}."
        echo "-- codesign --verify ${dmg##*/}"
        codesign --verify --strict --verbose=2 "${dmg}" 2>&1 || failed=1
        if [ "${SKIP_NOTARIZE}" != "1" ]; then
            echo "-- spctl -a -vvv -t install ${dmg##*/}"
            if ! spctl -a -vvv -t install "${dmg}" 2>&1; then
                echo "-- spctl -a -vvv -t open --context context:primary-signature ${dmg##*/}"
                spctl -a -vvv -t open --context context:primary-signature "${dmg}" 2>&1 || failed=1
            fi
            echo "-- xcrun stapler validate ${dmg##*/}"
            xcrun stapler validate "${dmg}" 2>&1 || failed=1
        fi
        echo "-- shasum -a 256"
        shasum -a 256 "${dmg}"
    fi

    [ "${failed}" -eq 0 ] || die "verification failed; see the lines marked above."
    echo "Verification passed."
}

# ---------------------------------------------------------------- package

run_package() {
    local source_app="${1:-${BUILT_APP}}"
    [ -d "${source_app}" ] || die "no built app at ${source_app}. Run scripts/release.sh build first, or pass the app's path."
    [ "$(plist_value "${source_app}/Contents/Info.plist" CFBundleIdentifier)" = "com.stage11.liquidvoice" ] \
        || die "${source_app} is not the Release app (com.stage11.liquidvoice)."

    resolve_identity
    check_notary_profile

    local version build app zip dmg
    version="$(app_version "${source_app}")"
    build="$(app_build "${source_app}")"
    [ -n "${version}" ] || die "cannot read CFBundleShortVersionString from ${source_app}."
    echo "Packaging Liquid Voice ${version} (${build})"

    mkdir -p "${DIST_DIR}"
    app="${DIST_DIR}/${APP_NAME}"
    zip="${DIST_DIR}/LiquidVoice-${version}-notarize.zip"
    dmg="${DIST_DIR}/LiquidVoice-${version}.dmg"

    # Work on a copy, so the build product is never modified.
    rm -rf "${app}"
    ditto "${source_app}" "${app}"

    step "Sign with Developer ID"
    sign_app "${app}"

    if [ "${SKIP_NOTARIZE}" != "1" ]; then
        step "Notarize the app"
        rm -f "${zip}"
        ditto -c -k --keepParent "${app}" "${zip}"
        notarize "${zip}"
        rm -f "${zip}"
        xcrun stapler staple "${app}" || die "stapling the app failed."
    fi

    step "Build the DMG"
    make_dmg "${app}" "${dmg}"

    if [ "${SKIP_NOTARIZE}" != "1" ]; then
        step "Notarize the DMG"
        notarize "${dmg}"
        xcrun stapler staple "${dmg}" || die "stapling the DMG failed."
    fi

    run_verify "${app}" "${dmg}"
    echo
    echo "Release artifact: ${dmg}"
    [ "${SKIP_NOTARIZE}" = "1" ] && echo "NOT notarized: for a signing check only, not for upload."
    return 0
}

case "${1:-all}" in
    all)
        # Check the credentials before a long build, not after it.
        resolve_identity
        check_notary_profile
        run_build
        run_package "${BUILT_APP}"
        ;;
    build)
        run_build
        ;;
    package)
        run_package "${2:-${BUILT_APP}}"
        ;;
    verify)
        run_verify "${2:-${DIST_DIR}/${APP_NAME}}" "${3:-}"
        ;;
    -h|--help|help)
        sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        die "unknown command: $1 (use all, build, package or verify)."
        ;;
esac
