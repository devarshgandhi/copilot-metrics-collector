#!/bin/bash

################################################################################
# GitHub Copilot Enterprise Metrics Capture Script (2026 API)
# 
# Description: Captures enterprise-wide GitHub Copilot usage metrics using latest API
# Requirements: curl, jq, openssl
# API Version: 2022-11-28 (Latest endpoints from Feb 2026)
# 
# Usage:
#   ./capture-enterprise-metrics.sh                    # Yesterday's metrics
#   ./capture-enterprise-metrics.sh 2024-12-15         # Specific date
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
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

check_env_vars() {
    local missing_vars=()
    [ -z "$GITHUB_APP_ID" ] && missing_vars+=("GITHUB_APP_ID")
    [ -z "$GITHUB_INSTALLATION_ID" ] && missing_vars+=("GITHUB_INSTALLATION_ID")
    [ -z "$GITHUB_PRIVATE_KEY_PATH" ] && missing_vars+=("GITHUB_PRIVATE_KEY_PATH")
    [ -z "$GITHUB_ENTERPRISE" ] && missing_vars+=("GITHUB_ENTERPRISE")
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing environment variables: ${missing_vars[*]}"
        exit 1
    fi
    
    [ ! -f "$GITHUB_PRIVATE_KEY_PATH" ] && { log_error "Private key not found: $GITHUB_PRIVATE_KEY_PATH"; exit 1; }
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
    
    log_info "Obtaining installation access token..."
    local response=$(curl -s -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $jwt" \
        "${GITHUB_API_URL}/app/installations/${installation_id}/access_tokens")
    
    local token=$(echo "$response" | jq -r '.token')
    [ "$token" == "null" ] || [ -z "$token" ] && { log_error "Failed to get token"; echo "$response" | jq '.'; exit 1; }
    echo "$token"
}

fetch_enterprise_metrics() {
    local token=$1
    local enterprise=$2
    local day=$3
    
    local url="${GITHUB_API_URL}/enterprises/${enterprise}/copilot/metrics/reports/enterprise-1-day?day=${day}"
    
    log_info "Fetching Enterprise Copilot metrics: $enterprise"
    log_info "Date: $day"
    log_info "Using NEW API: /enterprises/{enterprise}/copilot/metrics/reports/enterprise-1-day"
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url")
    
    local error_message=$(echo "$response" | jq -r '.message // empty')
    [ -n "$error_message" ] && { log_error "API Error: $error_message"; echo "$response" | jq '.'; exit 1; }
    
    local download_links=$(echo "$response" | jq -r '.download_links[]' 2>/dev/null)
    [ -z "$download_links" ] && { log_error "No download links found"; echo "$response" | jq '.'; exit 1; }
    
    local combined_data=""
    for link in $download_links; do
        log_info "Downloading report..."
        combined_data="${combined_data}$(curl -s "$link")"$'\n'
    done
    
    echo "$combined_data"
}

display_enterprise_metrics() {
    local metrics=$1
    local output_file=$2
    local date=$3
    
    echo "========================================" | tee "$output_file"
    echo "GitHub Copilot Enterprise Metrics (2026 API)" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "Date: $date" | tee -a "$output_file"
    echo "Enterprise: $GITHUB_ENTERPRISE" | tee -a "$output_file"
    echo "----------------------------------------" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    local total_suggestions=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_engaged_users // 0] | add')
    local total_acceptances=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_code_acceptances // 0] | add')
    local active_users=$(echo "$metrics" | jq -s '[.[] | select(.copilot_ide_code_completions.total_code_acceptances > 0)] | length')
    
    echo "Enterprise Active Users: $active_users" | tee -a "$output_file"
    echo "Total Code Suggestions: $total_suggestions" | tee -a "$output_file"
    echo "Total Acceptances: $total_acceptances" | tee -a "$output_file"
    
    if [ "$total_suggestions" -gt 0 ]; then
        local acceptance_rate=$(echo "scale=2; ($total_acceptances * 100) / $total_suggestions" | bc)
        echo "Acceptance Rate: ${acceptance_rate}%" | tee -a "$output_file"
    fi
    
    echo "" | tee -a "$output_file"
    echo "✨ Enterprise API provides:" | tee -a "$output_file"
    echo "  - Cross-organization aggregation" | tee -a "$output_file"
    echo "  - Enterprise-wide user engagement" | tee -a "$output_file"
    echo "  - Model usage across all orgs" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
}

main() {
    log_info "Starting Enterprise Metrics Collection (2026 API)"
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
    
    METRICS=$(fetch_enterprise_metrics "$TOKEN" "$GITHUB_ENTERPRISE" "$target_date")
    
    local json_output="${OUTPUT_DIR}/copilot-enterprise-metrics-${GITHUB_ENTERPRISE}-${target_date}.json"
    local text_output="${OUTPUT_DIR}/copilot-enterprise-metrics-${GITHUB_ENTERPRISE}-${target_date}.txt"
    
    echo "$METRICS" > "$json_output"
    log_success "Saved: $json_output"
    
    display_enterprise_metrics "$METRICS" "$text_output" "$target_date"
    log_success "Enterprise metrics collection completed!"
}

main "$@"
