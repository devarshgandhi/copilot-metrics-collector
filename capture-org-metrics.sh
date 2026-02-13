#!/bin/bash

################################################################################
# GitHub Copilot Organization Metrics Capture Script (2026 API)
# 
# Description: Captures GitHub Copilot usage metrics using the latest API
# Requirements: curl, jq, openssl
# API Version: 2022-11-28 (Latest endpoints from Feb 2026)
# 
# Usage:
#   ./capture-org-metrics.sh                    # Yesterday's metrics
#   ./capture-org-metrics.sh 2024-12-15         # Specific date
#
# Environment Variables:
#   GITHUB_APP_ID              - Your GitHub App ID
#   GITHUB_INSTALLATION_ID     - Your GitHub App Installation ID
#   GITHUB_PRIVATE_KEY_PATH    - Path to your GitHub App private key (.pem)
#   GITHUB_ORG                 - Your GitHub organization name
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"

# Function to print colored messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl jq openssl base64 bc; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Install with: brew install ${missing_deps[*]} (macOS) or apt-get install ${missing_deps[*]} (Linux)"
        exit 1
    fi
}

# Function to check environment variables
check_env_vars() {
    local missing_vars=()
    
    [ -z "$GITHUB_APP_ID" ] && missing_vars+=("GITHUB_APP_ID")
    [ -z "$GITHUB_INSTALLATION_ID" ] && missing_vars+=("GITHUB_INSTALLATION_ID")
    [ -z "$GITHUB_PRIVATE_KEY_PATH" ] && missing_vars+=("GITHUB_PRIVATE_KEY_PATH")
    [ -z "$GITHUB_ORG" ] && missing_vars+=("GITHUB_ORG")
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        echo ""
        echo "Please set the following environment variables:"
        echo "  export GITHUB_APP_ID=\"your-app-id\""
        echo "  export GITHUB_INSTALLATION_ID=\"your-installation-id\""
        echo "  export GITHUB_PRIVATE_KEY_PATH=\"/path/to/private-key.pem\""
        echo "  export GITHUB_ORG=\"your-org-name\""
        exit 1
    fi
    
    if [ ! -f "$GITHUB_PRIVATE_KEY_PATH" ]; then
        log_error "Private key file not found: $GITHUB_PRIVATE_KEY_PATH"
        exit 1
    fi
}

# Function to generate JWT token
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
    
    local signature=$(echo -n "${header_b64}.${payload_b64}" | \
                     openssl dgst -sha256 -sign "$private_key_path" | \
                     openssl base64 -e -A | \
                     tr '+/' '-_' | \
                     tr -d '=')
    
    echo "${header_b64}.${payload_b64}.${signature}"
}

