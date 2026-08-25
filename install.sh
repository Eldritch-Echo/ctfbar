#!/usr/bin/env bash

set -euo pipefail

APP_NAME="ctfbar"
VERSION="1.0.3"

CONFIG_DIR="$HOME/.config/ctfbar"
BACKUP_DIR="$CONFIG_DIR/backups"
STATE_FILE="$CONFIG_DIR/state"
ZSHRC="$HOME/.zshrc"

# ============================================================
# Runtime state / rollback
# ============================================================

INSTALL_STARTED=false
ZSH_MODIFIED=false
PANEL_MODIFIED=false

PANEL_ID=""
ORIGINAL_PLUGIN_IDS=()
CREATED_PLUGIN_IDS=()

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
    return 1
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# Cleanup helpers
# ============================================================

remove_ctfbar_zsh_block() {

    [ -f "$ZSHRC" ] || return 0

    python3 - "$ZSHRC" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])

if not path.exists():
    sys.exit(0)

text = path.read_text()

start = "# >>> CTFBAR >>>"
end = "# <<< CTFBAR <<<"

before, marker, rest = text.partition(start)

if not marker:
    sys.exit(0)

block, end_marker, after = rest.partition(end)

if not end_marker:
    sys.exit(0)

text = before.rstrip() + "\n" + after.lstrip()

path.write_text(text)
PY
}

remove_created_plugins() {

    local id

    for id in "${CREATED_PLUGIN_IDS[@]}"; do

        [ -n "$id" ] || continue

        xfconf-query \
            -c xfce4-panel \
            -p "/plugins/plugin-$id" \
            -r \
            -R >/dev/null 2>&1 || true
    done
}

restore_plugin_ids() {

    [ -n "$PANEL_ID" ] || return 0
    [ "${#ORIGINAL_PLUGIN_IDS[@]}" -gt 0 ] || return 0

    local args=()
    local id

    for id in "${ORIGINAL_PLUGIN_IDS[@]}"; do
        args+=(
            "-t" "int"
            "-s" "$id"
        )
    done

    xfconf-query \
        -c xfce4-panel \
        -p "/panels/panel-$PANEL_ID/plugin-ids" \
        -a \
        "${args[@]}" \
        >/dev/null 2>&1 || true
}

rollback() {

    echo
    warn "CTFBar installation failed."
    warn "Attempting to restore previous state..."

    # --------------------------------------------------------
    # Panel
    # --------------------------------------------------------

    if [ "$PANEL_MODIFIED" = true ] ||
       [ "${#CREATED_PLUGIN_IDS[@]}" -gt 0 ]; then

        info "Restoring panel plugins..."

        remove_created_plugins
        restore_plugin_ids

        xfce4-panel -r >/dev/null 2>&1 || true

        info "Panel restored."
    fi

    # --------------------------------------------------------
    # ZSH
    # --------------------------------------------------------

    if [ "$ZSH_MODIFIED" = true ]; then

        info "Removing CTFBar block from .zshrc..."

        remove_ctfbar_zsh_block

        info "ZSH configuration restored."
    fi

    # --------------------------------------------------------
    # Files
    # --------------------------------------------------------

    if [ "$INSTALL_STARTED" = true ] &&
       [ -d "$CONFIG_DIR" ]; then

        rm -rf "$CONFIG_DIR"

        info "Failed installation files removed."
    fi

    echo
    echo "======================================"
    echo "     Installation aborted"
    echo "======================================"
    echo

    exit 1
}

# ============================================================
# Checks
# ============================================================

check_environment() {

    if [ -z "${HOME:-}" ]; then
        error "Could not determine HOME."
        return 1
    fi

    if ! command_exists xfconf-query; then
        error "xfconf-query is not available. CTFBar requires XFCE."
        return 1
    fi

    if ! xfconf-query \
        -c xfce4-panel \
        -p /panels >/dev/null 2>&1; then

        error "Could not access xfce4-panel."
        return 1
    fi

    if ! command_exists python3; then
        error "Python 3 is required to manage the .zshrc block."
        return 1
    fi

    if ! command_exists xfce4-panel; then
        error "xfce4-panel is not available."
        return 1
    fi
}

# ============================================================
# Dependencies
# ============================================================

install_dependencies() {

    local packages=()

    command_exists xclip || packages+=("xclip")
    command_exists notify-send || packages+=("libnotify-bin")

    if ! dpkg -s xfce4-genmon-plugin >/dev/null 2>&1; then
        packages+=("xfce4-genmon-plugin")
    fi

    if [ "${#packages[@]}" -eq 0 ]; then
        info "Dependencies: OK"
        return 0
    fi

    info "Installing: ${packages[*]}"

    sudo apt update
    sudo apt install -y "${packages[@]}"
}

