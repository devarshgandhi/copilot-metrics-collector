#!/bin/bash

################################################################################
# GitHub Copilot Enterprise User-Level Metrics Script (2026 API)
# 
# Description: Captures per-user Copilot metrics across all orgs in enterprise
# Requirements: curl, jq, openssl
# API Version: 2022-11-28 (Latest endpoints)
# 
# Usage:
#   ./capture-enterprise-users.sh                    # Yesterday's user metrics
#   ./capture-enterprise-users.sh 2026-02-15         # Specific date
#
# Output Formats:
#   - NDJSON: Raw per-user data from API
#   - CSV: Spreadsheet-compatible format
#   - TXT: Human-readable summary
#
# Environment Variables:
#   GITHUB_APP_ID              - Your GitHub App ID
#   GITHUB_INSTALLATION_ID     - Your GitHub App Installation ID
#   GITHUB_PRIVATE_KEY_PATH    - Path to your GitHub App private key (.pem)
#   GITHUB_ENTERPRISE          - Your GitHub Enterprise slug
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
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
    [ -z "$GITHUB_ENTERPRISE" ] && missing_vars+=("GITHUB_ENTERPRISE")
    
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
    
    log_info "Authenticating..."
    local response=$(curl -s -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $jwt" \
        "${GITHUB_API_URL}/app/installations/${installation_id}/access_tokens")
    
    local token=$(echo "$response" | jq -r '.token')
    [ "$token" == "null" ] && { log_error "Auth failed"; exit 1; }
    echo "$token"
}

fetch_enterprise_user_metrics() {
    local token=$1
    local enterprise=$2
    local day=$3
    
    local url="${GITHUB_API_URL}/enterprises/${enterprise}/copilot/metrics/reports/users-1-day?day=${day}"
    
    log_info "Fetching Enterprise User Metrics: $enterprise"
    log_info "Date: $day"
    log_info "Using API: /enterprises/{enterprise}/copilot/metrics/reports/users-1-day"
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url")
    
    local error_message=$(echo "$response" | jq -r '.message // empty')
    [ -n "$error_message" ] && { log_error "API Error: $error_message"; echo "$response" | jq '.'; exit 1; }
    
    local download_links=$(echo "$response" | jq -r '.download_links[]?' 2>/dev/null)
    [ -z "$download_links" ] && { log_error "No download links found"; echo "$response" | jq '.'; exit 1; }
    
    local combined_data=""
    for link in $download_links; do
        log_info "Downloading user metrics report..."
        combined_data="${combined_data}$(curl -s "$link")"$'\n'
    done
    
    echo "$combined_data"
}

display_user_metrics() {
    local metrics=$1
    local output_file=$2
    local date=$3
    
    echo "========================================" | tee "$output_file"
    echo "GitHub Copilot Enterprise User Metrics (2026 API)" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "Enterprise: $GITHUB_ENTERPRISE" | tee -a "$output_file"
    echo "Date: $date" | tee -a "$output_file"
    echo "----------------------------------------" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    # Count unique users
    local total_users=$(echo "$metrics" | jq -s 'length')
    local active_users=$(echo "$metrics" | jq -s '[.[] | select(.copilot_ide_code_completions.total_code_acceptances > 0)] | length')
    local total_acceptances=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_code_acceptances // 0] | add')
    local total_suggestions=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_code_suggestions // 0] | add')
    
    echo "Total Users in Report: $total_users" | tee -a "$output_file"
    echo "Active Users (with acceptances): $active_users" | tee -a "$output_file"
    echo "Total Code Acceptances: $total_acceptances" | tee -a "$output_file"
    echo "Total Code Suggestions: $total_suggestions" | tee -a "$output_file"
    
    if [ "$total_suggestions" -gt 0 ]; then
        local acceptance_rate=$(echo "scale=2; ($total_acceptances * 100) / $total_suggestions" | bc)
        echo "Acceptance Rate: ${acceptance_rate}%" | tee -a "$output_file"
    fi
    
    echo "" | tee -a "$output_file"
    echo "📊 Top Users by Acceptances:" | tee -a "$output_file"
    echo "$metrics" | jq -s 'sort_by(-.copilot_ide_code_completions.total_code_acceptances) | .[:10] | .[] | "  \(.user_login): \(.copilot_ide_code_completions.total_code_acceptances) acceptances"' -r | tee -a "$output_file"
    
    echo "" | tee -a "$output_file"
    echo "✨ Per-user enterprise metrics include:" | tee -a "$output_file"
    echo "  - Individual productivity across all orgs" | tee -a "$output_file"
    echo "  - User-level model usage" | tee -a "$output_file"
    echo "  - Per-user IDE and language breakdown" | tee -a "$output_file"
    echo "  - Chat and agent adoption per user" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "See JSON for complete per-user details" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
}

