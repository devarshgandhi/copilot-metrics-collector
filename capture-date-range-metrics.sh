#!/bin/bash

################################################################################
# GitHub Copilot Date Range Metrics Script
# 
# Description: Advanced metrics collection with date ranges and trend analysis
# Requirements: curl, jq, openssl, bc
# 
# Usage:
#   ./capture-date-range-metrics.sh --period weekly --weeks 4
#   ./capture-date-range-metrics.sh --period monthly --months 3
#   ./capture-date-range-metrics.sh --from 2024-12-01 --to 2024-12-31
#   ./capture-date-range-metrics.sh --compare-periods --current 2024-12 --previous 2024-11
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
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
GITHUB_API_URL="${GITHUB_API_URL:-https://api.github.com}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
PERIOD=""
WEEKS=0
MONTHS=0
FROM_DATE=""
TO_DATE=""
SHOW_TRENDS=false
COMPARE_MODE=false

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

log_trend() {
    echo -e "${CYAN}[TREND]${NC} $1"
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    for cmd in curl jq openssl base64 bc date; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
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
        exit 1
    fi
    
    echo "$token"
}

# Function to calculate date ranges
calculate_date_range() {
    local period=$1
    local count=$2
    
    local end_date=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
    local start_date=""
    
    case $period in
        weekly)
            local days=$((count * 7))
            start_date=$(date -v-${days}d +%Y-%m-%d 2>/dev/null || date -d "$days days ago" +%Y-%m-%d)
            ;;
        monthly)
            local months=$count
            start_date=$(date -v-${months}m +%Y-%m-%d 2>/dev/null || date -d "$months months ago" +%Y-%m-%d)
            ;;
        *)
            log_error "Unknown period: $period"
            exit 1
            ;;
    esac
    
    echo "$start_date $end_date"
}

# Function to fetch metrics for date range
fetch_metrics_range() {
    local token=$1
    local org=$2
    local from=$3
    local to=$4
    
    log_info "Fetching metrics from $from to $to"
    
    # API limits to 28 days, so we need to batch if needed
    local url="${GITHUB_API_URL}/orgs/${org}/copilot/usage?since=${from}&until=${to}"
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "$url")
    
    local error_message=$(echo "$response" | jq -r '.message // empty')
    if [ -n "$error_message" ]; then
        log_error "API Error: $error_message"
        exit 1
    fi
    
    echo "$response"
}

# Function to calculate trends
calculate_trends() {
    local metrics=$1
    local output_file=$2
    
    echo "========================================" | tee "$output_file"
    echo "GitHub Copilot Metrics Trend Analysis" | tee -a "$output_file"
    echo "Organization: $GITHUB_ORG" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    local count=$(echo "$metrics" | jq 'length')
    
    if [ "$count" -lt 2 ]; then
        log_warning "Need at least 2 data points for trend analysis"
        return
    fi
    
    # Calculate averages
    local avg_active_users=$(echo "$metrics" | jq '[.[].total_active_users // 0] | add / length | round')
    local avg_suggestions=$(echo "$metrics" | jq '[.[].total_suggestions_count // 0] | add / length | round')
    local avg_acceptances=$(echo "$metrics" | jq '[.[].total_acceptances_count // 0] | add / length | round')
    local avg_acceptance_rate=$(echo "$metrics" | jq '[.[]] | map(select(.total_suggestions_count > 0) | (.total_acceptances_count / .total_suggestions_count * 100)) | add / length | round')
    
    echo "Period Averages:" | tee -a "$output_file"
    echo "  Average Active Users: $avg_active_users" | tee -a "$output_file"
    echo "  Average Daily Suggestions: $avg_suggestions" | tee -a "$output_file"
    echo "  Average Daily Acceptances: $avg_acceptances" | tee -a "$output_file"
    echo "  Average Acceptance Rate: ${avg_acceptance_rate}%" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    # Calculate growth rates (first vs last)
    local first_active=$(echo "$metrics" | jq '.[0].total_active_users // 0')
    local last_active=$(echo "$metrics" | jq '.[-1].total_active_users // 0')
    
    if [ "$first_active" -gt 0 ]; then
        local growth_rate=$(echo "scale=2; (($last_active - $first_active) * 100) / $first_active" | bc)
        echo "Growth Metrics:" | tee -a "$output_file"
        echo "  Active Users Growth: ${growth_rate}%" | tee -a "$output_file"
        
        if (( $(echo "$growth_rate > 0" | bc -l) )); then
            log_trend "📈 Active users growing by ${growth_rate}%"
        elif (( $(echo "$growth_rate < 0" | bc -l) )); then
            log_trend "📉 Active users declining by ${growth_rate}%"
        else
            log_trend "➡️  Active users stable"
        fi
    fi
    
    echo "" | tee -a "$output_file"
    
    # Daily breakdown
    echo "Daily Breakdown:" | tee -a "$output_file"
    echo "----------------------------------------" | tee -a "$output_file"
    
    for i in $(seq 0 $((count - 1))); do
        local day_metrics=$(echo "$metrics" | jq ".[$i]")
        local date=$(echo "$day_metrics" | jq -r '.day')
        local active=$(echo "$day_metrics" | jq -r '.total_active_users // 0')
        local suggestions=$(echo "$day_metrics" | jq -r '.total_suggestions_count // 0')
        local acceptances=$(echo "$day_metrics" | jq -r '.total_acceptances_count // 0')
        
        local rate=0
        if [ "$suggestions" -gt 0 ]; then
            rate=$(echo "scale=1; ($acceptances * 100) / $suggestions" | bc)
        fi
        
        printf "%s | Users: %4d | Suggestions: %6d | Acceptances: %6d | Rate: %5.1f%%\n" \
            "$date" "$active" "$suggestions" "$acceptances" "$rate" | tee -a "$output_file"
    done
    
    echo "" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
}

