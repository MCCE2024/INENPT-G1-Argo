#!/bin/bash

# Multi-Tenant OAuth Setup Script with Sealed Secrets
# This script sets up GitHub OAuth sealed secrets for multiple tenants

# Note: We don't use 'set -e' here because we want to handle errors gracefully
# and continue processing other tenants even if one fails

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLICATIONSETS_DIR="$SCRIPT_DIR/../applicationsets/tenants"
SECRETS_DIR="$SCRIPT_DIR/../secrets"

# Function to process a single tenant ApplicationSet
process_tenant_applicationset() {
    local tenant_dir="$1"
    local applicationset_file="$tenant_dir/applicationset.yaml"
    
    if [[ ! -f "$applicationset_file" ]]; then
        return 1
    fi
    
    # Extract the first element from the ApplicationSet (they're all the same tenant)
    local tenant_name=$(yq eval '.spec.generators[0].list.elements[0].tenant' "$applicationset_file" 2>/dev/null)
    local namespace=$(yq eval '.spec.generators[0].list.elements[0].namespace' "$applicationset_file" 2>/dev/null)
    local node_port=$(yq eval '.spec.generators[0].list.elements[0].nodePort' "$applicationset_file" 2>/dev/null)
    local domain=$(yq eval '.spec.generators[0].list.elements[0].domain' "$applicationset_file" 2>/dev/null)
    local display_name=$(yq eval '.spec.generators[0].list.elements[0].displayName' "$applicationset_file" 2>/dev/null)
    
    # Check if we got valid values
    if [[ "$tenant_name" == "null" || -z "$tenant_name" ]]; then
        return 1
    fi
    
    echo "===================="
    print_info "Configuring OAuth for: $display_name"
    print_info "Domain: http://$domain:$node_port"
    echo ""
    
    # Prompt for GitHub OAuth credentials
    read -p "Enter GitHub Client ID for $tenant_name: " github_client_id
    read -s -p "Enter GitHub Client Secret for $tenant_name: " github_client_secret
    echo ""
    
    if [[ -z "$github_client_id" || -z "$github_client_secret" ]]; then
        print_warning "Skipping $tenant_name - missing credentials"
        return 1  # Return 1 to indicate this tenant was skipped
    fi
    
    # Try to create the sealed secret, return the result
    if create_tenant_oauth_sealed_secret "$tenant_name" "$namespace" "$github_client_id" "$github_client_secret" "$node_port" "$domain"; then
        return 0  # Success
    else
        print_error "Failed to create sealed secret for $tenant_name"
        return 1  # Failure
    fi
}

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

# Function to create OAuth sealed secret for a tenant
create_tenant_oauth_sealed_secret() {
    local tenant_name="$1"
    local namespace="$2"
    local github_client_id="$3"
    local github_client_secret="$4"
    local node_port="$5"
    local domain="$6"
    
    print_info "Setting up OAuth sealed secret for tenant: $tenant_name"
    
    # Generate session secret
    local session_secret=$(generate_session_secret)
    
    # Create secrets directory if it doesn't exist
    mkdir -p "$SECRETS_DIR"
    
    # Create namespace if it doesn't exist
    print_info "📦 Ensuring namespace exists: $namespace"
    if kubectl get namespace "$namespace" &>/dev/null; then
        print_info "Namespace $namespace already exists"
    else
        print_info "Creating namespace: $namespace"
        kubectl create namespace "$namespace"
    fi
    
    # Define sealed secret file path
    local sealed_secret_file="$SECRETS_DIR/${tenant_name}-oauth-sealed-secret.yaml"
    
    print_info "🔒 Creating sealed secret for $tenant_name OAuth configuration..."
    
    # Create the sealed secret (namespace-scoped)
    kubectl create secret generic consumer-oauth-secret \
        --namespace="$namespace" \
        --from-literal=github-client-id="$github_client_id" \
        --from-literal=github-client-secret="$github_client_secret" \
        --from-literal=session-secret="$session_secret" \
        --dry-run=client -o yaml | \
        kubeseal --controller-name=sealed-secrets --controller-namespace=sealed-secrets-system -o yaml > "$sealed_secret_file"
    
    print_status "Sealed secret created: $sealed_secret_file"
    
    # Apply the sealed secret to the cluster
    print_info "🚀 Applying sealed secret to cluster..."
    if kubectl apply -f "$sealed_secret_file"; then
        print_status "OAuth sealed secret applied successfully for $tenant_name in namespace $namespace"
    else
        print_error "Failed to apply sealed secret for $tenant_name"
        return 1
    fi
    
    # Print GitHub OAuth App configuration
    echo ""
    print_info "GitHub OAuth App Configuration for $tenant_name:"
    echo "  App Name: MCCE $tenant_name"
    echo "  Homepage URL: http://$domain:$node_port"
    echo "  Authorization callback URL: http://$domain:$node_port/auth/github/callback"
    echo "  Client ID: $github_client_id"
    echo "  🔒 Sealed Secret File: $sealed_secret_file"
    echo ""
}

