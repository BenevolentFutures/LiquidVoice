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

# The bundle identifier of an app bundle, or nothing.
bundle_id() {
    # PlistBuddy offers to create a missing file on stdout, so check first.
    [ -f "$1/Contents/Info.plist" ] || return 0
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

# Quits Liquid Voice and waits up to 10 s for it to go.
quit_liquid_voice() {
    osascript -e 'quit app "Liquid Voice"' >/dev/null 2>&1 || true
    local waited=0
    while pgrep -x "Liquid Voice" >/dev/null 2>&1; do
        if [ "${waited}" -ge 20 ]; then
            return 1
        fi
        sleep 0.5
        waited=$((waited + 1))
    done
}

# Writes <backup dir>/rollback.sh, which puts the backed-up app back with the same
# move-aside swap as install: nothing is removed until the backup copy is in place.
write_rollback_script() {
    local backup_dir="$1"
    local installed="$2"
    local backup_id="$3"
    cat > "${backup_dir}/rollback.sh" <<ROLLBACK
#!/bin/bash
# Puts back the Liquid Voice (${backup_id}) that ./build.sh install replaced. Its own settings
# and data were never changed, so it picks up where it was (without dictations made in the
# newer app).
set -euo pipefail
installed="${installed}"
backup="${backup_dir}/Liquid Voice.app"
staged="\${installed}.rollback"
replaced="\${installed}.replaced-\$(date +%Y%m%d-%H%M%S)"
osascript -e 'quit app "Liquid Voice"' >/dev/null 2>&1 || true
waited=0
while pgrep -x "Liquid Voice" >/dev/null 2>&1; do
    if [ "\${waited}" -ge 20 ]; then
        echo "Liquid Voice is still running. Quit it, then run this again. Nothing was changed." >&2
        exit 1
    fi
    sleep 0.5
    waited=\$((waited + 1))
done
rm -rf "\${staged}"
ditto "\${backup}" "\${staged}"
if [ ! -f "\${staged}/Contents/Info.plist" ] || \\
    [ "\$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "\${staged}/Contents/Info.plist")" != "${backup_id}" ]; then
    rm -rf "\${staged}"
    echo "The copy of the backup is incomplete. Nothing was changed." >&2
    exit 1
fi
if [ -e "\${installed}" ]; then
    mv "\${installed}" "\${replaced}"
fi
if ! mv "\${staged}" "\${installed}"; then
    if [ -e "\${replaced}" ] && mv "\${replaced}" "\${installed}"; then
        echo "Could not put the backup in place; the current app was left as it was." >&2
    else
        echo "Could not put the backup in place. The app that was installed is at \${replaced}; the backup is at \${backup}." >&2
    fi
    exit 1
fi
rm -rf "\${replaced}"
echo "Restored ${backup_id} to \${installed}."
open "\${installed}"
ROLLBACK
    chmod +x "${backup_dir}/rollback.sh"
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

# Installs the built app, keeping the one it replaces so one command brings it back. Nothing
# destructive happens before the backup is verified and the rollback command is printed, and
# the new app is copied next to the old one first, then swapped in with mv.
# LIQUIDVOICE_INSTALL_PATH, LIQUIDVOICE_BACKUP_ROOT, LIQUIDVOICE_DATA_DOMAIN and
# LIQUIDVOICE_DATA_FOLDER only exist to try this step on scratch folders.
install_app() {
    local product="$1"
    local installed="${LIQUIDVOICE_INSTALL_PATH:-/Applications/Liquid Voice.app}"
    local backup_root="${LIQUIDVOICE_BACKUP_ROOT:-${HOME}/Backups}"
    local data_domain="${LIQUIDVOICE_DATA_DOMAIN:-com.stage11.liquidvoice}"
    local data_folder="${LIQUIDVOICE_DATA_FOLDER:-${HOME}/Library/Application Support/LiquidVoice}"
    local staged="${installed}.new"
    local previous="${installed}.previous"
    local backup_dir=""
    local product_id installed_id=""

    product_id="$(bundle_id "${product}")"
    [ -n "${product_id}" ] || { printf >&2 'Cannot read the bundle ID of %s. Nothing was installed.\n' "${product}"; exit 1; }

    # An earlier install that stopped between its two moves leaves the old app at .previous.
    # Put it back (or, when an app is installed again, keep it in the backups); never delete it.
    if [ -e "${previous}" ]; then
        if [ ! -e "${installed}" ]; then
            echo "Found ${previous} from an interrupted install and no app at ${installed}: moving it back first."
            mv "${previous}" "${installed}"
        else
            local leftover
            leftover="${backup_root}/liquid-voice-leftover-$(date +%Y%m%d-%H%M%S)"
            mkdir -p "${leftover}"
            mv "${previous}" "${leftover}/Liquid Voice.app"
            echo "Kept a leftover ${previous} as ${leftover}/Liquid Voice.app."
        fi
    fi
    if [ -d "${installed}" ]; then
        installed_id="$(bundle_id "${installed}")"
    fi
    preflight_existing_identity_data "${product_id}" "${installed_id}" "${data_domain}" "${data_folder}"

    echo "Installing ${product_id} to ${installed} ..."
    # The running app must be gone before it is replaced (and before the new one migrates
    # its data), or it would keep writing its settings and hotkeys beside the new app.
    if ! quit_liquid_voice; then
        printf >&2 'Liquid Voice is still running after 10 s. Quit it, then run install again. Nothing was installed.\n'
        exit 1
    fi

    # Keep the app being replaced, verified, so one command brings it back.
    if [ -d "${installed}" ]; then
        backup_dir="${backup_root}/liquid-voice-$(date +%Y%m%d-%H%M%S)"
        # Two installs within one second must not share (and merge into) one backup.
        [ ! -e "${backup_dir}" ] || backup_dir="${backup_dir}-$$"
        mkdir -p "${backup_dir}"
        echo "Backing up the current app to ${backup_dir}/Liquid Voice.app ..."
        ditto "${installed}" "${backup_dir}/Liquid Voice.app"
        local backup_id
        backup_id="$(bundle_id "${backup_dir}/Liquid Voice.app")"
        if [ -z "${backup_id}" ] || [ "${backup_id}" != "${installed_id}" ]; then
            printf >&2 'The backup at %s has bundle ID "%s", not "%s". Nothing was installed.\n' \
                "${backup_dir}" "${backup_id}" "${installed_id}"
            exit 1
        fi
        if ! codesign --verify --deep --strict "${backup_dir}/Liquid Voice.app" >/dev/null 2>&1; then
            if codesign --verify --deep --strict "${installed}" >/dev/null 2>&1; then
                printf >&2 'The backup at %s fails codesign verification but the installed app passes. Nothing was installed.\n' "${backup_dir}"
                exit 1
            fi
            echo "Note: the installed app itself fails strict codesign verification; the backup is an exact copy of it."
        fi
        write_rollback_script "${backup_dir}" "${installed}" "${backup_id}"
        echo "Backed up ${backup_id}."
        echo "Rollback, if needed (restores the previous app; its own settings and data were never changed):"
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
    if [ -d "${installed}" ]; then
        mv "${installed}" "${previous}"
    fi
    if ! mv "${staged}" "${installed}"; then
        if [ -e "${previous}" ] && mv "${previous}" "${installed}"; then
            printf >&2 'Could not move the new app into place; the previous app was put back.\n'
        else
            printf >&2 'Could not move the new app into place, nor put the previous app back.\n'
            printf >&2 'The previous app is at %s. Move it back to %s, run install again (it moves it back first)' "${previous}" "${installed}"
            if [ -n "${backup_dir}" ]; then
                printf >&2 ', or run: bash "%s/rollback.sh"' "${backup_dir}"
            fi
            printf >&2 '.\n'
        fi
        exit 1
    fi
    rm -rf "${previous}"

    echo "Installed: ${installed}"
    codesign -dv "${installed}" 2>&1 | grep -E 'Identifier|TeamIdentifier' || true
    echo "Log: ~/Library/Logs/LiquidVoice/Fluid.log. After an identity change, follow docs/INSTALL-CHECKLIST.md."
    if [ -n "${backup_dir}" ]; then
        echo "Rollback: bash \"${backup_dir}/rollback.sh\""
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
