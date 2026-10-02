#!/bin/bash

# MouthKeys Build Profile Router
#
# Usage:
#   ./build.sh                    # signed Debug build
#   ./build.sh public             # signed Debug build
#   ./build.sh unsigned           # unsigned Debug build (CI/fallback)
#   ./build.sh release            # signed Release build -> "MouthKeys.app"
#   ./build.sh install            # Release build, back up the installed app, install to /Applications
#   ./build.sh dist               # Developer ID signed, notarized DMG in dist/ (scripts/release.sh)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE="${1:-${BUILD_PROFILE:-public}}"
DERIVED_DATA_PATH="${FLUIDVOICE_DERIVED_DATA_PATH:-${PROJECT_DIR}/DerivedData}"
# LIQUIDVOICE_DEVELOPMENT_TEAM picks the signing team; the older FLUIDVOICE_DEVELOPMENT_TEAM still works.
DEVELOPMENT_TEAM_OVERRIDE="${LIQUIDVOICE_DEVELOPMENT_TEAM:-${FLUIDVOICE_DEVELOPMENT_TEAM:-}}"

resolve_development_team() {
    local identity
    identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | awk 'NR == 1 { identity = $0 } END { print identity }')"
    [ -n "${identity}" ] || return 0

    if [ -n "${DEVELOPMENT_TEAM_OVERRIDE}" ]; then
        printf '%s\n' "${DEVELOPMENT_TEAM_OVERRIDE}"
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
        echo "Running unsigned MouthKeys Debug build..."
        echo "Accessibility permission may need to be granted again after rebuilding."
        exec xcodebuild "${build_args[@]}" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
    fi

    development_team="$(resolve_development_team)"
    if [ -z "${development_team}" ]; then
        if [ -n "${DEVELOPMENT_TEAM_OVERRIDE}" ]; then
            printf >&2 'LIQUIDVOICE_DEVELOPMENT_TEAM is set to %s, but no Apple Development signing identity was found.\n\n' \
                "${DEVELOPMENT_TEAM_OVERRIDE}"
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
teams, set LIQUIDVOICE_DEVELOPMENT_TEAM to the desired 10-character Team ID.

To build without signing instead, run:
  ./build.sh unsigned

Unsigned builds may require Accessibility permission again after rebuilding.
EOF
        exit 1
    fi

    echo "Running signed MouthKeys Debug build..."
    echo "Build product: ${DERIVED_DATA_PATH}/Build/Products/Debug/MouthKeys Debug.app"
    exec xcodebuild "${build_args[@]}" DEVELOPMENT_TEAM="${development_team}"
}

