#!/bin/bash

# Liquid Voice Build Profile Router
#
# Usage:
#   ./build.sh                    # signed Debug build
#   ./build.sh public             # signed Debug build
#   ./build.sh unsigned           # unsigned Debug build (CI/fallback)
#   ./build.sh release            # signed Release build -> "Liquid Voice.app"
#   ./build.sh install            # Release build, back up the installed app, install to /Applications

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${1:-${BUILD_PROFILE:-public}}"
DERIVED_DATA_PATH="${FLUIDVOICE_DERIVED_DATA_PATH:-${PROJECT_DIR}/DerivedData}"

resolve_development_team() {
    local identity
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | awk 'NR == 1 { identity = $0 } END { print identity }')"
    [ -n "${identity}" ] || return 0

    if [ -n "${FLUIDVOICE_DEVELOPMENT_TEAM:-}" ]; then
        printf '%s\n' "${FLUIDVOICE_DEVELOPMENT_TEAM}"
        return
    fi

    security find-certificate -c "${identity}" -p 2>/dev/null \
        | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null \
        | sed -n 's/.*OU=\([^,]*\).*/\1/p'
}

run_public_build() {
    local signing_mode="$1"
    local development_team
    local -a build_args=(
        -project Fluid.xcodeproj
        -scheme Fluid
        -configuration Debug
        -destination 'platform=macOS'
        -derivedDataPath "${DERIVED_DATA_PATH}"
        SDK_STAT_CACHE_ENABLE=NO
        build
    )

    cd "${PROJECT_DIR}"

    if [ "${signing_mode}" = "unsigned" ]; then
        echo "Running unsigned Liquid Voice Debug build..."
        echo "Accessibility permission may need to be granted again after rebuilding."
        exec xcodebuild "${build_args[@]}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
    fi

    development_team="$(resolve_development_team)"
    if [ -z "${development_team}" ]; then
        if [ -n "${FLUIDVOICE_DEVELOPMENT_TEAM:-}" ]; then
            printf >&2 'FLUIDVOICE_DEVELOPMENT_TEAM is set to %s, but no Apple Development signing identity was found.\n\n' \
                "${FLUIDVOICE_DEVELOPMENT_TEAM}"
            printf >&2 '%s\n\n' \
                "The team override selects an installed signing identity; it does not replace a certificate."
        else
            printf >&2 'No Apple Development signing identity was found.\n\n'
        fi

        cat >&2 <<'EOF'
For stable Accessibility permission across rebuilds, add any Apple Account in:
  Xcode > Settings > Accounts

Then open Manage Certificates and create an Apple Development certificate.

A free Personal Team is sufficient for local development. If you have multiple
teams, set FLUIDVOICE_DEVELOPMENT_TEAM to the desired 10-character Team ID.

To build without signing instead, run:
  ./build.sh unsigned

Unsigned builds may require Accessibility permission again after rebuilding.
EOF
        exit 1
    fi

    echo "Running signed Liquid Voice Debug build..."
    echo "Build product: ${DERIVED_DATA_PATH}/Build/Products/Debug/Liquid Voice Debug.app"
    exec xcodebuild "${build_args[@]}" DEVELOPMENT_TEAM="${development_team}"
}

# The vendored CTranscribe.xcframework (altic-dev/transcribe-cpp-swift) ships a
# malformed versioned-framework layout: Versions/Current is a real directory and
# the top-level entries are copies, not symlinks. codesign then seals three
# divergent copies of the binary and every signature check fails with
# "a sealed resource is missing or invalid" -- which puts Accessibility
# permission at risk. Normalize to the canonical layout and re-sign.
normalize_ctranscribe_framework() {
    local app="$1"
    local team="$2"
    local fw="${app}/Contents/Frameworks/CTranscribe.framework"

    [ -d "${fw}" ] || return 0
    [ -L "${fw}/Versions/Current" ] && return 0   # already canonical

    echo "Normalizing CTranscribe.framework layout..."

    # Versions/Current holds Xcode's processed+signed slice; make it the real A.
    rm -rf "${fw}/Versions/A"
    mv "${fw}/Versions/Current" "${fw}/Versions/A"
    ln -s "A" "${fw}/Versions/Current"

    # Top-level entries become symlinks into Versions/Current.
    local entry
    for entry in CTranscribe Resources Headers Modules; do
        if [ -e "${fw}/${entry}" ] && [ ! -L "${fw}/${entry}" ]; then
            rm -rf "${fw}/${entry}"
        fi
        if [ -e "${fw}/Versions/Current/${entry}" ]; then
            ln -sfn "Versions/Current/${entry}" "${fw}/${entry}"
        fi
    done

    local identity
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
    [ -n "${identity}" ] || { printf >&2 'No signing identity for re-sign.\n'; return 1; }

    codesign --force --sign "${identity}" --timestamp=none "${fw}"
    codesign --force --sign "${identity}" --timestamp=none \
        --entitlements Fluid.entitlements --options runtime "${app}"

    if codesign --verify --deep --strict "${app}"; then
        echo "Signature verified."
    else
        printf >&2 'Warning: signature still does not verify after normalization.\n'
    fi
}

