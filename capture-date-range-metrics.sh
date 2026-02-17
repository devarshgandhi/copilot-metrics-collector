#!/bin/bash

################################################################################
# GitHub Copilot Date Range Metrics Script (2026 API)
# 
# Description: Collects metrics for multiple dates and shows trends
# Requirements: curl, jq, openssl
# API Version: 2022-11-28 (Latest endpoints from Feb 2026)
# 
# Usage:
#   ./capture-date-range-metrics.sh 2024-12-01 2024-12-15    # Date range
#   ./capture-date-range-metrics.sh                           # Last 7 days
#
# Output Formats:
#   - NDJSON: Raw per-user data from API
#   - CSV: Spreadsheet-compatible format
#   - TXT: Human-readable summary
#
# Environment Variables:
#   GITHUB_APP_ID, GITHUB_INSTALLATION_ID, GITHUB_PRIVATE_KEY_PATH, GITHUB_ORG
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
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    local missing_deps=()
    for cmd in curl jq openssl base64 bc date; do
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
    
    local response=$(curl -s -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $jwt" \
        "${GITHUB_API_URL}/app/installations/${installation_id}/access_tokens")
    
    local token=$(echo "$response" | jq -r '.token')
    [ "$token" == "null" ] && { log_error "Auth failed"; exit 1; }
    echo "$token"
}

fetch_metrics_for_date() {
    local token=$1
    local org=$2
    local day=$3
    
    local url="${GITHUB_API_URL}/orgs/${org}/copilot/metrics/reports/organization-1-day?day=${day}"
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url")
    
    local download_links=$(echo "$response" | jq -r '.download_links[]?' 2>/dev/null)
    [ -z "$download_links" ] && { echo ""; return; }
    
    local combined_data=""
    for link in $download_links; do
        combined_data="${combined_data}$(curl -s "$link")"$'\n'
    done
    
    echo "$combined_data"
}

generate_date_list() {
    local start_date=$1
    local end_date=$2
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        local current=$(date -j -f "%Y-%m-%d" "$start_date" +%s)
        local end=$(date -j -f "%Y-%m-%d" "$end_date" +%s)
        
        while [ $current -le $end ]; do
            date -j -f %s $current +%Y-%m-%d
            current=$((current + 86400))
        done
    else
        # Linux
        local current=$(date -d "$start_date" +%s)
        local end=$(date -d "$end_date" +%s)
        
        while [ $current -le $end ]; do
            date -d "@$current" +%Y-%m-%d
            current=$((current + 86400))
        done
    fi
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
    log_info "Starting Date Range Metrics Collection (2026 API)"
    check_dependencies
    check_env_vars
    
    local start_date end_date
    
    if [ $# -eq 2 ]; then
        start_date=$1
        end_date=$2
    elif [ $# -eq 0 ]; then
        # Default: last 7 days
        if [[ "$OSTYPE" == "darwin"* ]]; then
            end_date=$(date -v-1d +%Y-%m-%d)
            start_date=$(date -v-7d +%Y-%m-%d)
        else
            end_date=$(date -d "yesterday" +%Y-%m-%d)
            start_date=$(date -d "7 days ago" +%Y-%m-%d)
        fi
    else
        log_error "Usage: $0 [start_date end_date]"
        exit 1
    fi
    
    log_info "Collecting metrics from $start_date to $end_date"
    mkdir -p "$OUTPUT_DIR"
    
    JWT=$(generate_jwt "$GITHUB_APP_ID" "$GITHUB_PRIVATE_KEY_PATH")
    TOKEN=$(get_installation_token "$JWT" "$GITHUB_INSTALLATION_ID")
    log_success "Authenticated"
    
    local ndjson_output="${OUTPUT_DIR}/copilot-trends-${GITHUB_ORG}-${start_date}-to-${end_date}.ndjson"
    local csv_output="${OUTPUT_DIR}/copilot-trends-${GITHUB_ORG}-${start_date}-to-${end_date}.csv"
    local text_output="${OUTPUT_DIR}/copilot-trends-${GITHUB_ORG}-${start_date}-to-${end_date}.txt"
    
    echo "========================================" | tee "$text_output"
    echo "GitHub Copilot Trends (2026 API)" | tee -a "$text_output"
    echo "========================================" | tee -a "$text_output"
    echo "" | tee -a "$text_output"
    echo "Organization: $GITHUB_ORG" | tee -a "$text_output"
    echo "Date Range: $start_date to $end_date" | tee -a "$text_output"
    echo "----------------------------------------" | tee -a "$text_output"
    echo "" | tee -a "$text_output"
    
    local dates=($(generate_date_list "$start_date" "$end_date"))
    local all_metrics=""
    
    for date in "${dates[@]}"; do
        log_info "Fetching: $date"
        local metrics=$(fetch_metrics_for_date "$TOKEN" "$GITHUB_ORG" "$date")
        
        if [ -n "$metrics" ]; then
            all_metrics="${all_metrics}${metrics}"
            local active=$(echo "$metrics" | jq -s 'length')
            local acceptances=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_code_acceptances // 0] | add')
            printf "%-12s | Active: %3d | Acceptances: %6d\n" "$date" "$active" "$acceptances" | tee -a "$text_output"
        else
            printf "%-12s | No data\n" "$date" | tee -a "$text_output"
        fi
        
        sleep 1  # Rate limit protection
    done
    
    echo "" | tee -a "$text_output"
    echo "========================================" | tee -a "$text_output"
    
    # Save NDJSON output
    echo "$all_metrics" > "$ndjson_output"
    log_success "NDJSON saved: $ndjson_output"
    
    # Generate CSV output
    generate_csv "$all_metrics" "$csv_output"
    log_success "CSV saved: $csv_output"
    
    log_success "Text summary saved: $text_output"
    
    echo ""
    log_success "Date range metrics collection completed!"
    log_info "Output formats:"
    log_info "  NDJSON: $ndjson_output (raw API data)"
    log_info "  CSV:    $csv_output (spreadsheet import)"
    log_info "  TXT:    $text_output (human readable)"
}

main "$@"