# True when an entitlements plist grants com.apple.security.device.audio-input.
has_audio_input_entitlement() {
    [ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.device.audio-input' "$1" 2>/dev/null)" = "true" ]
}

# Stops unless the signed app grants the microphone. Under the hardened runtime a
# missing com.apple.security.device.audio-input makes macOS deny the microphone
# silently: no prompt, and the app never appears in Privacy & Security > Microphone.
# Runs on every Release build, whether or not the CTranscribe layout needed fixing.
verify_audio_input_entitlement() {
    local app="$1"
    local entitlements
    entitlements="$(mktemp -t liquidvoice-entitlements)"
    if codesign -d --entitlements - --xml "${app}" > "${entitlements}" 2>/dev/null \
        && has_audio_input_entitlement "${entitlements}"; then
        rm -f "${entitlements}"
        echo "Microphone entitlement present."
        return 0
    fi
    rm -f "${entitlements}"
    printf >&2 '%s lacks com.apple.security.device.audio-input; the microphone would be denied. Stopping.\n' "${app}"
    return 1
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

    # Re-sign with the entitlements Xcode signed the app with, not the bare
    # Fluid.entitlements file. Xcode adds the hardened-runtime resource entitlements
    # (ENABLE_RESOURCE_ACCESS_AUDIO_INPUT -> com.apple.security.device.audio-input) at
    # build time; without that one, macOS denies the microphone silently: no prompt,
    # and the app never appears in Privacy & Security > Microphone.
    local entitlements
    entitlements="$(mktemp -t liquidvoice-entitlements)"
    if ! codesign -d --entitlements - --xml "${app}" > "${entitlements}" 2>/dev/null; then
        printf >&2 'Could not read entitlements from the Xcode-signed app. Stopping.\n'
        rm -f "${entitlements}"
        return 1
    fi
    if ! has_audio_input_entitlement "${entitlements}"; then
        printf >&2 'The built app lacks com.apple.security.device.audio-input; the microphone would be denied. Stopping.\n'
        rm -f "${entitlements}"
        return 1
    fi

    if ! codesign --force --sign "${identity}" --timestamp=none "${fw}" \
        || ! codesign --force --sign "${identity}" --timestamp=none \
            --entitlements "${entitlements}" --options runtime "${app}"; then
        printf >&2 'Re-signing after the CTranscribe layout fix failed. Stopping.\n'
        rm -f "${entitlements}"
        return 1
    fi
    rm -f "${entitlements}"

    if codesign --verify --deep --strict "${app}"; then
        echo "Signature verified."
    else
        printf >&2 'Warning: signature still does not verify after normalization.\n'
    fi
}

# The bundle identifier of an app bundle, or nothing.
bundle_id() {
    # PlistBuddy offers to create a missing file on stdout, so check first.
    [ -f "$1/Contents/Info.plist" ] || return 0
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}


# The app was called Liquid Voice until 2026-10-02 and installed as "Liquid Voice.app". It keeps
# its bundle ID, so two copies in /Applications would confuse LaunchServices and the login item:
# install backs the old one up with everything else it replaces, then takes it out.
LEGACY_APP_NAME="Liquid Voice.app"
# Process names of the installed app, current and legacy.
APP_PROCESS_NAMES=("MouthKeys" "Liquid Voice")

# True while any copy of the app (MouthKeys or the older Liquid Voice) is running.
app_is_running() {
    local name
    for name in "${APP_PROCESS_NAMES[@]}"; do
        if pgrep -x "${name}" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

# Quits every running copy of the app and waits up to 10 s for them to go. Only a running
# process is asked to quit, so this never launches anything.
quit_running_app() {
    local name
    for name in "${APP_PROCESS_NAMES[@]}"; do
        if pgrep -x "${name}" >/dev/null 2>&1; then
            osascript -e "quit app \"${name}\"" >/dev/null 2>&1 || true
        fi
    done
    local waited=0
    while app_is_running; do
        if [ "${waited}" -ge 20 ]; then
            return 1
        fi
        sleep 0.5
        waited=$((waited + 1))
    done
}

# Writes <backup dir>/rollback.sh, which puts every backed-up app back where it was with the
# same move-aside swap as install: nothing is removed until the backup copies are in place.
# Arguments: backup dir, install path, 1 when nothing was at the install path before (the new
# app then comes out after the restore), then one "<backup copy>|<original path>|<bundle ID>"
# entry per backed-up app.
write_rollback_script() {
    local backup_dir="$1"
    local installed="$2"
    local remove_new="$3"
    shift 3
    local script="${backup_dir}/rollback.sh"
    local entry
    {
        echo '#!/bin/bash'
        echo "# Puts back the app(s) that ./build.sh install replaced on $(date '+%Y-%m-%d %H:%M'). Their own"
        echo '# settings and data were never changed, so they pick up where they were (without'
        echo '# dictations made in the newer app).'
        echo 'set -euo pipefail'
        printf 'installed=%q\n' "${installed}"
        printf 'remove_new=%q\n' "${remove_new}"
        printf 'process_names=(%q %q)\n' "${APP_PROCESS_NAMES[@]}"
        echo 'restores=()'
        for entry in "$@"; do
            printf 'restores+=(%q)\n' "${entry}"
        done
        cat <<'ROLLBACK'
stamp="$(date +%Y%m%d-%H%M%S)"
running() {
    local name
    for name in "${process_names[@]}"; do
        pgrep -x "${name}" >/dev/null 2>&1 && return 0
    done
    return 1
}
for name in "${process_names[@]}"; do
    if pgrep -x "${name}" >/dev/null 2>&1; then
        osascript -e "quit app \"${name}\"" >/dev/null 2>&1 || true
    fi
done
waited=0
while running; do
    if [ "${waited}" -ge 20 ]; then
        echo "The app is still running. Quit it, then run this again. Nothing was changed." >&2
        exit 1
    fi
    sleep 0.5
    waited=$((waited + 1))
done

# Copy every backup next to where it goes and check it before anything is moved.
for entry in "${restores[@]}"; do
    IFS='|' read -r backup target id <<< "${entry}"
    rm -rf "${target}.rollback"
    ditto "${backup}" "${target}.rollback"
    if [ ! -f "${target}.rollback/Contents/Info.plist" ] || \
        [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${target}.rollback/Contents/Info.plist")" != "${id}" ]; then
        for staged_entry in "${restores[@]}"; do
            IFS='|' read -r _ staged_target _ <<< "${staged_entry}"
            rm -rf "${staged_target}.rollback"
        done
        echo "The copy of ${backup} is incomplete. Nothing was changed." >&2
        exit 1
    fi
done

# Swap each one in.
replaced=()
restored=()
for entry in "${restores[@]}"; do
    IFS='|' read -r backup target id <<< "${entry}"
    if [ -e "${target}" ]; then
        mv "${target}" "${target}.replaced-${stamp}"
        replaced+=("${target}.replaced-${stamp}")
    fi
    if ! mv "${target}.rollback" "${target}"; then
        if [ -e "${target}.replaced-${stamp}" ] && mv "${target}.replaced-${stamp}" "${target}"; then
            echo "Could not put ${backup} back at ${target}; what was there was left as it was." >&2
        else
            echo "Could not put ${backup} back at ${target}. What was there is at ${target}.replaced-${stamp}." >&2
        fi
        if [ "${#restored[@]}" -gt 0 ]; then
            echo "Already restored: ${restored[*]}" >&2
        fi
        exit 1
    fi
    restored+=("${target}")
    echo "Restored ${id} to ${target}."
done

# Nothing was at the install path before the install, so the app it added comes out too.
if [ "${remove_new}" = "1" ] && [ -e "${installed}" ]; then
    case " ${restored[*]} " in
        *" ${installed} "*) ;;
        *)
            mv "${installed}" "${installed}.replaced-${stamp}"
            replaced+=("${installed}.replaced-${stamp}")
            echo "Took out ${installed}, which the install had added."
            ;;
    esac
fi
if [ "${#replaced[@]}" -gt 0 ]; then
    rm -rf "${replaced[@]}"
fi
open "${restored[0]}"
ROLLBACK
    } > "${script}"
    chmod +x "${script}"
}

