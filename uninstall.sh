#!/usr/bin/env bash

set -euo pipefail

APP_NAME="ctfbar"
VERSION="1.0.1"

CONFIG_DIR="$HOME/.config/ctfbar"
BACKUP_DIR="$CONFIG_DIR/backups"
STATE_FILE="$CONFIG_DIR/state"
ZSHRC="$HOME/.zshrc"

# ============================================================
# Runtime state
# ============================================================

PANEL_ID=""

ORIGINAL_PLUGIN_IDS=()
NEW_PLUGIN_IDS=()
CTFBAR_PLUGIN_IDS=()

PANEL_MODIFIED=false

# ============================================================
# Output helpers
# ============================================================

info() {
    echo "[+] $*"
}

warn() {
    echo "[!] $*"
}

error() {
    echo "[X] $*" >&2
    exit 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# Environment
# ============================================================

check_environment() {

    if [ -z "${HOME:-}" ]; then
        error "Could not determine HOME."
    fi

    if ! command_exists xfconf-query; then
        error "xfconf-query is not available."
    fi

    if ! command_exists xfce4-panel; then
        error "xfce4-panel is not available."
    fi

    if ! command_exists python3; then
        error "Python3 is required to manage .zshrc."
    fi
}

# ============================================================
# State
# ============================================================

if [ ! -f "$STATE_FILE" ]; then
    error "CTFBar is not installed."
fi

# shellcheck disable=SC1090
source "$STATE_FILE"

# ============================================================
# Validate state
# ============================================================

required_state=(
    PANEL_ID
    SEPARATOR1_ID
    INFO_ID
    SEPARATOR2_ID
    TARGET_ID
    SEPARATOR3_ID
)

for variable in "${required_state[@]}"; do

    if [ -z "${!variable:-}" ]; then
        error "The state file is incomplete: $variable is missing."
    fi

done

PANEL_ID="$PANEL_ID"

CTFBAR_PLUGIN_IDS=(
    "$SEPARATOR1_ID"
    "$INFO_ID"
    "$SEPARATOR2_ID"
    "$TARGET_ID"
    "$SEPARATOR3_ID"
)

# ============================================================
# Panel helpers
# ============================================================

PANEL_PATH="/panels/panel-$PANEL_ID/plugin-ids"

get_plugin_ids() {

    local panel="$1"
    local property="/panels/panel-$panel/plugin-ids"
    local raw

    # --------------------------------------------------------
    # IMPORTANT:
    # NEVER create the property while reading it.
    # If it does not exist, abort safely.
    # --------------------------------------------------------

    if ! raw=$(
        xfconf-query \
            -c xfce4-panel \
            -p "$property" \
            2>/dev/null
    ); then

        error \
            "Could not read $property. " \
            "The uninstall process will stop without modifying the panel."
    fi

    local ids

    mapfile -t ids < <(
        printf '%s\n' "$raw" |
        sed \
            -n \
            '/^Value is an array with [0-9][0-9]* items:$/,$p' |
        tail -n +2 |
        grep -E '^[0-9]+$' || true
    )

    if [ "${#ids[@]}" -eq 0 ]; then

        error \
            "The $property property exists but does not contain valid IDs. " \
            "The uninstall process will stop for safety."
    fi

    printf '%s\n' "${ids[@]}"
}

write_plugin_ids() {

    local panel="$1"
    shift

    local ids=("$@")
    local args=()
    local id

    if [ "${#ids[@]}" -eq 0 ]; then
        error "The new plugin-ids array cannot be empty."
    fi

    for id in "${ids[@]}"; do

        if ! [[ "$id" =~ ^[0-9]+$ ]]; then
            error "Invalid plugin ID: $id"
        fi

        args+=(
            "-t" "int"
            "-s" "$id"
        )
    done

    # --------------------------------------------------------
    # IMPORTANT:
    #
    # -n creates the property if it does not exist.
    # NEVER use:
    #
    #     xfconf-query ... -r
    #
    # because that deletes the entire plugin-ids property.
    # --------------------------------------------------------

    xfconf-query \
        -c xfce4-panel \
        -p "/panels/panel-$panel/plugin-ids" \
        -n \
        -a \
        "${args[@]}"
}

verify_plugin_ids() {

    local panel="$1"
    shift

    local expected=("$@")
    local actual=()

    mapfile -t actual < <(
        get_plugin_ids "$panel"
    )

    if [ "${#actual[@]}" -ne "${#expected[@]}" ]; then

        error \
            "The plugin-ids array verification failed: " \
            "expected ${#expected[@]} elements, but got ${#actual[@]}."
    fi

    local i

    for i in "${!expected[@]}"; do

        if [ "${actual[$i]}" != "${expected[$i]}" ]; then

            error \
                "The panel verification failed at position $i: " \
                "expected ${expected[$i]}, got ${actual[$i]}."
        fi
    done
}

# ============================================================
# Validate CTFBar plugins
# ============================================================

verify_ctfbar_plugins_present() {

    local id
    local found

    for id in "${CTFBAR_PLUGIN_IDS[@]}"; do

        found=false

        for current in "${ORIGINAL_PLUGIN_IDS[@]}"; do

            if [ "$current" = "$id" ]; then
                found=true
                break
            fi
        done

        if [ "$found" = false ]; then

            error \
                "CTFBar plugin-$id is not present in plugin-ids. " \
                "The uninstall process will stop to avoid modifying the panel."
        fi
    done

    info "All 5 CTFBar plugins are present in the panel."
}

# ============================================================
# Build new plugin array
# ============================================================

build_new_plugin_array() {

    NEW_PLUGIN_IDS=()

    local current
    local remove
    local remove_id

    for current in "${ORIGINAL_PLUGIN_IDS[@]}"; do

        remove=false

        for remove_id in "${CTFBAR_PLUGIN_IDS[@]}"; do

            if [ "$current" = "$remove_id" ]; then
                remove=true
                break
            fi
        done

        if [ "$remove" = false ]; then
            NEW_PLUGIN_IDS+=("$current")
        fi
    done

    if [ "${#NEW_PLUGIN_IDS[@]}" -eq 0 ]; then

        error \
            "Removing CTFBar would leave the panel with no plugins. " \
            "Operation cancelled."
    fi
}

# ============================================================
# Remove plugin configuration
# ============================================================

remove_ctfbar_plugins() {

    local id

    for id in "${CTFBAR_PLUGIN_IDS[@]}"; do

        info "Removing plugin-$id configuration..."

        xfconf-query \
            -c xfce4-panel \
            -p "/plugins/plugin-$id" \
            -r \
            -R \
            >/dev/null 2>&1 || true
    done
}

# ============================================================
# Panel rollback
# ============================================================

rollback_panel() {

    if [ "${#ORIGINAL_PLUGIN_IDS[@]}" -eq 0 ]; then
        warn "No original array available for rollback."
        return 0
    fi

    warn "Attempting to restore the original panel array..."

    if write_plugin_ids \
        "$PANEL_ID" \
        "${ORIGINAL_PLUGIN_IDS[@]}"; then

        info "Original array restored."

    else

        warn "Could NOT automatically restore the original array."
        warn "Do not continue modifying XFCE until the configuration has been reviewed."
    fi

    xfce4-panel -r >/dev/null 2>&1 || true
}

# ============================================================
# Panel uninstall
# ============================================================

uninstall_panel() {

    info "Reading current panel configuration..."

    mapfile -t ORIGINAL_PLUGIN_IDS < <(
        get_plugin_ids "$PANEL_ID"
    )

    if [ "${#ORIGINAL_PLUGIN_IDS[@]}" -eq 0 ]; then
        error "No plugins found in the panel."
    fi

    info \
        "Panel $PANEL_ID found with " \
        "${#ORIGINAL_PLUGIN_IDS[@]} plugins."

    # --------------------------------------------------------
    # Make absolutely sure the five CTFBar IDs exist.
    # --------------------------------------------------------

    verify_ctfbar_plugins_present

    # --------------------------------------------------------
    # Backup BEFORE modifying anything.
    # --------------------------------------------------------

    mkdir -p "$BACKUP_DIR"

    local backup

    backup="$BACKUP_DIR/xfce4-panel-before-uninstall-$(date +%Y%m%d-%H%M%S).txt"

    xfconf-query \
        -c xfce4-panel \
        -lv > "$backup"

    info "Panel backup created:"
    info "$backup"

    # --------------------------------------------------------
    # Build new array.
    # --------------------------------------------------------

    build_new_plugin_array

    echo
    echo "Current array:"
    printf '  %s\n' "${ORIGINAL_PLUGIN_IDS[@]}"

    echo
    echo "Array after removing CTFBar:"
    printf '  %s\n' "${NEW_PLUGIN_IDS[@]}"

    # --------------------------------------------------------
    # Write new array.
    #
    # DO NOT delete plugin-ids first.
    # --------------------------------------------------------

    info "Applying new panel layout..."

    PANEL_MODIFIED=true

    if ! write_plugin_ids \
        "$PANEL_ID" \
        "${NEW_PLUGIN_IDS[@]}"; then

        rollback_panel

        error "Could not write the new panel configuration."
    fi

    # --------------------------------------------------------
    # Verify array.
    # --------------------------------------------------------

    info "Verifying panel configuration..."

    if ! verify_plugin_ids \
        "$PANEL_ID" \
        "${NEW_PLUGIN_IDS[@]}"; then

        rollback_panel

        error "Panel verification failed."
    fi

    info "plugin-ids array verified successfully."

    # --------------------------------------------------------
    # Only AFTER the array is confirmed:
    # remove CTFBar plugin configurations.
    # --------------------------------------------------------

    remove_ctfbar_plugins

    # --------------------------------------------------------
    # Final verification.
    # --------------------------------------------------------

    local final_ids=()

    mapfile -t final_ids < <(
        get_plugin_ids "$PANEL_ID"
    )

    local id

    for id in "${CTFBAR_PLUGIN_IDS[@]}"; do

        for current in "${final_ids[@]}"; do

            if [ "$current" = "$id" ]; then

                warn \
                    "plugin-$id is still present in plugin-ids."

                rollback_panel

                error \
                    "CTFBar removal could not be verified."
            fi
        done
    done

    info "CTFBar plugins are no longer present in plugin-ids."

    # --------------------------------------------------------
    # Restart panel.
    # --------------------------------------------------------

    xfce4-panel -r >/dev/null 2>&1 || true

    info "Panel updated successfully."
}

# ============================================================
# ZSH
# ============================================================

remove_ctfbar_zsh_block() {

    [ -f "$ZSHRC" ] || return 0

    if ! grep -q '^# >>> CTFBAR >>>$' "$ZSHRC"; then

        warn "No CTFBar block found in .zshrc."
        return 0
    fi

    mkdir -p "$BACKUP_DIR"

    local backup

    backup="$BACKUP_DIR/zshrc-before-uninstall-$(date +%Y%m%d-%H%M%S).bak"

    cp "$ZSHRC" "$backup"

    info ".zshrc backup created:"
    info "$backup"

    python3 - "$ZSHRC" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])