# ============================================================
# Directories
# ============================================================

create_directories() {

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"

    touch "$CONFIG_DIR/target.txt"
    touch "$CONFIG_DIR/info.txt"

    chmod 600 "$CONFIG_DIR/target.txt"
    chmod 600 "$CONFIG_DIR/info.txt"
}

# ============================================================
# Scripts
# ============================================================

create_scripts() {

    cat > "$CONFIG_DIR/target_status.sh" <<EOF
#!/usr/bin/env bash

TARGET=\$(cat "$CONFIG_DIR/target.txt" 2>/dev/null)
COPY_SCRIPT="$CONFIG_DIR/copy_target.sh"

if [ -z "\$TARGET" ]; then
    echo "<txt>🎯 No Target</txt>"
else
    echo "<txtclick>\$COPY_SCRIPT</txtclick><txt>🎯 \$TARGET</txt>"
fi
EOF

    cat > "$CONFIG_DIR/info_status.sh" <<EOF
#!/usr/bin/env bash

INFO=\$(cat "$CONFIG_DIR/info.txt" 2>/dev/null)
COPY_SCRIPT="$CONFIG_DIR/copy_info.sh"

if [ -z "\$INFO" ]; then
    echo "<txt>📌 No Info</txt>"
else
    echo "<txtclick>\$COPY_SCRIPT</txtclick><txt>📌 \$INFO</txt>"
fi
EOF

    cat > "$CONFIG_DIR/copy_target.sh" <<EOF
#!/usr/bin/env bash

export DISPLAY="\${DISPLAY:-:0}"

TARGET=\$(cat "$CONFIG_DIR/target.txt" 2>/dev/null)

if [ -n "\$TARGET" ]; then

    printf '%s' "\$TARGET" |
        xclip -selection clipboard

    printf '%s' "\$TARGET" |
        xclip -selection primary

    notify-send "CTFBar" "🎯 \$TARGET copied" \
        --icon=terminal \
        -t 1000
fi
EOF

    cat > "$CONFIG_DIR/copy_info.sh" <<EOF
#!/usr/bin/env bash

export DISPLAY="\${DISPLAY:-:0}"

INFO=\$(cat "$CONFIG_DIR/info.txt" 2>/dev/null)

if [ -n "\$INFO" ]; then

    printf '%s' "\$INFO" |
        xclip -selection clipboard

    printf '%s' "\$INFO" |
        xclip -selection primary

    notify-send "CTFBar" "📌 Info copied" \
        --icon=terminal \
        -t 1000
fi
EOF

    chmod +x \
        "$CONFIG_DIR/target_status.sh" \
        "$CONFIG_DIR/info_status.sh" \
        "$CONFIG_DIR/copy_target.sh" \
        "$CONFIG_DIR/copy_info.sh"
}

# ============================================================
# ZSH
# ============================================================

install_zsh_config() {

    [ -f "$ZSHRC" ] || touch "$ZSHRC"

    if grep -q '^# >>> CTFBAR >>>$' "$ZSHRC"; then

        if [ -f "$STATE_FILE" ]; then
            error "CTFBar is already installed."
            return 1
        else
            error "An incomplete CTFBar block has been detected in .zshrc. Clean up the previous installation before continuing."
            return 1
        fi
    fi

    cp "$ZSHRC" \
        "$BACKUP_DIR/zshrc-before-install-$(date +%Y%m%d-%H%M%S).bak"

    cat >> "$ZSHRC" <<EOF

# >>> CTFBAR >>>

settarget() {
    printf '%s' "\$*" > "$CONFIG_DIR/target.txt"
}

setinfo() {
    printf '%s' "\$*" > "$CONFIG_DIR/info.txt"
}

alias cleartarget='printf "" > "$CONFIG_DIR/target.txt"'
alias clearinfo='printf "" > "$CONFIG_DIR/info.txt"'
alias clearbars='cleartarget && clearinfo'

# <<< CTFBAR <<<
EOF

    ZSH_MODIFIED=true

    info "ZSH configuration added."
}

# ============================================================
# XFCE
# ============================================================

get_panel_id() {

    local panel

    panel=$(
        xfconf-query \
            -c xfce4-panel \
            -p /panels 2>/dev/null |
        grep -oE '[0-9]+' |
        head -n1 || true
    )

    if [ -z "$panel" ]; then
        error "Could not determine the panel."
        return 1
    fi

    echo "$panel"
}