# Before the first install of a new bundle identifier: the new app copies FluidVoice-era data
# once, on its first launch. Preferences or a folder already under the new identity (a stray
# Release run, an earlier install) mean that copy would be skipped or merged into them.
preflight_existing_identity_data() {
    local product_id="$1"
    local installed_id="$2"
    local data_domain="$3"
    local data_folder="$4"
    [ "${installed_id}" != "${product_id}" ] || return 0

    local found=""
    if defaults read "${data_domain}" >/dev/null 2>&1; then
        found="${found}  - preferences: ${data_domain}"
        if defaults read "${data_domain}" LiquidVoiceIdentityMigrationDefaults >/dev/null 2>&1; then
            found="${found} (migration already marked done: it will NOT copy your data again)"
        fi
        found="${found}"$'\n'
    fi
    if [ -e "${data_folder}" ]; then
        found="${found}  - folder: ${data_folder}"$'\n'
    fi
    [ -n "${found}" ] || return 0

    local stamp
    stamp="$(date +%Y%m%d-%H%M%S)"
    cat >&2 <<WARN

First install of ${product_id} (the installed app is ${installed_id:-none}), but data for it already exists:
${found}
On its first launch the new app copies your FluidVoice-era settings, history, dictionary and
folder once. With data already there, that copy is skipped or merged into it. To start clean,
move it aside first:
  defaults export ${data_domain} ~/Backups/${data_domain}-${stamp}.plist && defaults delete ${data_domain}
  mv "${data_folder}" ~/Backups/LiquidVoice-folder-${stamp}

WARN
    if [ "${LIQUIDVOICE_ALLOW_EXISTING_DATA:-}" = "1" ]; then
        echo "Continuing anyway (LIQUIDVOICE_ALLOW_EXISTING_DATA=1)." >&2
        return 0
    fi
    if [ ! -t 0 ]; then
        echo "Not interactive, so stopping. Nothing was installed. Set LIQUIDVOICE_ALLOW_EXISTING_DATA=1 to continue anyway." >&2
        exit 1
    fi
    local answer=""
    read -r -p "Type 'install' to install anyway; anything else stops: " answer
    if [ "${answer}" != "install" ]; then
        echo "Stopped. Nothing was installed." >&2
        exit 1
    fi
}