# Installs the built app, keeping the one it replaces so one command brings it back.
# LIQUIDVOICE_INSTALL_PATH and LIQUIDVOICE_BACKUP_ROOT only exist to try this step on scratch
# folders; the defaults are /Applications/Liquid Voice.app and ~/Backups.
install_app() {
    local product="$1"
    local installed="${LIQUIDVOICE_INSTALL_PATH:-/Applications/Liquid Voice.app}"
    local backup_root="${LIQUIDVOICE_BACKUP_ROOT:-${HOME}/Backups}"
    local backup_dir=""

    echo "Installing to ${installed} ..."
    osascript -e 'quit app "Liquid Voice"' >/dev/null 2>&1 || true
    sleep 1

    # Keep the app being replaced, so one command brings it back.
    if [ -d "${installed}" ]; then
        backup_dir="${backup_root}/liquid-voice-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "${backup_dir}"
        echo "Backing up the current app to ${backup_dir}/Liquid Voice.app ..."
        ditto "${installed}" "${backup_dir}/Liquid Voice.app"
        local installed_id backup_id
        installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${installed}/Contents/Info.plist" 2>/dev/null || true)"
        backup_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${backup_dir}/Liquid Voice.app/Contents/Info.plist" 2>/dev/null || true)"
        if [ -z "${backup_id}" ] || [ "${backup_id}" != "${installed_id}" ]; then
            printf >&2 'The backup at %s looks incomplete; nothing was installed.\n' "${backup_dir}"
            exit 1
        fi
        echo "Backed up ${backup_id}."
    fi

    rm -rf "${installed}"
    ditto "${product}" "${installed}"
    echo "Installed: ${installed}"
    codesign -dv "${installed}" 2>&1 | grep -E 'Identifier|TeamIdentifier' || true
    echo "Log: ~/Library/Logs/LiquidVoice/Fluid.log. After an identity change, follow docs/INSTALL-CHECKLIST.md."

    if [ -n "${backup_dir}" ]; then
        echo "Rollback to the previous app (its own settings and data were left untouched):"
        printf '  osascript -e %s; sleep 1; rm -rf "%s" && ditto "%s" "%s" && open "%s"\n' \
            "'quit app \"Liquid Voice\"'" "${installed}" "${backup_dir}/Liquid Voice.app" "${installed}" "${installed}"
    fi
}

run_release_build() {
    local do_install="$1"
    local development_team
    local product="${DERIVED_DATA_PATH}/Build/Products/Release/Liquid Voice.app"

    cd "${PROJECT_DIR}"

    development_team="$(resolve_development_team)"
    if [ -z "${development_team}" ]; then
        printf >&2 'No Apple Development signing identity was found.\n'
        printf >&2 'Set FLUIDVOICE_DEVELOPMENT_TEAM or add an account in Xcode > Settings > Accounts.\n'
        exit 1
    fi

    echo "Running signed Release build of Liquid Voice..."
    xcodebuild \
        -project Fluid.xcodeproj \
        -scheme Fluid \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        DEVELOPMENT_TEAM="${development_team}" \
        SDK_STAT_CACHE_ENABLE=NO \
        build

    [ -d "${product}" ] || { printf >&2 'Build succeeded but %s is missing.\n' "${product}"; exit 1; }
    normalize_ctranscribe_framework "${product}" "${development_team}"
    echo "Build product: ${product}"

    if [ "${do_install}" != "install" ]; then
        return
    fi

    install_app "${product}"
}

case "${PROFILE}" in
    public|oss|incremental|fast)
        run_public_build signed
        ;;
    unsigned|ci)
        run_public_build unsigned
        ;;
    release)
        run_release_build build
        ;;
    install)
        run_release_build install
        ;;
    *)
        echo "Unknown build profile: ${PROFILE}"
        echo "Valid profiles: public/oss/incremental/fast, unsigned/ci, release, install"
        exit 1
        ;;
esac