# Function to export to CSV with trends
export_trends_csv() {
    local metrics=$1
    local csv_file=$2
    
    echo "date,active_users,engaged_users,suggestions,acceptances,acceptance_rate,lines_suggested,lines_accepted,chat_users,chat_turns,day_of_week" > "$csv_file"
    
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
        
        # Get day of week (for weekly patterns)
        local day_of_week=$(date -j -f "%Y-%m-%d" "$date" "+%A" 2>/dev/null || date -d "$date" "+%A" 2>/dev/null || echo "Unknown")
        
        local rate=0
        if [ "$suggestions" -gt 0 ]; then
            rate=$(echo "scale=2; ($acceptances * 100) / $suggestions" | bc)
        fi
        
        echo "$date,$active,$engaged,$suggestions,$acceptances,$rate,$lines_suggested,$lines_accepted,$chat_users,$chat_turns,$day_of_week" >> "$csv_file"
    done
    
    log_success "Trends CSV exported to: $csv_file"
}

# Main script
main() {
    log_info "Starting GitHub Copilot Date Range Metrics Collection"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --period)
                PERIOD="$2"
                shift 2
                ;;
            --weeks)
                WEEKS="$2"
                shift 2
                ;;
            --months)
                MONTHS="$2"
                shift 2
                ;;
            --from)
                FROM_DATE="$2"
                shift 2
                ;;
            --to)
                TO_DATE="$2"
                shift 2
                ;;
            --show-trends)
                SHOW_TRENDS=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Usage: $0 [--period weekly|monthly] [--weeks N] [--months N] [--from YYYY-MM-DD] [--to YYYY-MM-DD] [--show-trends]"
                exit 1
                ;;
        esac
    done
    
    check_dependencies
    check_env_vars
    
    # Determine date range
    if [ -n "$FROM_DATE" ] && [ -n "$TO_DATE" ]; then
        log_info "Using custom date range: $FROM_DATE to $TO_DATE"
    elif [ "$PERIOD" == "weekly" ] && [ "$WEEKS" -gt 0 ]; then
        read FROM_DATE TO_DATE <<< $(calculate_date_range "weekly" "$WEEKS")
        log_info "Using weekly period: Last $WEEKS weeks ($FROM_DATE to $TO_DATE)"
    elif [ "$PERIOD" == "monthly" ] && [ "$MONTHS" -gt 0 ]; then
        read FROM_DATE TO_DATE <<< $(calculate_date_range "monthly" "$MONTHS")
        log_info "Using monthly period: Last $MONTHS months ($FROM_DATE to $TO_DATE)"
    else
        log_error "Must specify either --from/--to or --period with --weeks/--months"
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Generate JWT and get token
    log_info "Generating JWT token..."
    JWT=$(generate_jwt "$GITHUB_APP_ID" "$GITHUB_PRIVATE_KEY_PATH")
    TOKEN=$(get_installation_token "$JWT" "$GITHUB_INSTALLATION_ID")
    log_success "Successfully authenticated"
    
    # Fetch metrics
    METRICS=$(fetch_metrics_range "$TOKEN" "$GITHUB_ORG" "$FROM_DATE" "$TO_DATE")
    
    # Create output filenames
    local date_suffix="${FROM_DATE}_to_${TO_DATE}"
    local json_output="${OUTPUT_DIR}/copilot-metrics-range-${GITHUB_ORG}-${date_suffix}.json"
    local trend_output="${OUTPUT_DIR}/copilot-metrics-trends-${GITHUB_ORG}-${date_suffix}.txt"
    local csv_output="${OUTPUT_DIR}/copilot-metrics-trends-${GITHUB_ORG}-${date_suffix}.csv"
    
    # Save raw JSON
    echo "$METRICS" | jq '.' > "$json_output"
    log_success "Raw metrics saved to: $json_output"
    
    # Calculate and display trends
    calculate_trends "$METRICS" "$trend_output"
    
    # Export to CSV
    export_trends_csv "$METRICS" "$csv_output"
    
    log_success "Date range metrics collection completed successfully!"
}

# Run main function
main "$@"