# An earlier install that stopped between its moves leaves an app it was replacing at
# <path>.previous. Put it back when no app is installed at any of the given paths; otherwise
# keep it in the backups. Never delete it.
recover_previous() {
    local target="$1"
    local backup_root="$2"
    shift 2
    local previous="${target}.previous"
    [ -e "${previous}" ] || return 0

    local other present=""
    for other in "$@"; do
        if [ -n "${other}" ] && [ -e "${other}" ]; then
            present=1
        fi
    done
    if [ -z "${present}" ]; then
        echo "Found ${previous} from an interrupted install and no app installed: moving it back first."
        mv "${previous}" "${target}"
    else
        local leftover
        leftover="${backup_root}/liquid-voice-leftover-$(date +%Y%m%d-%H%M%S)-$$"
        mkdir -p "${leftover}"
        mv "${previous}" "${leftover}/$(basename "${target}")"
        echo "Kept a leftover ${previous} as ${leftover}/$(basename "${target}")."
    fi
}

# Copies an installed app into the backup folder and checks the copy. Prints the rollback
# entry ("<backup copy>|<original path>|<bundle ID>") on success; stops the install otherwise.
backup_app() {
    local source="$1"
    local backup_dir="$2"
    local copy
    copy="${backup_dir}/$(basename "${source}")"
    local source_id backup_id
    source_id="$(bundle_id "${source}")"
    echo "Backing up ${source} to ${copy} ..." >&2
    ditto "${source}" "${copy}"
    backup_id="$(bundle_id "${copy}")"
    if [ -z "${backup_id}" ] || [ "${backup_id}" != "${source_id}" ]; then
        printf >&2 'The backup at %s has bundle ID "%s", not "%s". Nothing was installed.\n' \
            "${copy}" "${backup_id}" "${source_id}"
        exit 1
    fi
    if ! codesign --verify --deep --strict "${copy}" >/dev/null 2>&1; then
        if codesign --verify --deep --strict "${source}" >/dev/null 2>&1; then
            printf >&2 'The backup at %s fails codesign verification but %s passes. Nothing was installed.\n' \
                "${copy}" "${source}"
            exit 1
        fi
        echo "Note: ${source} itself fails strict codesign verification; the backup is an exact copy of it." >&2
    fi
    echo "Backed up ${backup_id}." >&2
    printf '%s|%s|%s\n' "${copy}" "${source}" "${backup_id}"
}

