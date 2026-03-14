#!/bin/bash
set -e

echo "=== Cosmic Workspaces with Launcher Integration - Installation ==="
echo ""

if [ ! -f "Cargo.toml" ]; then
    echo "Error: Please run this script from the cosmic-ext-overview directory"
    exit 1
fi

INSTALL_DIR="$(pwd)"

CARGO_CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/cosmic-workspaces-build"
PROJECT_HASH="$(printf '%s' "$INSTALL_DIR" | sha256sum | cut -c1-12)"
TARGET_DIR="${CARGO_TARGET_DIR:-${CARGO_CACHE_BASE}/${PROJECT_HASH}}"
BIN_PATH="${TARGET_DIR}/release/cosmic-workspaces"

mkdir -p "$TARGET_DIR"

if [ -z "${CARGO_TARGET_DIR:-}" ]; then
    export CARGO_TARGET_DIR="$TARGET_DIR"
fi

echo "Using cargo target dir: $CARGO_TARGET_DIR"

BUILD_CMD=(cargo build --release)
LOCKED_BUILD=false
if [ -f "Cargo.lock" ]; then
    BUILD_CMD+=(--locked)
    LOCKED_BUILD=true
fi

echo "Building release binary..."
BUILD_LOG="$(mktemp)"
set +e
"${BUILD_CMD[@]}" 2> >(tee "$BUILD_LOG" >&2)
BUILD_STATUS=$?
set -e

if [ $BUILD_STATUS -ne 0 ]; then
    if [ "$LOCKED_BUILD" = true ] && grep -q "lock file .* needs to be updated but --locked was passed" "$BUILD_LOG"; then
        echo "Cargo.lock is out of date for this branch; retrying build without --locked..."
        cargo build --release
    else
        rm -f "$BUILD_LOG"
        exit $BUILD_STATUS
    fi
fi

rm -f "$BUILD_LOG"

if [ ! -f "$BIN_PATH" ]; then
    echo "Error: Build failed"
    exit 1
fi
echo "Build successful!"
echo ""

if [ -f "/usr/bin/cosmic-workspaces" ]; then
    BACKUP_NUM=1
    while [ -f "/usr/bin/cosmic-workspaces.backup${BACKUP_NUM}" ]; do
        BACKUP_NUM=$((BACKUP_NUM + 1))
    done
    echo "Backing up to /usr/bin/cosmic-workspaces.backup${BACKUP_NUM}..."
    sudo cp /usr/bin/cosmic-workspaces "/usr/bin/cosmic-workspaces.backup${BACKUP_NUM}"
fi

SHORTCUTS_CONFIG="$HOME/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom"
SHORTCUTS_DIR="$(dirname "$SHORTCUTS_CONFIG")"

echo "Configuring Super key to open Workspaces..."
mkdir -p "$SHORTCUTS_DIR"

if [ -f "$SHORTCUTS_CONFIG" ]; then
    cp "$SHORTCUTS_CONFIG" "${SHORTCUTS_CONFIG}.backup.$(date +%s)"
    if grep -q "WorkspaceOverview" "$SHORTCUTS_CONFIG"; then
        echo "Super key already mapped to WorkspaceOverview, skipping."
    else
        SHORTCUTS_TMP="$(mktemp)"
        if awk '
            /^}/ && !inserted {
                print "    ("
                print "        modifiers: ["
                print "            Super,"
                print "        ],"
                print "    ): System(WorkspaceOverview),"
                inserted=1
            }
            { print }
        ' "$SHORTCUTS_CONFIG" > "$SHORTCUTS_TMP"; then
            mv "$SHORTCUTS_TMP" "$SHORTCUTS_CONFIG"
        else
            rm -f "$SHORTCUTS_TMP"
            echo "Error: Failed to update shortcuts config"
            exit 1
        fi
        echo "Super key binding added to existing shortcuts."
    fi
else
    cat > "$SHORTCUTS_CONFIG" << 'SHORTCUTS'
{
    (
        modifiers: [
            Super,
        ],
    ): System(WorkspaceOverview),
}
SHORTCUTS
fi

echo "Super key configured!"

WORKSPACE_CONFIG="$HOME/.config/cosmic/com.system76.CosmicWorkspaces.toml"
WORKSPACE_DIR="$(dirname "$WORKSPACE_CONFIG")"

echo "Setting workspace layout to Horizontal..."

mkdir -p "$WORKSPACE_DIR"

if [ -f "$WORKSPACE_CONFIG" ]; then
    cp "$WORKSPACE_CONFIG" "${WORKSPACE_CONFIG}.backup.$(date +%s)"
fi

if grep -q "workspace_layout" "$WORKSPACE_CONFIG" 2>/dev/null; then
    sed -i 's/workspace_layout = .*/workspace_layout = "Horizontal"/' "$WORKSPACE_CONFIG"
else
    echo 'workspace_layout = "Horizontal"' >> "$WORKSPACE_CONFIG"
fi

echo "Workspace layout set to Horizontal."

echo "Installing..."
sudo mkdir -p /usr/local/lib/cosmic-workspaces-overview
sudo cp "$BIN_PATH" /usr/local/lib/cosmic-workspaces-overview/cosmic-workspaces
sudo cp "$BIN_PATH" /usr/bin/cosmic-workspaces.new
sudo chmod +x /usr/bin/cosmic-workspaces.new
sudo mv /usr/bin/cosmic-workspaces.new /usr/bin/cosmic-workspaces

echo "Restarting cosmic-workspaces..."
sudo killall cosmic-workspaces 2>/dev/null || true
sleep 1
echo "Installed successfully!"

AUTO_REINSTALL="manual"

if command -v pacman >/dev/null 2>&1; then
    echo "Creating pacman hook..."
    sudo mkdir -p /etc/pacman.d/hooks
    sudo tee /etc/pacman.d/hooks/cosmic-workspaces-custom.hook > /dev/null << HOOK
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = cosmic-workspaces

[Action]
Description = Reinstalling custom cosmic-workspaces with launcher integration...
When = PostTransaction
Exec = /bin/sh -c 'cp /usr/local/lib/cosmic-workspaces-overview/cosmic-workspaces /usr/bin/cosmic-workspaces.new && chmod +x /usr/bin/cosmic-workspaces.new && mv /usr/bin/cosmic-workspaces.new /usr/bin/cosmic-workspaces && killall cosmic-workspaces 2>/dev/null || true'
HOOK
    echo "Pacman hook installed!"
    AUTO_REINSTALL="pacman"
else
    echo "Pacman not detected; skipping package hook setup."
fi

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "  ✓ Press Super to open workspaces with integrated launcher"
echo "  ✓ Type to search apps immediately"
echo "  ✓ Horizontal layout enabled"
echo "  ✓ Space, backspace, arrow keys all work"
echo "  ✓ Enter or click to launch"
echo "  ✓ Clicking dock closes the view"

if [ "$AUTO_REINSTALL" = "pacman" ]; then
    echo "  ✓ Auto-reinstalls after system updates (pacman hook)"
else
    echo "  ✓ Works on any distro with COSMIC DE"
    echo "  • Re-run 'bash install.sh' after your distro updates cosmic-workspaces"
fi

echo ""