generate_csv() {
    local metrics=$1
    local csv_file=$2
    
    log_info "Generating CSV output..."
    
    # CSV Header
    echo "date,user_login,total_code_acceptances,total_code_suggestions,acceptance_rate,total_lines_accepted,total_lines_suggested,total_chats,copilot_ide_chat,copilot_dotcom_chat" > "$csv_file"
    
    # CSV Data
    echo "$metrics" | jq -r '
        .date as $date |
        .user_login as $user |
        (.copilot_ide_code_completions.total_code_acceptances // 0) as $accept |
        (.copilot_ide_code_completions.total_code_suggestions // 0) as $suggest |
        (.copilot_ide_code_completions.total_code_lines_accepted // 0) as $lines_accept |
        (.copilot_ide_code_completions.total_code_lines_suggested // 0) as $lines_suggest |
        ((.copilot_ide_chat.total_chats // 0) + (.copilot_dotcom_chat.total_chats // 0)) as $total_chats |
        (.copilot_ide_chat.total_chats // 0) as $ide_chat |
        (.copilot_dotcom_chat.total_chats // 0) as $dotcom_chat |
        (if $suggest > 0 then ($accept * 100 / $suggest) else 0 end) as $rate |
        "\($date),\($user),\($accept),\($suggest),\($rate | floor),\($lines_accept),\($lines_suggest),\($total_chats),\($ide_chat),\($dotcom_chat)"
    ' >> "$csv_file"
}

main() {
    log_info "Starting Enterprise User Metrics Collection (2026 API)"
    check_dependencies
    check_env_vars
    
    local target_date=""
    if [ $# -eq 1 ]; then
        target_date=$1
    elif [ $# -eq 0 ]; then
        target_date=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
    else
        log_error "Usage: $0 [date]"
        exit 1
    fi
    
    mkdir -p "$OUTPUT_DIR"
    
    JWT=$(generate_jwt "$GITHUB_APP_ID" "$GITHUB_PRIVATE_KEY_PATH")
    TOKEN=$(get_installation_token "$JWT" "$GITHUB_INSTALLATION_ID")
    log_success "Authenticated"
    
    METRICS=$(fetch_enterprise_user_metrics "$TOKEN" "$GITHUB_ENTERPRISE" "$target_date")
    
    local ndjson_output="${OUTPUT_DIR}/copilot-enterprise-users-${GITHUB_ENTERPRISE}-${target_date}.ndjson"
    local csv_output="${OUTPUT_DIR}/copilot-enterprise-users-${GITHUB_ENTERPRISE}-${target_date}.csv"
    local text_output="${OUTPUT_DIR}/copilot-enterprise-users-${GITHUB_ENTERPRISE}-${target_date}.txt"
    
    echo "$METRICS" > "$ndjson_output"
    log_success "NDJSON saved: $ndjson_output"
    
    generate_csv "$METRICS" "$csv_output"
    log_success "CSV saved: $csv_output"
    
    display_user_metrics "$METRICS" "$text_output" "$target_date"
    log_success "Text summary saved: $text_output"
    
    echo ""
    log_success "Enterprise user metrics collection completed!"
    log_info "Output formats:"
    log_info "  NDJSON: $ndjson_output (raw API data)"
    log_info "  CSV:    $csv_output (spreadsheet import)"
    log_info "  TXT:    $text_output (human readable)"
}

main "$@"
