#!/bin/bash

################################################################################
# GitHub Copilot Enterprise Metrics Capture Script
# 
# Description: Captures GitHub Copilot usage metrics at enterprise level
# Requirements: curl, jq, openssl
# 
# Usage:
#   ./capture-enterprise-metrics.sh                    # Yesterday's metrics
#   ./capture-enterprise-metrics.sh 2024-12-15         # Specific date
#   ./capture-enterprise-metrics.sh 2024-12-01 2024-12-28  # Date range
#   ./capture-enterprise-metrics.sh --detailed 2024-12-15  # Include per-org breakdown
#
# Environment Variables:
#   GITHUB_APP_ID              - Your GitHub App ID
#   GITHUB_INSTALLATION_ID     - Your GitHub App Installation ID
#   GITHUB_PRIVATE_KEY_PATH    - Path to your GitHub App private key (.pem)
#   GITHUB_ENTERPRISE          - Your GitHub Enterprise slug
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
DETAILED_MODE=false

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

# Function to check if required commands exist
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
    [ -z "$GITHUB_ENTERPRISE" ] && missing_vars+=("GITHUB_ENTERPRISE")
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        echo ""
        echo "Please set the following environment variables:"
        echo "  export GITHUB_APP_ID=\"your-app-id\""
        echo "  export GITHUB_INSTALLATION_ID=\"your-installation-id\""
        echo "  export GITHUB_PRIVATE_KEY_PATH=\"/path/to/private-key.pem\""
        echo "  export GITHUB_ENTERPRISE=\"your-enterprise-slug\""
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

# Function to fetch enterprise Copilot metrics
fetch_enterprise_metrics() {
    local token=$1
    local enterprise=$2
    local since=$3
    local until=$4
    
    local url="${GITHUB_API_URL}/enterprises/${enterprise}/copilot/usage"
    local params=""
    
    if [ -n "$since" ]; then
        params="?since=${since}"
    fi
    
    if [ -n "$until" ]; then
        if [ -n "$params" ]; then
            params="${params}&until=${until}"
        else
            params="?until=${until}"
        fi
    fi
    
    log_info "Fetching enterprise Copilot metrics for: $enterprise"
    [ -n "$since" ] && log_info "Since: $since"
    [ -n "$until" ] && log_info "Until: $until"
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${url}${params}")
    
    local error_message=$(echo "$response" | jq -r '.message // empty')
    if [ -n "$error_message" ]; then
        log_error "API Error: $error_message"
        echo "$response" | jq '.'
        exit 1
    fi
    
    echo "$response"
}

# Function to fetch list of organizations in enterprise
fetch_enterprise_orgs() {
    local token=$1
    local enterprise=$2
    
    log_info "Fetching organizations in enterprise: $enterprise"
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API_URL}/enterprises/${enterprise}/copilot/billing/seats?per_page=100")
    
    # Extract unique organizations from seats
    local orgs=$(echo "$response" | jq -r '[.seats[]?.assignee.organization.login // empty] | unique | .[]' 2>/dev/null || echo "")
    
    echo "$orgs"
}

# Function to fetch org-level metrics for detailed breakdown
fetch_org_metrics() {
    local token=$1
    local org=$2
    local since=$3
    local until=$4
    
    local url="${GITHUB_API_URL}/orgs/${org}/copilot/usage"
    local params=""
    
    if [ -n "$since" ]; then
        params="?since=${since}"
    fi
    
    if [ -n "$until" ]; then
        if [ -n "$params" ]; then
            params="${params}&until=${until}"
        else
            params="?until=${until}"
        fi
    fi
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${url}${params}")
    
    echo "$response"
}

