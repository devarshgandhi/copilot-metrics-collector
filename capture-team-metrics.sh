#!/bin/bash

################################################################################
# GitHub Copilot Team Metrics Capture Script (2026 API)
# 
# Description: Captures team-specific Copilot usage using latest API
# Requirements: curl, jq, openssl
# API Version: 2022-11-28 (Latest endpoints from Feb 2026)
# 
# Usage:
#   ./capture-team-metrics.sh TEAM_SLUG                    # Yesterday
#   ./capture-team-metrics.sh TEAM_SLUG 2024-12-15         # Specific date
#
# Environment Variables:
#   GITHUB_APP_ID              - Your GitHub App ID
#   GITHUB_INSTALLATION_ID     - Your GitHub App Installation ID
#   GITHUB_PRIVATE_KEY_PATH    - Path to your GitHub App private key (.pem)
#   GITHUB_ORG                 - Your GitHub organization name
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    local missing_deps=()
    for cmd in curl jq openssl base64 bc; do
        command -v $cmd &> /dev/null || missing_deps+=($cmd)
    done
    [ ${#missing_deps[@]} -ne 0 ] && { log_error "Missing: ${missing_deps[*]}"; exit 1; }
}

check_env_vars() {
    local missing_vars=()
    [ -z "$GITHUB_APP_ID" ] && missing_vars+=("GITHUB_APP_ID")
    [ -z "$GITHUB_INSTALLATION_ID" ] && missing_vars+=("GITHUB_INSTALLATION_ID")
    [ -z "$GITHUB_PRIVATE_KEY_PATH" ] && missing_vars+=("GITHUB_PRIVATE_KEY_PATH")
    [ -z "$GITHUB_ORG" ] && missing_vars+=("GITHUB_ORG")
    
    [ ${#missing_vars[@]} -ne 0 ] && { log_error "Missing: ${missing_vars[*]}"; exit 1; }
    [ ! -f "$GITHUB_PRIVATE_KEY_PATH" ] && { log_error "Private key not found"; exit 1; }
}

generate_jwt() {
    local app_id=$1
    local private_key_path=$2
    local now=$(date +%s)
    local iat=$((now - 60))
    local exp=$((now + 600))
    
    local header='{"alg":"RS256","typ":"JWT"}'
    local header_b64=$(echo -n "$header" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
    local payload="{\"iat\":${iat},\"exp\":${exp},\"iss\":\"${app_id}\"}"
    local payload_b64=$(echo -n "$payload" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
    local signature=$(echo -n "${header_b64}.${payload_b64}" | openssl dgst -sha256 -sign "$private_key_path" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
    
    echo "${header_b64}.${payload_b64}.${signature}"
}

get_installation_token() {
    local jwt=$1
    local installation_id=$2
    
    log_info "Getting token..."
    local response=$(curl -s -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $jwt" \
        "${GITHUB_API_URL}/app/installations/${installation_id}/access_tokens")
    
    local token=$(echo "$response" | jq -r '.token')
    [ "$token" == "null" ] && { log_error "Auth failed"; exit 1; }
    echo "$token"
}

get_team_members() {
    local token=$1
    local org=$2
    local team=$3
    
    log_info "Fetching team members for: $team"
    local url="${GITHUB_API_URL}/orgs/${org}/teams/${team}/members"
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url")
    
    echo "$response" | jq -r '.[].login' | tr '\n' ',' | sed 's/,$//'
}

fetch_team_metrics() {
    local token=$1
    local org=$2
    local team_members=$3
    local day=$4
    
    log_info "Fetching metrics for team members..."
    log_info "Using NEW API: /orgs/{org}/copilot/metrics/reports/organization-1-day"
    
    local url="${GITHUB_API_URL}/orgs/${org}/copilot/metrics/reports/organization-1-day?day=${day}"
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url")
    
    local download_links=$(echo "$response" | jq -r '.download_links[]' 2>/dev/null)
    [ -z "$download_links" ] && { log_error "No download links"; exit 1; }
    
    # Download and filter for team members
    local combined_data=""
    IFS=',' read -ra MEMBERS <<< "$team_members"
    
    for link in $download_links; do
        log_info "Downloading and filtering report..."
        local report_data=$(curl -s "$link")
        
        # Filter NDJSON for team members only
        for member in "${MEMBERS[@]}"; do
            echo "$report_data" | jq -c "select(.user_login == \"$member\")" >> /tmp/team_filtered.ndjson
        done
    done
    
    cat /tmp/team_filtered.ndjson
    rm -f /tmp/team_filtered.ndjson
}

display_team_metrics() {
    local metrics=$1
    local output_file=$2
    local team=$3
    local date=$4
    
    echo "========================================" | tee "$output_file"
    echo "GitHub Copilot Team Metrics (2026 API)" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "Team: $team" | tee -a "$output_file"
    echo "Organization: $GITHUB_ORG" | tee -a "$output_file"
    echo "Date: $date" | tee -a "$output_file"
    echo "----------------------------------------" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    local active_users=$(echo "$metrics" | jq -s 'length')
    local total_acceptances=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_code_acceptances // 0] | add')
    
    echo "Team Active Users: $active_users" | tee -a "$output_file"
    echo "Total Acceptances: $total_acceptances" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "✨ Per-user team metrics available in JSON file" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
}

main() {
    log_info "Starting Team Metrics Collection (2026 API)"
    check_dependencies
    check_env_vars
    
    if [ $# -lt 1 ] || [ $# -gt 2 ]; then
        log_error "Usage: $0 TEAM_SLUG [date]"
        exit 1
    fi
    
    local team_slug=$1
    local target_date=""
    
    if [ $# -eq 2 ]; then
        target_date=$2
    else
        target_date=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
    fi
    
    mkdir -p "$OUTPUT_DIR"
    
    JWT=$(generate_jwt "$GITHUB_APP_ID" "$GITHUB_PRIVATE_KEY_PATH")
    TOKEN=$(get_installation_token "$JWT" "$GITHUB_INSTALLATION_ID")
    log_success "Authenticated"
    
    TEAM_MEMBERS=$(get_team_members "$TOKEN" "$GITHUB_ORG" "$team_slug")
    [ -z "$TEAM_MEMBERS" ] && { log_error "No team members found"; exit 1; }
    log_success "Found team members"
    
    METRICS=$(fetch_team_metrics "$TOKEN" "$GITHUB_ORG" "$TEAM_MEMBERS" "$target_date")
    
    local json_output="${OUTPUT_DIR}/copilot-team-metrics-${team_slug}-${target_date}.json"
    local text_output="${OUTPUT_DIR}/copilot-team-metrics-${team_slug}-${target_date}.txt"
    
    echo "$METRICS" > "$json_output"
    log_success "Saved: $json_output"
    
    display_team_metrics "$METRICS" "$text_output" "$team_slug" "$target_date"
    log_success "Team metrics collection completed!"
}

main "$@"