get_plugin_ids() {

    local panel="$1"
    local property="/panels/panel-$panel/plugin-ids"
    local raw

    if ! raw=$(
        xfconf-query \
            -c xfce4-panel \
            -p "$property" 2>/dev/null
    ); then

        error "Could not read $property. CTFBar will not modify the panel."
        return 1
    fi

    local ids

    mapfile -t ids < <(
        printf '%s\n' "$raw" |
        sed -n '/^Value is an array with [0-9][0-9]* items:$/,$p' |
        tail -n +2 |
        grep -E '^[0-9]+$' || true
    )

    if [ "${#ids[@]}" -eq 0 ]; then
        error "The $property property exists but does not contain valid IDs."
        return 1
    fi

    printf '%s\n' "${ids[@]}"
}

find_cpugraph_position() {

    local panel="$1"
    shift

    local ids=("$@")
    local i
    local id
    local plugin_type

    for i in "${!ids[@]}"; do

        id="${ids[$i]}"

        plugin_type=$(
            xfconf-query \
                -c xfce4-panel \
                -p "/plugins/plugin-$id" \
                2>/dev/null || true
        )

        if [ "$plugin_type" = "cpugraph" ]; then
            echo "$i"
            return 0
        fi
    done

    return 1
}

get_free_id() {

    local ids="$1"
    local id=1

    while printf '%s\n' "$ids" |
          grep -qx "$id"; do

        id=$((id + 1))
    done

    echo "$id"
}

create_genmon() {

    local id="$1"
    local command="$2"

    xfconf-query \
        -c xfce4-panel \
        -p "/plugins/plugin-$id" \
        -n \
        -t string \
        -s genmon

    xfconf-query \
        -c xfce4-panel \
        -p "/plugins/plugin-$id/command" \
        -n \
        -t string \
        -s "$command"

    xfconf-query \
        -c xfce4-panel \
        -p "/plugins/plugin-$id/update-period" \
        -n \
        -t int \
        -s 3000

    xfconf-query \
        -c xfce4-panel \
        -p "/plugins/plugin-$id/use-label" \
        -n \
        -t bool \
        -s false

    xfconf-query \
        -c xfce4-panel \
        -p "/plugins/plugin-$id/enable-single-row" \
        -n \
        -t bool \
        -s true
}

create_separator() {

    local id="$1"

    xfconf-query \
        -c xfce4-panel \
        -p "/plugins/plugin-$id" \
        -n \
        -t string \
        -s separator

    xfconf-query \
        -c xfce4-panel \
        -p "/plugins/plugin-$id/style" \
        -n \
        -t int \
        -s 0
}

# ============================================================
# Panel array handling
# ============================================================

write_plugin_ids() {

    local panel="$1"
    shift

    local ids=("$@")
    local args=()
    local id

    if [ "${#ids[@]}" -eq 0 ]; then
        error "There are no IDs to write to the panel."
        return 1
    fi

    for id in "${ids[@]}"; do

        args+=(
            "-t" "int"
            "-s" "$id"
        )
    done

    xfconf-query \
        -c xfce4-panel \
        -p "/panels/panel-$panel/plugin-ids" \
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
        error "The plugin-ids array verification failed: expected ${#expected[@]} elements, but got ${#actual[@]}."
        return 1
    fi

    local i

    for i in "${!expected[@]}"; do

        if [ "${actual[$i]}" != "${expected[$i]}" ]; then
            error "The panel verification failed at position $i: expected ${expected[$i]}, got ${actual[$i]}."
            return 1
        fi
    done
}

# ============================================================
# Panel installation
# ============================================================