# Function to display enterprise metrics
display_enterprise_metrics() {
    local metrics=$1
    local output_file=$2
    
    echo "========================================" | tee "$output_file"
    echo "GitHub Copilot Enterprise Metrics" | tee -a "$output_file"
    echo "Enterprise: $GITHUB_ENTERPRISE" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    local count=$(echo "$metrics" | jq 'length')
    
    if [ "$count" -eq 0 ]; then
        log_warning "No metrics data available for the specified date range"
        echo "No data available" | tee -a "$output_file"
        return
    fi
    
    for i in $(seq 0 $((count - 1))); do
        local day_metrics=$(echo "$metrics" | jq ".[$i]")
        local date=$(echo "$day_metrics" | jq -r '.day')
        
        echo "Date: $date" | tee -a "$output_file"
        echo "----------------------------------------" | tee -a "$output_file"
        
        local total_active_users=$(echo "$day_metrics" | jq -r '.total_active_users // 0')
        local total_engaged_users=$(echo "$day_metrics" | jq -r '.total_engaged_users // 0')
        
        echo "Active Users: $total_active_users" | tee -a "$output_file"
        echo "Engaged Users: $total_engaged_users" | tee -a "$output_file"
        
        if [ "$total_engaged_users" -gt 0 ]; then
            local engagement_rate=$(echo "scale=2; ($total_active_users * 100) / $total_engaged_users" | bc)
            echo "Engagement Rate: ${engagement_rate}%" | tee -a "$output_file"
        fi
        
        local total_suggestions=$(echo "$day_metrics" | jq -r '.total_suggestions_count // 0')
        local total_acceptances=$(echo "$day_metrics" | jq -r '.total_acceptances_count // 0')
        local total_lines_suggested=$(echo "$day_metrics" | jq -r '.total_lines_suggested // 0')
        local total_lines_accepted=$(echo "$day_metrics" | jq -r '.total_lines_accepted // 0')
        
        echo "" | tee -a "$output_file"
        echo "Code Completions:" | tee -a "$output_file"
        echo "  Suggestions: $total_suggestions" | tee -a "$output_file"
        echo "  Acceptances: $total_acceptances" | tee -a "$output_file"
        
        if [ "$total_suggestions" -gt 0 ]; then
            local acceptance_rate=$(echo "scale=2; ($total_acceptances * 100) / $total_suggestions" | bc)
            echo "  Acceptance Rate: ${acceptance_rate}%" | tee -a "$output_file"
        fi
        
        echo "  Lines Suggested: $total_lines_suggested" | tee -a "$output_file"
        echo "  Lines Accepted: $total_lines_accepted" | tee -a "$output_file"
        
        if [ "$total_lines_suggested" -gt 0 ]; then
            local lines_efficiency=$(echo "scale=2; ($total_lines_accepted * 100) / $total_lines_suggested" | bc)
            echo "  Lines Efficiency: ${lines_efficiency}%" | tee -a "$output_file"
        fi
        
        local total_chat_users=$(echo "$day_metrics" | jq -r '.total_active_chat_users // 0')
        local total_chat_turns=$(echo "$day_metrics" | jq -r '.total_chat_turns // 0')
        
        echo "" | tee -a "$output_file"
        echo "Copilot Chat:" | tee -a "$output_file"
        echo "  Active Chat Users: $total_chat_users" | tee -a "$output_file"
        echo "  Chat Turns: $total_chat_turns" | tee -a "$output_file"
        
        echo "" | tee -a "$output_file"
        echo "Breakdown by Editor:" | tee -a "$output_file"
        
        local editors=$(echo "$day_metrics" | jq -r '.breakdown[] | select(.editor) | .editor' | sort -u)
        
        while IFS= read -r editor; do
            if [ -n "$editor" ]; then
                local editor_data=$(echo "$day_metrics" | jq ".breakdown[] | select(.editor == \"$editor\")")
                local editor_suggestions=$(echo "$editor_data" | jq -r '.suggestions_count // 0')
                local editor_acceptances=$(echo "$editor_data" | jq -r '.acceptances_count // 0')
                
                echo "  $editor:" | tee -a "$output_file"
                echo "    Suggestions: $editor_suggestions" | tee -a "$output_file"
                echo "    Acceptances: $editor_acceptances" | tee -a "$output_file"
            fi
        done <<< "$editors"
        
        echo "" | tee -a "$output_file"
        echo "========================================" | tee -a "$output_file"
        echo "" | tee -a "$output_file"
    done
}