# Function to setup all tenants
setup_all_tenants() {
    print_info "Setting up OAuth sealed secrets for all tenants..."
    echo ""
    
    # Check if required tools are available
    if ! command -v yq &> /dev/null; then
        print_error "yq is required but not installed. Please install yq to continue."
        print_info "Install with: sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
        exit 1
    fi
    
    if ! command -v kubeseal &> /dev/null; then
        print_error "kubeseal CLI is not installed or not in PATH"
        print_info "Install kubeseal: https://github.com/bitnami-labs/sealed-secrets#installation"
        exit 1
    fi
    
    # Check if ApplicationSets directory exists
    if [[ ! -d "$APPLICATIONSETS_DIR" ]]; then
        print_error "ApplicationSets directory not found: $APPLICATIONSETS_DIR"
        exit 1
    fi
    
    # Process each tenant directory
    local processed_count=0
    local failed_count=0
    
    for tenant_dir in "$APPLICATIONSETS_DIR"/*/; do
        if [[ -d "$tenant_dir" ]]; then
            local tenant_basename=$(basename "$tenant_dir")
            print_info "Found tenant directory: $tenant_basename"
            
            if process_tenant_applicationset "$tenant_dir"; then
                ((processed_count++))
                print_status "Successfully processed tenant: $tenant_basename"
            else
                ((failed_count++))
                print_warning "Failed to process tenant directory: $tenant_basename"
            fi
            echo ""  # Add spacing between tenants
        fi
    done
    
    if [[ $processed_count -eq 0 ]]; then
        print_error "No valid tenants found in ApplicationSet files"
        exit 1
    fi
    
    print_info "Processing summary:"
    print_info "  ✅ Successfully processed: $processed_count tenants"
    if [[ $failed_count -gt 0 ]]; then
        print_warning "  ⚠️  Failed to process: $failed_count tenants"
    fi
    
    echo ""
    print_status "All tenant OAuth sealed secrets created!"
    print_info "🔒 Sealed secret files are safe to commit to Git"
    print_info "📁 Files created in: $SECRETS_DIR/"
}

# Function to setup single tenant
setup_single_tenant() {
    local target_tenant="$1"
    
    if [[ -z "$target_tenant" ]]; then
        print_error "Please specify a tenant name"
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v yq &> /dev/null; then
        print_error "yq is required but not installed."
        exit 1
    fi
    
    if ! command -v kubeseal &> /dev/null; then
        print_error "kubeseal CLI is not installed or not in PATH"
        print_info "Install kubeseal: https://github.com/bitnami-labs/sealed-secrets#installation"
        exit 1
    fi
    
    # Find tenant ApplicationSet directory
    local tenant_dir="$APPLICATIONSETS_DIR/$target_tenant"
    
    if [[ ! -d "$tenant_dir" ]]; then
        print_error "Tenant '$target_tenant' not found. Available tenants:"
        for dir in "$APPLICATIONSETS_DIR"/*/; do
            if [[ -d "$dir" ]]; then
                print_info "  - $(basename "$dir")"
            fi
        done
        exit 1
    fi
    
    # Process the tenant ApplicationSet
    if ! process_tenant_applicationset "$tenant_dir"; then
        print_error "Could not process tenant ApplicationSet for $target_tenant"
        exit 1
    fi
}

# Function to show help
show_help() {
    echo "Multi-Tenant OAuth Setup Script with Sealed Secrets"
    echo ""
    echo "Usage:"
    echo "  $0 all                    # Setup OAuth sealed secrets for all tenants"
    echo "  $0 <tenant-name>          # Setup OAuth sealed secret for specific tenant"
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
    echo "3. Ensure kubeseal CLI is installed and sealed-secrets controller is running"
    echo ""
    echo "🔒 Security Benefits:"
    echo "- Creates encrypted sealed secrets (safe to store in Git)"
    echo "- Separate sealed secret file per tenant"
    echo "- Namespace-scoped secrets for tenant isolation"
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
echo "1. Commit the sealed secret files to git - they're safe to store in version control!"
echo "2. Deploy the multi-tenant applications using ArgoCD ApplicationSet"
echo "3. Update DNS records for each tenant domain"
echo "4. Test OAuth login for each tenant"
echo ""
print_info "🔒 Security Notes:"
echo "   - Sealed secrets are encrypted and safe to store in Git"
echo "   - Each tenant has its own sealed secret file"
echo "   - Secrets are namespace-scoped for tenant isolation" 