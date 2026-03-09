#!/usr/bin/env bash
# manage-agent-user.sh — Provision/deprovision per-agent Linux users.
#
# This script MUST be owned by root (root:root 0755) and called via sudo
# by the ductor service user. It creates minimal system users that CLI
# subprocesses (claude/codex/gemini) run as, providing file-level isolation
# between agents.
#
# Usage:
#   sudo /opt/ductor/scripts/manage-agent-user.sh create  <agent_name> <ductor_user>
#   sudo /opt/ductor/scripts/manage-agent-user.sh delete  <agent_name> <ductor_user>
#   sudo /opt/ductor/scripts/manage-agent-user.sh exists  <agent_name>
#   sudo /opt/ductor/scripts/manage-agent-user.sh fix-perms <agent_name> <ductor_user>

set -euo pipefail

ACTION="${1:-}"
AGENT_NAME="${2:-}"
DUCTOR_USER="${3:-}"

if [[ -z "$ACTION" || -z "$AGENT_NAME" ]]; then
    echo "Usage: $0 {create|delete|exists|fix-perms} <agent_name> [ductor_user]" >&2
    exit 1
fi

# Strict name validation: lowercase alphanumeric + hyphens, 1-31 chars
if [[ ! "$AGENT_NAME" =~ ^[a-z][a-z0-9-]{0,30}$ ]]; then
    echo "ERROR: Invalid agent name '${AGENT_NAME}'" >&2
    exit 1
fi

AGENT_USER="ductor-${AGENT_NAME}"
DUCTOR_GROUP="ductor"

case "$ACTION" in
    create)
        if [[ -z "$DUCTOR_USER" ]]; then
            echo "ERROR: ductor_user argument required for create" >&2
            exit 1
        fi

        # Ensure ductor group exists
        if ! getent group "$DUCTOR_GROUP" >/dev/null 2>&1; then
            groupadd "$DUCTOR_GROUP"
            echo "Created group: ${DUCTOR_GROUP}"
        fi

        # Add ductor service user to ductor group if needed
        if id "$DUCTOR_USER" >/dev/null 2>&1; then
            if ! id -nG "$DUCTOR_USER" 2>/dev/null | grep -qw "$DUCTOR_GROUP"; then
                usermod -aG "$DUCTOR_GROUP" "$DUCTOR_USER" 2>/dev/null || true
            fi
        fi

        # Create agent user (idempotent)
        if id "$AGENT_USER" >/dev/null 2>&1; then
            echo "User ${AGENT_USER} already exists"
        else
            useradd \
                --system \
                --create-home \
                --home-dir "/home/${AGENT_USER}" \
                --shell /usr/sbin/nologin \
                --gid "$DUCTOR_GROUP" \
                "$AGENT_USER"
            echo "Created user: ${AGENT_USER}"
        fi

        # Symlink Claude Code credentials from ductor user
        DUCTOR_CLAUDE_DIR="$(eval echo "~${DUCTOR_USER}")/.claude"
        AGENT_CLAUDE_DIR="/home/${AGENT_USER}/.claude"
        if [[ -d "$DUCTOR_CLAUDE_DIR" ]]; then
            mkdir -p "$AGENT_CLAUDE_DIR"
            for cred_file in .credentials.json settings.json; do
                if [[ -f "${DUCTOR_CLAUDE_DIR}/${cred_file}" ]]; then
                    ln -sf "${DUCTOR_CLAUDE_DIR}/${cred_file}" "${AGENT_CLAUDE_DIR}/${cred_file}"
                fi
            done
            chown -R "${AGENT_USER}:${DUCTOR_GROUP}" "$AGENT_CLAUDE_DIR"
            echo "Symlinked Claude credentials"
        fi

        # NOTE: Workspace permissions are handled by fix-perms AFTER workspace init.
        # The ductor service user always owns the workspace; the agent user gets
        # ACL-based access via fix-perms.

        # Ensure shared files are group-writable
        DUCTOR_HOME="$(eval echo "~${DUCTOR_USER}")/.ductor"
        for shared_file in "${DUCTOR_HOME}/SHAREDMEMORY.md" "${DUCTOR_HOME}/.env"; do
            if [[ -f "$shared_file" ]]; then
                chgrp "$DUCTOR_GROUP" "$shared_file"
                chmod g+rw "$shared_file"
            fi
        done

        # Ensure Claude CLI is globally accessible.
        # Claude installs per-user under ~/.local/ and updates its own
        # symlink (~/.local/bin/claude → ~/.local/share/claude/versions/X.Y.Z).
        # We create a global symlink chain and open the directory traversal
        # so it auto-follows Claude updates without manual intervention.
        DUCTOR_HOME_DIR="$(eval echo "~${DUCTOR_USER}")"
        CLAUDE_LOCAL="${DUCTOR_HOME_DIR}/.local/bin/claude"
        CLAUDE_GLOBAL="/usr/local/bin/claude"
        if [[ -e "$CLAUDE_LOCAL" ]]; then
            # Open traverse-only (o+x) on the directory chain — no listing,
            # just enough for the kernel to follow the symlink path.
            for dir in \
                "${DUCTOR_HOME_DIR}/.local" \
                "${DUCTOR_HOME_DIR}/.local/bin" \
                "${DUCTOR_HOME_DIR}/.local/share" \
                "${DUCTOR_HOME_DIR}/.local/share/claude" \
                "${DUCTOR_HOME_DIR}/.local/share/claude/versions"; do
                [[ -d "$dir" ]] && chmod o+x "$dir" 2>/dev/null || true
            done
            # Make existing version binaries world-executable and set
            # default ACLs so future versions (auto-updates) inherit o+rx
            # automatically — no ductor restart needed.
            VERSIONS_DIR="${DUCTOR_HOME_DIR}/.local/share/claude/versions"
            if [[ -d "$VERSIONS_DIR" ]]; then
                chmod -R o+rx "$VERSIONS_DIR" 2>/dev/null || true
                setfacl -d -m o::rx "$VERSIONS_DIR" 2>/dev/null || true
            fi
            # Global symlink follows the per-user symlink chain automatically
            ln -sf "$CLAUDE_LOCAL" "$CLAUDE_GLOBAL"
            echo "Linked claude globally: ${CLAUDE_GLOBAL} -> ${CLAUDE_LOCAL}"
        fi

        # Ensure the ductor service user's .claude directory is traversable
        # so agent users can follow credential symlinks.
        DUCTOR_CLAUDE_PARENT="${DUCTOR_HOME_DIR}/.claude"
        if [[ -d "$DUCTOR_CLAUDE_PARENT" ]]; then
            chmod o+x "$DUCTOR_HOME_DIR" 2>/dev/null || true
            chmod o+x "$DUCTOR_CLAUDE_PARENT" 2>/dev/null || true
            for cred_file in .credentials.json settings.json; do
                if [[ -f "${DUCTOR_CLAUDE_PARENT}/${cred_file}" ]]; then
                    chmod o+r "${DUCTOR_CLAUDE_PARENT}/${cred_file}" 2>/dev/null || true
                fi
            done
        fi

        # Write per-agent sudoers entry for CLI binaries
        SUDOERS_FILE="/etc/sudoers.d/ductor-agent-${AGENT_NAME}"
        CLAUDE_PATH="$(command -v claude 2>/dev/null || echo "/usr/local/bin/claude")"
        cat > "${SUDOERS_FILE}" <<SUDOERS