# Function to export to CSV
export_to_csv() {
    local metrics=$1
    local csv_file=$2
    
    echo "date,active_users,engaged_users,engagement_rate,suggestions,acceptances,acceptance_rate,lines_suggested,lines_accepted,lines_efficiency,chat_users,chat_turns" > "$csv_file"
    
    local count=$(echo "$metrics" | jq 'length')
    
    for i in $(seq 0 $((count - 1))); do
        local day_metrics=$(echo "$metrics" | jq ".[$i]")
        local date=$(echo "$day_metrics" | jq -r '.day')
        local active=$(echo "$day_metrics" | jq -r '.total_active_users // 0')
        local engaged=$(echo "$day_metrics" | jq -r '.total_engaged_users // 0')
        local suggestions=$(echo "$day_metrics" | jq -r '.total_suggestions_count // 0')
        local acceptances=$(echo "$day_metrics" | jq -r '.total_acceptances_count // 0')
        local lines_suggested=$(echo "$day_metrics" | jq -r '.total_lines_suggested // 0')
        local lines_accepted=$(echo "$day_metrics" | jq -r '.total_lines_accepted // 0')
        local chat_users=$(echo "$day_metrics" | jq -r '.total_active_chat_users // 0')
        local chat_turns=$(echo "$day_metrics" | jq -r '.total_chat_turns // 0')
        
        local engagement_rate=0
        if [ "$engaged" -gt 0 ]; then
            engagement_rate=$(echo "scale=2; ($active * 100) / $engaged" | bc)
        fi
        
        local acceptance_rate=0
        if [ "$suggestions" -gt 0 ]; then
            acceptance_rate=$(echo "scale=2; ($acceptances * 100) / $suggestions" | bc)
        fi
        
        local lines_efficiency=0
        if [ "$lines_suggested" -gt 0 ]; then
            lines_efficiency=$(echo "scale=2; ($lines_accepted * 100) / $lines_suggested" | bc)
        fi
        
        echo "$date,$active,$engaged,$engagement_rate,$suggestions,$acceptances,$acceptance_rate,$lines_suggested,$lines_accepted,$lines_efficiency,$chat_users,$chat_turns" >> "$csv_file"
    done
    
    log_success "CSV exported to: $csv_file"
}

# Main script
main() {
    log_info "Starting GitHub Copilot Enterprise Metrics Collection"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --detailed)
                DETAILED_MODE=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    check_dependencies
    check_env_vars
    
    # Parse date arguments
    local since_date=""
    local until_date=""
    
    if [ $# -eq 1 ]; then
        since_date=$1
        until_date=$1
    elif [ $# -eq 2 ]; then
        since_date=$1
        until_date=$2
    elif [ $# -eq 0 ]; then
        since_date=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
        until_date=$since_date
    else
        log_error "Invalid arguments"
        echo "Usage: $0 [--detailed] [since_date] [until_date]"
        exit 1
    fi
    
    # Create output directory if needed
    mkdir -p "$OUTPUT_DIR"
    
    # Generate JWT
    log_info "Generating JWT token..."
    JWT=$(generate_jwt "$GITHUB_APP_ID" "$GITHUB_PRIVATE_KEY_PATH")
    
    # Get installation token
    TOKEN=$(get_installation_token "$JWT" "$GITHUB_INSTALLATION_ID")
    log_success "Successfully authenticated"
    
    # Fetch enterprise metrics
    METRICS=$(fetch_enterprise_metrics "$TOKEN" "$GITHUB_ENTERPRISE" "$since_date" "$until_date")
    
    # Create output filenames
    local date_suffix="${since_date}"
    if [ "$since_date" != "$until_date" ]; then
        date_suffix="${since_date}_to_${until_date}"
    fi
    
    local json_output="${OUTPUT_DIR}/copilot-metrics-enterprise-${GITHUB_ENTERPRISE}-${date_suffix}.json"
    local text_output="${OUTPUT_DIR}/copilot-metrics-enterprise-${GITHUB_ENTERPRISE}-${date_suffix}.txt"
    local csv_output="${OUTPUT_DIR}/copilot-metrics-enterprise-${GITHUB_ENTERPRISE}-${date_suffix}.csv"
    
    # Save raw JSON
    echo "$METRICS" | jq '.' > "$json_output"
    log_success "Raw metrics saved to: $json_output"
    
    # Display and save formatted metrics
    display_enterprise_metrics "$METRICS" "$text_output"
    
    # Export to CSV
    export_to_csv "$METRICS" "$csv_output"
    
    log_success "Metrics collection completed successfully!"
}

# Run main function
main "$@"