# Installs the built app, keeping what it replaces so one command brings it back. Nothing
# destructive happens before the backups are verified and the rollback command is printed, and
# the new app is copied next to the old one first, then swapped in with mv. An older
# "Liquid Voice.app" beside it is backed up the same way and taken out in the same swap.
# LIQUIDVOICE_INSTALL_PATH, LIQUIDVOICE_LEGACY_INSTALL_PATH, LIQUIDVOICE_BACKUP_ROOT,
# LIQUIDVOICE_DATA_DOMAIN and LIQUIDVOICE_DATA_FOLDER only exist to try this step on scratch folders.
install_app() {
    local product="$1"
    local installed="${LIQUIDVOICE_INSTALL_PATH:-/Applications/MouthKeys.app}"
    local legacy="${LIQUIDVOICE_LEGACY_INSTALL_PATH:-$(dirname "${installed}")/${LEGACY_APP_NAME}}"
    local backup_root="${LIQUIDVOICE_BACKUP_ROOT:-${HOME}/Backups}"
    local data_domain="${LIQUIDVOICE_DATA_DOMAIN:-com.stage11.liquidvoice}"
    local data_folder="${LIQUIDVOICE_DATA_FOLDER:-${HOME}/Library/Application Support/LiquidVoice}"
    local staged="${installed}.new"
    local previous="${installed}.previous"
    local legacy_previous=""
    local backup_dir=""
    local product_id installed_id=""

    [ "${legacy}" != "${installed}" ] || legacy=""
    [ -z "${legacy}" ] || legacy_previous="${legacy}.previous"

    product_id="$(bundle_id "${product}")"
    [ -n "${product_id}" ] || { printf >&2 'Cannot read the bundle ID of %s. Nothing was installed.\n' "${product}"; exit 1; }

    recover_previous "${installed}" "${backup_root}" "${installed}" "${legacy}"
    if [ -n "${legacy}" ]; then
        recover_previous "${legacy}" "${backup_root}" "${installed}" "${legacy}"
    fi
    if [ -d "${installed}" ]; then
        installed_id="$(bundle_id "${installed}")"
    elif [ -n "${legacy}" ] && [ -d "${legacy}" ]; then
        installed_id="$(bundle_id "${legacy}")"
    fi
    preflight_existing_identity_data "${product_id}" "${installed_id}" "${data_domain}" "${data_folder}"

    echo "Installing ${product_id} to ${installed} ..."
    # The running app must be gone before it is replaced (and before the new one migrates
    # its data), or it would keep writing its settings and hotkeys beside the new app.
    if ! quit_running_app; then
        printf >&2 'The app is still running after 10 s. Quit it, then run install again. Nothing was installed.\n'
        exit 1
    fi

    # Keep every app being replaced, verified, so one command brings them back.
    local had_installed="" had_legacy="" remove_new=1
    [ ! -d "${installed}" ] || had_installed=1
    [ -z "${legacy}" ] || [ ! -d "${legacy}" ] || had_legacy=1
    if [ -n "${had_installed}" ] || [ -n "${had_legacy}" ]; then
        backup_dir="${backup_root}/liquid-voice-$(date +%Y%m%d-%H%M%S)"
        # Two installs within one second must not share (and merge into) one backup.
        [ ! -e "${backup_dir}" ] || backup_dir="${backup_dir}-$$"
        mkdir -p "${backup_dir}"
        local -a restores=()
        local entry
        if [ -n "${had_installed}" ]; then
            entry="$(backup_app "${installed}" "${backup_dir}")"
            restores+=("${entry}")
            remove_new=0
        fi
        if [ -n "${had_legacy}" ]; then
            entry="$(backup_app "${legacy}" "${backup_dir}")"
            restores+=("${entry}")
        fi
        write_rollback_script "${backup_dir}" "${installed}" "${remove_new}" "${restores[@]}"
        echo "Rollback, if needed (restores what was installed; its own settings and data were never changed):"
        echo "  bash \"${backup_dir}/rollback.sh\""
    fi

    # Copy next to the installed app, check it, then swap it in.
    rm -rf "${staged}"
    ditto "${product}" "${staged}"
    if [ "$(bundle_id "${staged}")" != "${product_id}" ]; then
        rm -rf "${staged}"
        printf >&2 'The copy at %s is incomplete. The installed app was not touched.\n' "${staged}"
        exit 1
    fi
    if [ -n "${had_installed}" ]; then
        mv "${installed}" "${previous}"
    fi
    if [ -n "${had_legacy}" ] && ! mv "${legacy}" "${legacy_previous}"; then
        if [ -n "${had_installed}" ]; then
            mv "${previous}" "${installed}" || true
        fi
        rm -rf "${staged}"
        printf >&2 'Could not move %s aside. Nothing was installed.\n' "${legacy}"
        exit 1
    fi
    if ! mv "${staged}" "${installed}"; then
        local put_back=1
        if [ -n "${had_installed}" ] && ! mv "${previous}" "${installed}"; then
            put_back=""
        fi
        if [ -n "${had_legacy}" ] && ! mv "${legacy_previous}" "${legacy}"; then
            put_back=""
        fi
        if [ -n "${put_back}" ]; then
            printf >&2 'Could not move the new app into place; the previous app was put back.\n'
        else
            printf >&2 'Could not move the new app into place, nor put the previous app back.\n'
            printf >&2 'It is at %s. Move it back, run install again (it moves it back first)' \
                "$([ -e "${previous}" ] && echo "${previous}" || echo "${legacy_previous}")"
            if [ -n "${backup_dir}" ]; then
                printf >&2 ', or run: bash "%s/rollback.sh"' "${backup_dir}"
            fi
            printf >&2 '.\n'
        fi
        exit 1
    fi
    rm -rf "${previous}"
    if [ -n "${had_legacy}" ]; then
        rm -rf "${legacy_previous}"
        echo "Took out the old ${legacy}; its backup is in ${backup_dir}. Settings carry over (same bundle ID)."
    fi

    echo "Installed: ${installed}"
    codesign -dv "${installed}" 2>&1 | grep -E 'Identifier|TeamIdentifier' || true
    warn_other_registered_copies "${installed}"
    echo "Next: open MouthKeys, grant Microphone and Accessibility when asked (System Settings > Privacy & Security), pick a speech model, then try a dictation."
    echo "Log: ~/Library/Logs/LiquidVoice/Fluid.log. (docs/INSTALL-CHECKLIST.md is the maintainer's own post-install checklist; you do not need it.)"
    if [ -n "${backup_dir}" ]; then
        echo "Rollback: bash \"${backup_dir}/rollback.sh\""
    fi
}

