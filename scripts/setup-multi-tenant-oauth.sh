#!/bin/bash

# Multi-Tenant OAuth Setup Script
# This script sets up GitHub OAuth secrets for multiple tenants

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TENANT_CONFIG="$SCRIPT_DIR/../tenants/tenant-config.yaml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to generate session secret
generate_session_secret() {
    openssl rand -hex 32
}

# Function to create OAuth secret for a tenant
create_tenant_oauth_secret() {
    local tenant_name="$1"
    local namespace="$2"
    local github_client_id="$3"
    local github_client_secret="$4"
    local node_port="$5"
    local domain="$6"
    
    print_info "Setting up OAuth for tenant: $tenant_name"
    
    # Generate session secret
    local session_secret=$(generate_session_secret)
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
    
    # Delete existing secret if it exists
    kubectl delete secret consumer-oauth-secret -n "$namespace" 2>/dev/null || true
    
    # Create new secret
    kubectl create secret generic consumer-oauth-secret \
        --from-literal=github-client-id="$github_client_id" \
        --from-literal=github-client-secret="$github_client_secret" \
        --from-literal=session-secret="$session_secret" \
        -n "$namespace"
    
    print_status "OAuth secret created for $tenant_name in namespace $namespace"
    
    # Print GitHub OAuth App configuration
    echo ""
    print_info "GitHub OAuth App Configuration for $tenant_name:"
    echo "  App Name: MCCE $tenant_name"
    echo "  Homepage URL: http://$domain:$node_port"
    echo "  Authorization callback URL: http://$domain:$node_port/auth/github/callback"
    echo "  Client ID: $github_client_id"
    echo ""
}

# Function to setup all tenants
setup_all_tenants() {
    print_info "Setting up OAuth for all tenants..."
    echo ""
    
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        print_error "yq is required but not installed. Please install yq to continue."
        print_info "Install with: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
        exit 1
    fi
    
    # Read tenant configuration and prompt for OAuth credentials
    local tenant_count=$(yq eval '.tenants | length' "$TENANT_CONFIG")
    
    for ((i=0; i<tenant_count; i++)); do
        local tenant_name=$(yq eval ".tenants[$i].name" "$TENANT_CONFIG")
        local namespace=$(yq eval ".tenants[$i].namespace" "$TENANT_CONFIG")
        local node_port=$(yq eval ".tenants[$i].nodePort" "$TENANT_CONFIG")
        local domain=$(yq eval ".tenants[$i].domain" "$TENANT_CONFIG")
        local app_name=$(yq eval ".tenants[$i].github.appName" "$TENANT_CONFIG")
        
        echo "===================="
        print_info "Configuring OAuth for: $app_name"
        print_info "Domain: http://$domain:$node_port"
        echo ""
        
        # Prompt for GitHub OAuth credentials
        read -p "Enter GitHub Client ID for $tenant_name: " github_client_id
        read -s -p "Enter GitHub Client Secret for $tenant_name: " github_client_secret
        echo ""
        
        if [[ -z "$github_client_id" || -z "$github_client_secret" ]]; then
            print_warning "Skipping $tenant_name - missing credentials"
            continue
        fi
        
        create_tenant_oauth_secret "$tenant_name" "$namespace" "$github_client_id" "$github_client_secret" "$node_port" "$domain"
    done
}

# Function to setup single tenant
setup_single_tenant() {
    local target_tenant="$1"
    
    if [[ -z "$target_tenant" ]]; then
        print_error "Please specify a tenant name"
        exit 1
    fi
    
    # Check if yq is available
    if ! command -v yq &> /dev/null; then
        print_error "yq is required but not installed."
        exit 1
    fi
    
    # Find tenant in configuration
    local tenant_index=$(yq eval ".tenants | map(select(.name == \"$target_tenant\")) | keys | .[0]" "$TENANT_CONFIG")
    
    if [[ "$tenant_index" == "null" ]]; then
        print_error "Tenant '$target_tenant' not found in configuration"
        exit 1
    fi
    
    local namespace=$(yq eval ".tenants[$tenant_index].namespace" "$TENANT_CONFIG")
    local node_port=$(yq eval ".tenants[$tenant_index].nodePort" "$TENANT_CONFIG")
    local domain=$(yq eval ".tenants[$tenant_index].domain" "$TENANT_CONFIG")
    local app_name=$(yq eval ".tenants[$tenant_index].github.appName" "$TENANT_CONFIG")
    
    print_info "Configuring OAuth for: $app_name"
    print_info "Domain: http://$domain:$node_port"
    echo ""
    
    # Prompt for GitHub OAuth credentials
    read -p "Enter GitHub Client ID for $target_tenant: " github_client_id
    read -s -p "Enter GitHub Client Secret for $target_tenant: " github_client_secret
    echo ""
    
    if [[ -z "$github_client_id" || -z "$github_client_secret" ]]; then
        print_error "Missing credentials"
        exit 1
    fi
    
    create_tenant_oauth_secret "$target_tenant" "$namespace" "$github_client_id" "$github_client_secret" "$node_port" "$domain"
}

# Function to show help
show_help() {
    echo "Multi-Tenant OAuth Setup Script"
    echo ""
    echo "Usage:"
    echo "  $0 all                    # Setup OAuth for all tenants"
    echo "  $0 <tenant-name>          # Setup OAuth for specific tenant"
    echo "  $0 --help                 # Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 all"
    echo "  $0 tenant-a"
    echo "  $0 tenant-b"
    echo ""
    echo "Before running this script:"
    echo "1. Create GitHub OAuth Apps for each tenant with these settings:"
    echo "   - Homepage URL: http://[domain]:[port]"
    echo "   - Authorization callback URL: http://[domain]:[port]/auth/github/callback"
    echo "2. Have the Client ID and Client Secret ready for each tenant"
}

# Main script logic
case "${1:-}" in
    "all")
        setup_all_tenants
        ;;
    "--help"|"-h"|"help")
        show_help
        ;;
    "")
        print_error "No arguments provided"
        show_help
        exit 1
        ;;
    *)
        setup_single_tenant "$1"
        ;;
esac

print_status "OAuth setup completed!"
echo ""
print_info "Next steps:"
echo "1. Deploy the multi-tenant applications using ArgoCD ApplicationSet"
echo "2. Update DNS records for each tenant domain"
echo "3. Test OAuth login for each tenant" 