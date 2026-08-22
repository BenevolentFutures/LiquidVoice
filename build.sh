#!/bin/bash

# FluidVoice Build Profile Router
# Defaults to the public OSS build, which skips private Fluid Intelligence.
#
# Usage:
#   ./build.sh                    # signed public OSS build (Debug)
#   ./build.sh public             # signed public OSS build (Debug)
#   ./build.sh unsigned           # unsigned public OSS build (CI/fallback)
#   ./build.sh fi                 # private FI build
#   ./build.sh release            # signed Release build -> "Liquid Voice.app"
#   ./build.sh install            # Release build, then install to /Applications

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${1:-${BUILD_PROFILE:-public}}"
PRIVATE_FI_BUILD_SCRIPT="${PROJECT_DIR}/build_with_FI_incremental.sh"
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
        build
    )

    cd "${PROJECT_DIR}"

    if [ "${signing_mode}" = "unsigned" ]; then
        echo "Running unsigned public FluidVoice build..."
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

    echo "Running signed public FluidVoice build..."
    echo "Build product: ${DERIVED_DATA_PATH}/Build/Products/Debug/FluidVoice Debug.app"
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
        build

    [ -d "${product}" ] || { printf >&2 'Build succeeded but %s is missing.\n' "${product}"; exit 1; }
    normalize_ctranscribe_framework "${product}" "${development_team}"
    echo "Build product: ${product}"

    if [ "${do_install}" != "install" ]; then
        return
    fi

    echo "Installing to /Applications/Liquid Voice.app ..."
    osascript -e 'quit app "Liquid Voice"' >/dev/null 2>&1 || true
    sleep 1
    rm -rf "/Applications/Liquid Voice.app"
    ditto "${product}" "/Applications/Liquid Voice.app"
    echo "Installed: /Applications/Liquid Voice.app"
    codesign -dv "/Applications/Liquid Voice.app" 2>&1 | grep -E 'Identifier|TeamIdentifier' || true
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
    fi|private|dev|full)
        if [ ! -x "${PRIVATE_FI_BUILD_SCRIPT}" ]; then
            echo "Private Fluid Intelligence build script is missing:"
            echo "  ${PRIVATE_FI_BUILD_SCRIPT}"
            echo "Restore the private FI build setup, then run: sh build_with_FI_incremental.sh"
            exit 1
        fi
        exec "${PRIVATE_FI_BUILD_SCRIPT}"
        ;;
    *)
        echo "Unknown build profile: ${PROFILE}"
        echo "Valid profiles: public/oss/incremental/fast, unsigned/ci, release, install, fi/private/dev/full"
        exit 1
        ;;
esac
