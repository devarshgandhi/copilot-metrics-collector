#!/bin/bash

################################################################################
# GitHub Copilot 28-Day Metrics Script (2026 API)
# 
# Description: Captures last 28 days of Copilot metrics in one call
# Requirements: curl, jq, openssl
# API Version: 2022-11-28 (Latest endpoints)
# 
# Usage:
#   ./capture-28day-metrics.sh              # Last 28 days for org
#   ENTERPRISE=true ./capture-28day-metrics.sh  # Last 28 days for enterprise
#
# Environment Variables:
#   GITHUB_APP_ID, GITHUB_INSTALLATION_ID, GITHUB_PRIVATE_KEY_PATH
#   GITHUB_ORG (for org) or GITHUB_ENTERPRISE (for enterprise)
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
    
    if [ "$ENTERPRISE" == "true" ]; then
        [ -z "$GITHUB_ENTERPRISE" ] && missing_vars+=("GITHUB_ENTERPRISE")
    else
        [ -z "$GITHUB_ORG" ] && missing_vars+=("GITHUB_ORG")
    fi
    
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

fetch_28day_metrics() {
    local token=$1
    local target=$2
    local is_enterprise=$3
    
    local url
    if [ "$is_enterprise" == "true" ]; then
        url="${GITHUB_API_URL}/enterprises/${target}/copilot/metrics/reports/enterprise-28-day/latest"
        log_info "Fetching 28-day enterprise metrics: $target"
    else
        url="${GITHUB_API_URL}/orgs/${target}/copilot/metrics/reports/organization-28-day/latest"
        log_info "Fetching 28-day organization metrics: $target"
    fi
    
    log_info "Using API: /*/copilot/metrics/reports/*/28-day/latest"
    
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
        log_info "Downloading report..."
        combined_data="${combined_data}$(curl -s "$link")"$'\n'
    done
    
    echo "$combined_data"
}

display_28day_summary() {
    local metrics=$1
    local output_file=$2
    local target=$3
    local is_enterprise=$4
    
    echo "========================================" | tee "$output_file"
    echo "GitHub Copilot 28-Day Metrics (2026 API)" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    if [ "$is_enterprise" == "true" ]; then
        echo "Enterprise: $target" | tee -a "$output_file"
    else
        echo "Organization: $target" | tee -a "$output_file"
    fi
    
    echo "Period: Last 28 days" | tee -a "$output_file"
    echo "----------------------------------------" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    # Calculate totals across 28 days
    local total_active=$(echo "$metrics" | jq -s '[.[] | select(.copilot_ide_code_completions.total_code_acceptances > 0)] | length')
    local total_acceptances=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_code_acceptances // 0] | add')
    local total_suggestions=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_engaged_users // 0] | add')
    
    echo "Total Active Users: $total_active" | tee -a "$output_file"
    echo "Total Code Acceptances: $total_acceptances" | tee -a "$output_file"
    echo "Total Suggestions: $total_suggestions" | tee -a "$output_file"
    
    if [ "$total_suggestions" -gt 0 ]; then
        local acceptance_rate=$(echo "scale=2; ($total_acceptances * 100) / $total_suggestions" | bc)
        echo "Acceptance Rate: ${acceptance_rate}%" | tee -a "$output_file"
    fi
    
    echo "" | tee -a "$output_file"
    echo "✨ 28-day report includes:" | tee -a "$output_file"
    echo "  - Complete 28-day user activity" | tee -a "$output_file"
    echo "  - Model usage trends" | tee -a "$output_file"
    echo "  - Daily engagement patterns" | tee -a "$output_file"
    echo "  - See JSON for detailed breakdown" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
}

main() {
    log_info "Starting 28-Day Metrics Collection (2026 API)"
    check_dependencies
    check_env_vars
    
    mkdir -p "$OUTPUT_DIR"
    
    JWT=$(generate_jwt "$GITHUB_APP_ID" "$GITHUB_PRIVATE_KEY_PATH")
    TOKEN=$(get_installation_token "$JWT" "$GITHUB_INSTALLATION_ID")
    log_success "Authenticated"
    
    local target is_enterprise
    if [ "$ENTERPRISE" == "true" ]; then
        target="$GITHUB_ENTERPRISE"
        is_enterprise="true"
    else
        target="$GITHUB_ORG"
        is_enterprise="false"
    fi
    
    METRICS=$(fetch_28day_metrics "$TOKEN" "$target" "$is_enterprise")
    
    local timestamp=$(date +%Y-%m-%d)
    local json_output="${OUTPUT_DIR}/copilot-28day-${target}-${timestamp}.json"
    local text_output="${OUTPUT_DIR}/copilot-28day-${target}-${timestamp}.txt"
    
    echo "$METRICS" > "$json_output"
    log_success "Saved: $json_output"
    
    display_28day_summary "$METRICS" "$text_output" "$target" "$is_enterprise"
    log_success "28-day metrics collection completed!"
}

main "$@"
