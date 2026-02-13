#!/bin/bash

################################################################################
# Setup Script for GitHub Copilot Metrics Collector
# 
# This script helps set up the environment for collecting Copilot metrics
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo ""
echo "========================================"
echo "GitHub Copilot Metrics Collector Setup"
echo "========================================"
echo ""

# Check dependencies
log_info "Checking dependencies..."

missing_deps=()
for cmd in curl jq openssl base64 bc; do
    if ! command -v $cmd &> /dev/null; then
        missing_deps+=($cmd)
    fi
done

if [ ${#missing_deps[@]} -ne 0 ]; then
    log_error "Missing required dependencies: ${missing_deps[*]}"
    echo ""
    echo "Install missing dependencies:"
    echo "  macOS: brew install ${missing_deps[*]}"
    echo "  Ubuntu/Debian: sudo apt-get install ${missing_deps[*]}"
    echo "  CentOS/RHEL: sudo yum install ${missing_deps[*]}"
    echo ""
    exit 1
else
    log_success "All dependencies installed"
fi

# Check if .env exists
if [ -f .env ]; then
    log_warning ".env file already exists"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping existing .env file"
        ENV_EXISTS=true
    fi
fi

if [ "$ENV_EXISTS" != true ]; then
    log_info "Creating .env file from template..."
    cp .env.example .env
    chmod 600 .env
    log_success ".env file created with secure permissions (600)"
fi

# Create directories
log_info "Creating output directories..."
mkdir -p metrics-output
mkdir -p logs
log_success "Directories created"

# Set permissions on scripts
log_info "Setting executable permissions on scripts..."
chmod +x *.sh
log_success "Scripts are executable"

echo ""
echo "========================================"
echo "Setup Complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Create a GitHub App (see INSTRUCTIONS.md for detailed steps)"
echo "   https://github.com/organizations/YOUR_ORG/settings/apps"
echo ""
echo "2. Download the private key and move it here:"
echo "   mv ~/Downloads/*.private-key.pem ./github-app-private-key.pem"
echo "   chmod 600 ./github-app-private-key.pem"
echo ""
echo "3. Edit the .env file with your credentials:"
echo "   vim .env"
echo ""
echo "4. Load environment variables:"
echo "   source .env"
echo ""
echo "5. Run your first collection:"
echo "   ./capture-org-metrics.sh"
echo ""
echo "For detailed instructions, see:"
echo "  - README.md (quick start)"
echo "  - INSTRUCTIONS.md (complete guide)"
echo ""
