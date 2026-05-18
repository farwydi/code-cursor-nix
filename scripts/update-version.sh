#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_FILE="$SCRIPT_DIR/../package.nix"

log() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }
err() { echo "[ERROR] $*" >&2; }

for cmd in curl jq nix-prefetch-url nix-hash sed; do
    command -v "$cmd" &>/dev/null || { err "Required: $cmd"; exit 1; }
done

get_current_version() {
    grep -oP 'version = "\K[^"]+' "$PACKAGE_FILE" | head -1
}

api_query() {
    local api_platform="$1"
    local url="https://api2.cursor.sh/updates/api/download/stable/$api_platform/cursor"
    local tmp
    tmp=$(mktemp)
    local http_code
    http_code=$(curl -sS -w "%{http_code}" -o "$tmp" --connect-timeout 15 --max-time 30 "$url")
    local response
    response=$(cat "$tmp")
    rm -f "$tmp"

    if [[ "$http_code" != "200" ]]; then
        err "API returned HTTP $http_code for $api_platform"
        return 1
    fi
    if ! echo "$response" | jq empty 2>/dev/null; then
        err "Invalid JSON from API for $api_platform"
        return 1
    fi
    echo "$response"
}

prefetch_hash() {
    local url="$1"

    # Check availability first
    local http_code
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" -I --connect-timeout 15 --max-time 15 "$url")
    if [[ "$http_code" != "200" ]]; then
        err "Download URL not available (HTTP $http_code): $url"
        return 1
    fi

    local store_path
    store_path=$(nix-prefetch-url "$url" 2>/dev/null) || { err "Failed to prefetch: $url"; return 1; }
    nix-hash --to-sri --type sha256 "$store_path"
}

main() {
    local current_version
    current_version=$(get_current_version)
    log "Current version: $current_version"

    # Query API for x86_64-linux to get latest version
    local response
    response=$(api_query "linux-x64")
    local latest_version
    latest_version=$(echo "$response" | jq -r '.version')
    log "Latest version: $latest_version"

    if [[ "$current_version" == "$latest_version" ]]; then
        log "Already at latest version"
        exit 0
    fi

    log "Update available: $current_version -> $latest_version"

    # Define platforms: nix_platform -> api_platform
    declare -A API_MAP=(
        ["x86_64-linux"]="linux-x64"
        ["aarch64-linux"]="linux-arm64"
        ["x86_64-darwin"]="darwin-x64"
        ["aarch64-darwin"]="darwin-arm64"
    )

    # Canonical URL path suffix per platform — MUST match the URLs in package.nix
    # exactly. We pin to downloads.cursor.com (what Nix fetches), not the API's
    # downloadUrl, which may point at a different mirror/build with a different
    # hash (the cause of past Linux hash mismatches).
    declare -A PATH_MAP=(
        ["x86_64-linux"]="linux/x64/Cursor-${latest_version}-x86_64.AppImage"
        ["aarch64-linux"]="linux/arm64/Cursor-${latest_version}-aarch64.AppImage"
        ["x86_64-darwin"]="darwin/x64/Cursor-darwin-x64.dmg"
        ["aarch64-darwin"]="darwin/arm64/Cursor-darwin-arm64.dmg"
    )

    declare -A NEW_URLS
    declare -A NEW_HASHES
    declare -A NEW_COMMITS

    for nix_plat in "${!API_MAP[@]}"; do
        local api_plat="${API_MAP[$nix_plat]}"
        log "Querying $nix_plat ($api_plat)..."

        local resp
        resp=$(api_query "$api_plat")

        local ver
        ver=$(echo "$resp" | jq -r '.version')
        if [[ "$ver" != "$latest_version" ]]; then
            warn "Version mismatch for $nix_plat: got $ver, expected $latest_version — skipping update"
            exit 0
        fi

        local api_url
        api_url=$(echo "$resp" | jq -r '.downloadUrl')

        local commit_sha
        commit_sha=$(echo "$api_url" | grep -oP 'production/\K[^/]+' | head -1)
        if [[ -z "$commit_sha" ]]; then
            err "Could not extract commit sha from API URL for $nix_plat: $api_url"
            exit 1
        fi
        NEW_COMMITS[$nix_plat]="$commit_sha"

        # Reconstruct the canonical URL exactly as written into package.nix and
        # prefetch the hash from THAT, so the recorded hash always matches what
        # Nix will actually download.
        local canonical_url="https://downloads.cursor.com/production/${commit_sha}/${PATH_MAP[$nix_plat]}"
        NEW_URLS[$nix_plat]="$canonical_url"

        log "Prefetching $nix_plat from $canonical_url ..."
        local hash
        hash=$(prefetch_hash "$canonical_url")
        NEW_HASHES[$nix_plat]="$hash"
        log "$nix_plat: commit=$commit_sha hash=$hash"
    done

    log "All platforms ready. Updating package.nix..."

    # Update version
    sed -i "s/version = \"[^\"]*\"/version = \"$latest_version\"/" "$PACKAGE_FILE"

    # Update each platform's commit sha and hash
    for nix_plat in "${!API_MAP[@]}"; do
        local old_commit
        old_commit=$(sed -n "/${nix_plat} = fetchurl/,/};/{s|.*production/\([^/]*\)/.*|\1|p;}" "$PACKAGE_FILE" | head -1)
        local new_commit="${NEW_COMMITS[$nix_plat]}"
        local new_hash="${NEW_HASHES[$nix_plat]}"

        # Replace commit sha in the URL for this platform block
        sed -i "/${nix_plat} = fetchurl/,/};/s|production/${old_commit}/|production/${new_commit}/|" "$PACKAGE_FILE"

        # Replace hash in this platform block
        sed -i "/${nix_plat} = fetchurl/,/};/s|hash = \"[^\"]*\"|hash = \"${new_hash}\"|" "$PACKAGE_FILE"
    done

    log "Update completed: $current_version -> $latest_version"
}

main "$@"