install_panel() {

    PANEL_ID=$(get_panel_id)

    local existing_ids

    existing_ids=$(get_plugin_ids "$PANEL_ID")

    mapfile -t ORIGINAL_PLUGIN_IDS <<< "$existing_ids"

    if [ "${#ORIGINAL_PLUGIN_IDS[@]}" -eq 0 ]; then
        error "Could not retrieve the original panel IDs."
        return 1
    fi

    # --------------------------------------------------------
    # Backup
    # --------------------------------------------------------

    local backup

    backup="$BACKUP_DIR/xfce4-panel-before-install-$(date +%Y%m%d-%H%M%S).txt"

    xfconf-query \
        -c xfce4-panel \
        -lv > "$backup"

    info "Panel backup created."

    # --------------------------------------------------------
    # Locate CPU Graph
    # --------------------------------------------------------

    local cpugraph_position

    if cpugraph_position=$(
        find_cpugraph_position \
            "$PANEL_ID" \
            "${ORIGINAL_PLUGIN_IDS[@]}"
    ); then

        info "CPU Graph found at position $((cpugraph_position + 1)) in the panel."

    else

        warn "CPU Graph not found."
        warn "CTFBar will be added to the end of the panel."

        cpugraph_position="${#ORIGINAL_PLUGIN_IDS[@]}"
    fi

    # --------------------------------------------------------
    # Find five free IDs
    # --------------------------------------------------------

    local used_ids="$existing_ids"

    local separator1
    local info_id
    local separator2
    local target_id
    local separator3

    separator1=$(get_free_id "$used_ids")
    used_ids+=$'\n'"$separator1"

    info_id=$(get_free_id "$used_ids")
    used_ids+=$'\n'"$info_id"

    separator2=$(get_free_id "$used_ids")
    used_ids+=$'\n'"$separator2"

    target_id=$(get_free_id "$used_ids")
    used_ids+=$'\n'"$target_id"

    separator3=$(get_free_id "$used_ids")

    info "Creando:"
    info "  Separator → $separator1"
    info "  Info      → $info_id"
    info "  Separator → $separator2"
    info "  Target    → $target_id"
    info "  Separator → $separator3"

    CREATED_PLUGIN_IDS=(
        "$separator1"
        "$info_id"
        "$separator2"
        "$target_id"
        "$separator3"
    )

    # Fail = rollback
    PANEL_MODIFIED=true

    # --------------------------------------------------------
    # Create plugins
    # --------------------------------------------------------

    create_separator "$separator1"

    create_genmon \
        "$info_id" \
        "$CONFIG_DIR/info_status.sh"

    create_separator "$separator2"

    create_genmon \
        "$target_id" \
        "$CONFIG_DIR/target_status.sh"

    create_separator "$separator3"

    # --------------------------------------------------------
    # Build final array
    # --------------------------------------------------------

    local new_ids=()

    local i

    for i in "${!ORIGINAL_PLUGIN_IDS[@]}"; do

        # CTFBar before CPU Graph.
        if [ "$i" -eq "$cpugraph_position" ]; then

            new_ids+=(
                "$separator1"
                "$info_id"
                "$separator2"
                "$target_id"
                "$separator3"
            )
        fi

        new_ids+=("${ORIGINAL_PLUGIN_IDS[$i]}")

    done

    # --------------------------------------------------------
    # Fallback: CPU Graph not found
    # --------------------------------------------------------

    if [ "$cpugraph_position" -eq "${#ORIGINAL_PLUGIN_IDS[@]}" ]; then

        new_ids+=(
            "$separator1"
            "$info_id"
            "$separator2"
            "$target_id"
            "$separator3"
        )
    fi

    # --------------------------------------------------------
    # Show resulting distribution
    # --------------------------------------------------------

    info "Applying new panel layout..."

    write_plugin_ids \
        "$PANEL_ID" \
        "${new_ids[@]}"

    # --------------------------------------------------------
    # Verify
    # --------------------------------------------------------

    info "Verifying panel configuration..."

    verify_plugin_ids \
        "$PANEL_ID" \
        "${new_ids[@]}"

    info "Panel configuration verified successfully."

    # --------------------------------------------------------
    # Save state ONLY after successful verification
    # --------------------------------------------------------

    cat > "$STATE_FILE" <<EOF
CTFBAR_VERSION=$VERSION
PANEL_ID=$PANEL_ID
SEPARATOR1_ID=$separator1
INFO_ID=$info_id
SEPARATOR2_ID=$separator2
TARGET_ID=$target_id
SEPARATOR3_ID=$separator3
EOF

    # --------------------------------------------------------
    # Restart XFCE panel
    # --------------------------------------------------------

    xfce4-panel -r >/dev/null 2>&1 || true

    info "Panel configured successfully."
}

# ============================================================
# Main
# ============================================================

echo
echo "======================================"
echo "          CTFBar $VERSION"
echo " by EldritchEcho"
echo "======================================"
echo

if [ -f "$STATE_FILE" ]; then
    error "CTFBar is already installed."
    exit 1
fi

if [ -d "$CONFIG_DIR" ] &&
   [ ! -f "$STATE_FILE" ]; then

    error "An incomplete previous installation has been detected in $CONFIG_DIR. Remove it before continuing."
    exit 1
fi

INSTALL_STARTED=true

# ============================================================
# Installation
# ============================================================

check_environment
install_dependencies
create_directories
create_scripts
install_zsh_config
install_panel

# ============================================================
# Success
# ============================================================

echo
echo "======================================"
echo "       CTFBar installed"
echo "======================================"
echo
echo "Commands:"
echo
echo "    settarget <target> to set up a target"
echo "    setinfo <information> to set up information"
echo "    cleartarget to clear target"
echo "    clearinfo to clear info"
echo "    clearbars to clear both"
echo

if command -v zsh >/dev/null 2>&1; then

    echo "[+] Reloading ZSH..."

    exec zsh -l

else

    echo "[!] ZSH is not available."
    echo "    Reload the shell manually when possible."
    echo "    You can do this with: source ~/.zshrc"

fi