# Other copies of the installed bundle ID signed by someone else (the Trash, SwiftUI drag caches,
# DerivedData Release builds, old backups) can poison the Accessibility grant: System Settings may
# record one of their code requirements, and the switch then shows on but never matches the
# installed app (2026-10-02). Read-only: lists them, never deletes.
warn_other_registered_copies() {
    local installed="$1"
    local bundle_id
    bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${installed}/Contents/Info.plist" 2>/dev/null)" || return 0
    local others
    others="$({
        mdfind "kMDItemCFBundleIdentifier == '${bundle_id}'" 2>/dev/null
        for candidate in "${HOME}"/.Trash/*.app "${HOME}"/Library/Caches/com.apple.SwiftUI.Drag-*/*.app; do
            [ -d "${candidate}" ] || continue
            [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${candidate}/Contents/Info.plist" 2>/dev/null)" = "${bundle_id}" ] && echo "${candidate}"
        done
    } | grep -v -x -F "${installed}" | sort -u)"
    [ -n "${others}" ] || return 0
    local signer
    signer="$(codesign -dv "${installed}" 2>&1 | grep -m1 '^Authority=' || echo unsigned)"
    local conflicting=""
    local copy
    while IFS= read -r copy; do
        [ -d "${copy}" ] || continue
        if [ "$(codesign -dv "${copy}" 2>&1 | grep -m1 '^Authority=' || echo unsigned)" != "${signer}" ]; then
            conflicting="${conflicting}  ${copy}"$'\n'
        fi
    done <<< "${others}"
    [ -n "${conflicting}" ] || return 0
    echo "Other copies of ${bundle_id}, signed by someone else, are on this Mac. They can keep Accessibility"
    echo "from matching the installed app. Delete them (and empty the Trash), then switch MouthKeys off and on:"
    printf '%s' "${conflicting}"
}

run_release_build() {
    local do_install="$1"
    local development_team
    local product="${DERIVED_DATA_PATH}/Build/Products/Release/MouthKeys.app"

    cd "${PROJECT_DIR}"

    development_team="$(resolve_development_team)"
    if [ -z "${development_team}" ]; then
        printf >&2 'No Apple Development signing identity was found.\n'
        printf >&2 'Set LIQUIDVOICE_DEVELOPMENT_TEAM or add an account in Xcode > Settings > Accounts.\n'
        exit 1
    fi

    echo "Running signed Release build of MouthKeys..."
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
    verify_audio_input_entitlement "${product}"
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
    dist)
        exec "${PROJECT_DIR}/scripts/release.sh" all
        ;;
    *)
        echo "Unknown build profile: ${PROFILE}"
        echo "Valid profiles: public/oss/incremental/fast, unsigned/ci, release, install, dist"
        exit 1
        ;;
esac