# Function to get installation access token
get_installation_token() {
    local jwt=$1
    local installation_id=$2
    
    log_info "Obtaining installation access token..."
    
    local response=$(curl -s -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $jwt" \
        "${GITHUB_API_URL}/app/installations/${installation_id}/access_tokens")
    
    local token=$(echo "$response" | jq -r '.token')
    
    if [ "$token" == "null" ] || [ -z "$token" ]; then
        log_error "Failed to obtain installation token"
        echo "$response" | jq '.'
        exit 1
    fi
    
    echo "$token"
}

# Function to fetch Copilot metrics using NEW API (2026)
fetch_copilot_metrics() {
    local token=$1
    local org=$2
    local day=$3
    
    local url="${GITHUB_API_URL}/orgs/${org}/copilot/metrics/reports/organization-1-day?day=${day}"
    
    log_info "Fetching Copilot metrics for organization: $org"
    log_info "Date: $day"
    log_info "Using NEW API: /orgs/{org}/copilot/metrics/reports/organization-1-day"
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url")
    
    local error_message=$(echo "$response" | jq -r '.message // empty')
    if [ -n "$error_message" ]; then
        log_error "API Error: $error_message"
        echo "$response" | jq '.'
        exit 1
    fi
    
    # New API returns download links
    local download_links=$(echo "$response" | jq -r '.download_links[]' 2>/dev/null)
    
    if [ -z "$download_links" ]; then
        log_error "No download links found in response"
        echo "$response" | jq '.'
        exit 1
    fi
    
    # Download and combine all NDJSON reports
    local combined_data=""
    for link in $download_links; do
        log_info "Downloading report from: ${link:0:50}..."
        local report_data=$(curl -s "$link")
        combined_data="${combined_data}${report_data}"$'\n'
    done
    
    echo "$combined_data"
}

# Function to display metrics from NDJSON
display_metrics() {
    local metrics=$1
    local output_file=$2
    local date=$3
    
    echo "========================================" | tee "$output_file"
    echo "GitHub Copilot Usage Metrics (2026 API)" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    echo "Date: $date" | tee -a "$output_file"
    echo "Organization: $GITHUB_ORG" | tee -a "$output_file"
    echo "----------------------------------------" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    # Parse NDJSON metrics
    # Note: New API provides more detailed per-user metrics
    local total_suggestions=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_engaged_users // 0] | add')
    local total_acceptances=$(echo "$metrics" | jq -s '[.[] | .copilot_ide_code_completions.total_code_acceptances // 0] | add')
    local active_users=$(echo "$metrics" | jq -s '[.[] | select(.copilot_ide_code_completions.total_code_acceptances > 0)] | length')
    
    echo "Active Users: $active_users" | tee -a "$output_file"
    echo "Total Code Suggestions: $total_suggestions" | tee -a "$output_file"
    echo "Total Acceptances: $total_acceptances" | tee -a "$output_file"
    
    if [ "$total_suggestions" -gt 0 ]; then
        local acceptance_rate=$(echo "scale=2; ($total_acceptances * 100) / $total_suggestions" | bc)
        echo "Acceptance Rate: ${acceptance_rate}%" | tee -a "$output_file"
    fi
    
    echo "" | tee -a "$output_file"
    echo "✨ New API provides enhanced metrics including:" | tee -a "$output_file"
    echo "  - Model usage (GPT-4, Claude, etc.)" | tee -a "$output_file"
    echo "  - Per-user engagement data" | tee -a "$output_file"
    echo "  - IDE/Agent breakdown" | tee -a "$output_file"
    echo "  - Language-specific metrics" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "See JSON file for complete detailed metrics" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
}

# Main script
main() {
    log_info "Starting GitHub Copilot Metrics Collection (2026 API)"
    
    check_dependencies
    check_env_vars
    
    # Parse date argument
    local target_date=""
    
    if [ $# -eq 1 ]; then
        target_date=$1
    elif [ $# -eq 0 ]; then
        # Default to yesterday
        target_date=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
    else
        log_error "Invalid arguments"
        echo "Usage: $0 [date]"
        echo "  No arguments: Yesterday's metrics"
        echo "  One argument:  Specific date (YYYY-MM-DD)"
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Generate JWT
    log_info "Generating JWT token..."
    JWT=$(generate_jwt "$GITHUB_APP_ID" "$GITHUB_PRIVATE_KEY_PATH")
    
    # Get installation token
    TOKEN=$(get_installation_token "$JWT" "$GITHUB_INSTALLATION_ID")
    log_success "Successfully authenticated"
    
    # Fetch metrics
    METRICS=$(fetch_copilot_metrics "$TOKEN" "$GITHUB_ORG" "$target_date")
    
    # Create output filenames
    local json_output="${OUTPUT_DIR}/copilot-metrics-${GITHUB_ORG}-${target_date}.json"
    local text_output="${OUTPUT_DIR}/copilot-metrics-${GITHUB_ORG}-${target_date}.txt"
    
    # Save NDJSON
    echo "$METRICS" > "$json_output"
    log_success "Raw metrics saved to: $json_output"
    
    # Display and save formatted metrics
    display_metrics "$METRICS" "$text_output" "$target_date"
    
    log_success "Metrics collection completed successfully!"
    log_info "Note: Using latest 2026 API with enhanced metrics"
}

# Run main function
main "$@"