# Auto-generated by manage-agent-user.sh — do not edit manually
${DUCTOR_USER} ALL=(${AGENT_USER}) NOPASSWD:SETENV: ${CLAUDE_PATH}
${DUCTOR_USER} ALL=(${AGENT_USER}) NOPASSWD:SETENV: /usr/bin/env
SUDOERS
        chmod 0440 "${SUDOERS_FILE}"
        echo "Wrote sudoers: ${SUDOERS_FILE}"

        echo "OK"
        ;;

    delete)
        if [[ -z "$DUCTOR_USER" ]]; then
            echo "ERROR: ductor_user argument required for delete" >&2
            exit 1
        fi
        if id "$AGENT_USER" >/dev/null 2>&1; then
            userdel -r "$AGENT_USER" 2>/dev/null || userdel "$AGENT_USER" || true
            echo "Deleted user: ${AGENT_USER}"
        else
            echo "User ${AGENT_USER} does not exist"
        fi
        rm -f "/etc/sudoers.d/ductor-agent-${AGENT_NAME}"
        echo "OK"
        ;;

    exists)
        if id "$AGENT_USER" >/dev/null 2>&1; then
            echo "yes"
            exit 0
        else
            echo "no"
            exit 1
        fi
        ;;

    fix-perms)
        if [[ -z "$DUCTOR_USER" ]]; then
            echo "ERROR: ductor_user argument required for fix-perms" >&2
            exit 1
        fi
        DUCTOR_HOME="$(eval echo "~${DUCTOR_USER}")/.ductor"
        AGENT_WORKSPACE="${DUCTOR_HOME}/agents/${AGENT_NAME}"
        if [[ -d "$AGENT_WORKSPACE" ]]; then
            # The ductor service user always owns agent workspaces so the
            # supervisor can manage configs without permission issues.
            # The isolated agent user receives ACL-based rwX access so CLI
            # subprocesses (running as ductor-<name>) can read/write the
            # workspace without owning it.
            chown -R "${DUCTOR_USER}:${DUCTOR_GROUP}" "$AGENT_WORKSPACE"
            chmod -R g+rwX "$AGENT_WORKSPACE"
            setfacl -R -m u:"${AGENT_USER}":rwX "$AGENT_WORKSPACE"
            # Default ACLs ensure new files created by the agent user
            # (e.g. claude writing to workspace/) are accessible to both
            # the supervisor and the agent user.
            setfacl -R -d -m u:"${AGENT_USER}":rwX "$AGENT_WORKSPACE"
            setfacl -R -d -m u:"${DUCTOR_USER}":rwX "$AGENT_WORKSPACE"
            echo "Fixed permissions: ${AGENT_WORKSPACE}"
        fi
        # Ensure shared files stay group-writable
        for shared_file in "${DUCTOR_HOME}/SHAREDMEMORY.md" "${DUCTOR_HOME}/.env"; do
            if [[ -f "$shared_file" ]]; then
                chgrp "$DUCTOR_GROUP" "$shared_file"
                chmod g+rw "$shared_file"
            fi
        done
        echo "OK"
        ;;

    *)
        echo "Unknown action: ${ACTION}" >&2
        echo "Usage: $0 {create|delete|exists|fix-perms} <agent_name> [ductor_user]" >&2
        exit 1
        ;;
esac