text = path.read_text()

start = "# >>> CTFBAR >>>"
end = "# <<< CTFBAR <<<"

before, marker, rest = text.partition(start)

if not marker:
    sys.exit(0)

block, end_marker, after = rest.partition(end)

if not end_marker:
    print(
        "ERROR: se encontró el inicio del bloque CTFBar "
        "pero no el marcador final.",
        file=sys.stderr
    )
    sys.exit(1)

text = before.rstrip() + "\n" + after.lstrip()

path.write_text(text)
PY

    info "CTFBar block removed from .zshrc."
}

# ============================================================
# Main
# ============================================================

echo
echo "======================================"
echo "          CTFBar Uninstaller"
echo " by EldritchEcho"
echo "======================================"
echo

check_environment

# ============================================================
# Confirmation
# ============================================================

echo "PANEL: $PANEL_ID"
echo

echo "Only the following will be removed:"
echo

echo "  Separator → $SEPARATOR1_ID"
echo "  Info      → $INFO_ID"
echo "  Separator → $SEPARATOR2_ID"
echo "  Target    → $TARGET_ID"
echo "  Separator → $SEPARATOR3_ID"

echo

read -rp "¿Continue? [y/N] " answer

[[ "$answer" =~ ^[Yy]$ ]] || exit 0

echo

# ============================================================
# Panel
# ============================================================

uninstall_panel

# ============================================================
# ZSH
# ============================================================

remove_ctfbar_zsh_block

# ============================================================
# Configuration files
# ============================================================

echo
read -rp "Also remove ~/.config/ctfbar? [y/N] " delete_config

if [[ "$delete_config" =~ ^[Yy]$ ]]; then

    rm -rf "$CONFIG_DIR"

    info "CTFBar files removed."

else

    warn "$CONFIG_DIR will be preserved."
    warn "The state file and backups will remain available."
fi

# ============================================================
# Success
# ============================================================

echo
echo "======================================"
echo "   CTFBar uninstalled successfully"
echo "======================================"
echo

if command -v zsh >/dev/null 2>&1; then

    echo "[+] Reloading ZSH..."

    exec zsh -l

else

    echo "[!] ZSH is not available."
    echo "    Reload the shell manually when possible."
    echo "    You can do this with: source ~/.zshrc"

fi


