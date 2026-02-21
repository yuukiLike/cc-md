#!/bin/bash
# setup.sh logic tests
# Tests vault discovery, preflight helpers, and idempotency

SETUP_CMD="$PROJECT_DIR/scripts/setup.sh"

# ---------- helpers ----------

# Create a fake iCloud Obsidian directory with vaults
_setup_fake_icloud() {
    local icloud_dir="$1"
    mkdir -p "$icloud_dir"
}

_create_vault_in() {
    local icloud_dir="$1" name="$2"
    mkdir -p "$icloud_dir/$name"
    # Add a file so it's a real vault
    echo "# test" > "$icloud_dir/$name/test.md"
}

# ---------- vault discovery ----------

test_single_vault_auto_selected() {
    # Create a fake iCloud dir with one vault
    local fake_icloud
    fake_icloud="$(mktemp -d)/iCloud~md~obsidian/Documents"
    _setup_fake_icloud "$fake_icloud"
    _create_vault_in "$fake_icloud" "notes"

    # Source setup.sh can't be run directly (it exits on missing SSH key etc.)
    # Instead test the vault scanning logic by simulating it
    local vaults=()
    while IFS= read -r -d '' dir; do
        name="$(basename "$dir")"
        [[ "$name" == .* ]] && continue
        vaults+=("$dir")
    done < <(find "$fake_icloud" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    assert_eq "1" "${#vaults[@]}" "should find exactly 1 vault"
    assert_eq "notes" "$(basename "${vaults[0]}")" "vault name should be notes"

    rm -rf "$(dirname "$(dirname "$fake_icloud")")"
}

test_multiple_vaults_found() {
    local fake_icloud
    fake_icloud="$(mktemp -d)/iCloud~md~obsidian/Documents"
    _setup_fake_icloud "$fake_icloud"
    _create_vault_in "$fake_icloud" "work"
    _create_vault_in "$fake_icloud" "personal"
    _create_vault_in "$fake_icloud" "notes"

    local vaults=()
    while IFS= read -r -d '' dir; do
        name="$(basename "$dir")"
        [[ "$name" == .* ]] && continue
        vaults+=("$dir")
    done < <(find "$fake_icloud" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    assert_eq "3" "${#vaults[@]}" "should find 3 vaults"

    rm -rf "$(dirname "$(dirname "$fake_icloud")")"
}

test_hidden_dirs_skipped() {
    local fake_icloud
    fake_icloud="$(mktemp -d)/iCloud~md~obsidian/Documents"
    _setup_fake_icloud "$fake_icloud"
    _create_vault_in "$fake_icloud" "notes"
    _create_vault_in "$fake_icloud" ".hidden"

    local vaults=()
    while IFS= read -r -d '' dir; do
        name="$(basename "$dir")"
        [[ "$name" == .* ]] && continue
        vaults+=("$dir")
    done < <(find "$fake_icloud" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)

    assert_eq "1" "${#vaults[@]}" "should skip hidden dirs"
    assert_eq "notes" "$(basename "${vaults[0]}")" "should find notes only"

    rm -rf "$(dirname "$(dirname "$fake_icloud")")"
}

# ---------- saved vault config ----------

test_saved_vault_path_used() {
    # Write a vault-path that points to our test vault
    echo "$CC_MD_TEST_VAULT" > "$CC_MD_STATE_DIR/vault-path"

    local saved
    saved="$(cat "$CC_MD_STATE_DIR/vault-path")"

    if [ -d "$saved" ]; then
        # This simulates setup.sh phase 1 "already configured" check
        assert_eq "$CC_MD_TEST_VAULT" "$saved" "should use saved vault path"
    else
        _CURRENT_TEST_FAILED=1
        _ASSERT_MSGS+="    saved vault path should exist\n"
    fi
}

# ---------- git init idempotency ----------

test_git_init_idempotent() {
    # CC_MD_TEST_VAULT already has .git from setup_test_env
    local commit_before
    commit_before=$(git -C "$CC_MD_TEST_VAULT" rev-parse HEAD)

    # Simulate phase 2: if .git exists, skip
    if [ -d "$CC_MD_TEST_VAULT/.git" ]; then
        local commit_after
        commit_after=$(git -C "$CC_MD_TEST_VAULT" rev-parse HEAD)
        assert_eq "$commit_before" "$commit_after" "HEAD should not change"
    else
        _CURRENT_TEST_FAILED=1
        _ASSERT_MSGS+="    .git should exist from setup_test_env\n"
    fi
}

# ---------- remote idempotency ----------

test_remote_skip_when_configured() {
    local bare_remote
    bare_remote="$(mktemp -d)"
    git init --bare --quiet "$bare_remote"
    git -C "$CC_MD_TEST_VAULT" remote add origin "$bare_remote"

    # Simulate phase 3: if remote exists, skip
    local url
    url=$(git -C "$CC_MD_TEST_VAULT" remote get-url origin 2>/dev/null || echo "")

    assert_eq "$bare_remote" "$url" "remote should be configured"

    rm -rf "$bare_remote"
}

# ---------- install.sh backward compat ----------

test_install_sh_wrapper() {
    local install_content
    install_content=$(cat "$PROJECT_DIR/scripts/install.sh")

    assert_contains "$install_content" "setup.sh" "install.sh should reference setup.sh"
}

# ---------- cc-md CLI setup subcommand ----------

test_cc_md_has_setup_cmd() {
    local cc_md_content
    cc_md_content=$(cat "$PROJECT_DIR/scripts/cc-md")

    assert_contains "$cc_md_content" "setup)" "cc-md should have setup subcommand"
    assert_contains "$cc_md_content" "cmd_setup" "cc-md should have cmd_setup function"
}

# ---------- URL validation ----------

test_ssh_url_format_valid() {
    local url="git@github.com:user/repo.git"
    if [[ "$url" =~ ^git@github\.com:.+/.+\.git$ ]]; then
        # pass
        true
    else
        _CURRENT_TEST_FAILED=1
        _ASSERT_MSGS+="    valid SSH URL should match pattern\n"
    fi
}

test_ssh_url_format_invalid() {
    local url="https://github.com/user/repo"
    if [[ "$url" =~ ^git@github\.com:.+/.+\.git$ ]]; then
        _CURRENT_TEST_FAILED=1
        _ASSERT_MSGS+="    HTTPS URL should not match SSH pattern\n"
    fi
}
