#!/bin/bash

################################################################################
# GitHub Copilot Team Metrics Capture Script
# 
# Description: Captures GitHub Copilot usage metrics for specific teams
# Requirements: curl, jq, openssl
# 
# Usage:
#   ./capture-team-metrics.sh --team engineering 2024-12-15
#   ./capture-team-metrics.sh --teams team-a,team-b 2024-12-01 2024-12-28
#   ./capture-team-metrics.sh --all-teams 2024-12-15
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
TEAMS=()
ALL_TEAMS=false

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
        echo "$response" | jq '.'
        exit 1
    fi
    
    echo "$token"
}

# Function to get all teams in organization
get_all_teams() {
    local token=$1
    local org=$2
    
    log_info "Fetching all teams in organization: $org"
    
    local page=1
    local all_teams=()
    
    while true; do
        local response=$(curl -s -X GET \
            -H "Accept: application/vnd.github+json" \
            -H "Authorization: Bearer $token" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "${GITHUB_API_URL}/orgs/${org}/teams?per_page=100&page=${page}")
        
        local teams=$(echo "$response" | jq -r '.[].slug')
        
        if [ -z "$teams" ]; then
            break
        fi
        
        all_teams+=($teams)
        ((page++))
    done
    
    echo "${all_teams[@]}"
}

# Function to get team members
get_team_members() {
    local token=$1
    local org=$2
    local team=$3
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API_URL}/orgs/${org}/teams/${team}/members?per_page=100")
    
    echo "$response" | jq -r '.[].login'
}

# Function to get Copilot seat info for users
get_copilot_seats() {
    local token=$1
    local org=$2
    
    local response=$(curl -s -X GET \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $token" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${GITHUB_API_URL}/orgs/${org}/copilot/billing/seats?per_page=100")
    
    echo "$response"
}

# Function to fetch org metrics and filter by team members
fetch_team_metrics() {
    local token=$1
    local org=$2
    local team=$3
    local since=$4
    local until=$5
    
    log_info "Fetching metrics for team: $team"
    
    # Get team members
    local members=$(get_team_members "$token" "$org" "$team")
    
    if [ -z "$members" ]; then
        log_warning "No members found in team: $team"
        echo "[]"
        return
    fi
    
    local member_count=$(echo "$members" | wc -l | tr -d ' ')
    log_info "Team $team has $member_count members"
    
    # Get organization-wide metrics
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
    
    # Note: API doesn't provide per-user breakdown, so we return org metrics with team context
    # This is an aggregate view showing org metrics for context
    echo "$response" | jq --arg team "$team" --argjson members "$member_count" '. + [{team: $team, member_count: $members}]'
}

# Function to display team metrics
display_team_metrics() {
    local team=$1
    local metrics=$2
    local output_file=$3
    
    echo "========================================" | tee "$output_file"
    echo "GitHub Copilot Team Metrics" | tee -a "$output_file"
    echo "Organization: $GITHUB_ORG" | tee -a "$output_file"
    echo "Team: $team" | tee -a "$output_file"
    echo "========================================" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    local member_count=$(echo "$metrics" | jq -r '.[-1].member_count // 0')
    echo "Team Size: $member_count members" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    # Remove the team metadata object for metric processing
    local clean_metrics=$(echo "$metrics" | jq '[.[] | select(.day)]')
    
    local count=$(echo "$clean_metrics" | jq 'length')
    
    if [ "$count" -eq 0 ]; then
        log_warning "No metrics data available"
        echo "No data available" | tee -a "$output_file"
        return
    fi
    
    echo "Organization-wide Context:" | tee -a "$output_file"
    echo "(Team-specific breakdowns require GitHub Enterprise Cloud with advanced metrics)" | tee -a "$output_file"
    echo "" | tee -a "$output_file"
    
    for i in $(seq 0 $((count - 1))); do
        local day_metrics=$(echo "$clean_metrics" | jq ".[$i]")
        local date=$(echo "$day_metrics" | jq -r '.day')
        
        echo "Date: $date" | tee -a "$output_file"
        echo "----------------------------------------" | tee -a "$output_file"
        
        local total_active_users=$(echo "$day_metrics" | jq -r '.total_active_users // 0')
        local total_suggestions=$(echo "$day_metrics" | jq -r '.total_suggestions_count // 0')
        local total_acceptances=$(echo "$day_metrics" | jq -r '.total_acceptances_count // 0')
        
        echo "Org Active Users: $total_active_users" | tee -a "$output_file"
        echo "Org Suggestions: $total_suggestions" | tee -a "$output_file"
        echo "Org Acceptances: $total_acceptances" | tee -a "$output_file"
        
        if [ "$total_suggestions" -gt 0 ]; then
            local acceptance_rate=$(echo "scale=2; ($total_acceptances * 100) / $total_suggestions" | bc)
            echo "Org Acceptance Rate: ${acceptance_rate}%" | tee -a "$output_file"
        fi
        
        echo "" | tee -a "$output_file"
    done
    
    echo "========================================" | tee -a "$output_file"
}

# Main script
main() {
    log_info "Starting GitHub Copilot Team Metrics Collection"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --team)
                TEAMS+=("$2")
                shift 2
                ;;
            --teams)
                IFS=',' read -ra TEAM_ARRAY <<< "$2"
                TEAMS+=("${TEAM_ARRAY[@]}")
                shift 2
                ;;
            --all-teams)
                ALL_TEAMS=true
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
    else
        since_date=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
        until_date=$since_date
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Generate JWT and get token
    log_info "Generating JWT token..."
    JWT=$(generate_jwt "$GITHUB_APP_ID" "$GITHUB_PRIVATE_KEY_PATH")
    TOKEN=$(get_installation_token "$JWT" "$GITHUB_INSTALLATION_ID")
    log_success "Successfully authenticated"
    
    # Get all teams if requested
    if [ "$ALL_TEAMS" = true ]; then
        log_info "Fetching all teams in organization..."
        TEAMS=($(get_all_teams "$TOKEN" "$GITHUB_ORG"))
        log_info "Found ${#TEAMS[@]} teams"
    fi
    
    if [ ${#TEAMS[@]} -eq 0 ]; then
        log_error "No teams specified. Use --team <name>, --teams <name1,name2>, or --all-teams"
        exit 1
    fi
    
    # Process each team
    for team in "${TEAMS[@]}"; do
        log_info "Processing team: $team"
        
        METRICS=$(fetch_team_metrics "$TOKEN" "$GITHUB_ORG" "$team" "$since_date" "$until_date")
        
        local date_suffix="${since_date}"
        if [ "$since_date" != "$until_date" ]; then
            date_suffix="${since_date}_to_${until_date}"
        fi
        
        local json_output="${OUTPUT_DIR}/copilot-metrics-team-${team}-${date_suffix}.json"
        local text_output="${OUTPUT_DIR}/copilot-metrics-team-${team}-${date_suffix}.txt"
        
        echo "$METRICS" | jq '.' > "$json_output"
        log_success "Raw metrics saved to: $json_output"
        
        display_team_metrics "$team" "$METRICS" "$text_output"
    done
    
    log_success "Team metrics collection completed successfully!"
}

# Run main function
main "$@"
