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
    
    local output_file="${OUTPUT_DIR}/copilot-trends-${GITHUB_ORG}-${start_date}-to-${end_date}.txt"
    
    echo "========================================" | tee "$output_file"
    echo "GitHub Copilot Trends (2026 API)" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "Organization: $GITHUB_ORG" | tee -a "$output_file"
    echo "Date Range: $start_date to $end_date" | tee -a "$output_file"
    echo "----------------------------------------" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    local dates=($(generate_date_list "$start_date" "$end_date"))
    
    for date in "${dates[@]}"; do
        log_info "Fetching: $date"
        local metrics=$(fetch_metrics_for_date "$TOKEN" "$GITHUB_ORG" "$date")
        
        if [ -n "$metrics" ]; then
            local active=$(echo "$metrics" | jq -s 'length')
            local acceptances=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_code_acceptances // 0] | add')
            printf "%-12s | Active: %3d | Acceptances: %6d\n" "$date" "$active" "$acceptances" | tee -a "$output_file"
        else
            printf "%-12s | No data\n" "$date" | tee -a "$output_file"
        fi
        
        sleep 1  # Rate limit protection
    done
    
    echo "" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    
    log_success "Trends saved to: $output_file"
}

main "$@"
