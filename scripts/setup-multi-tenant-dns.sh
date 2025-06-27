#!/bin/bash

# Multi-Tenant DNS Setup Script
# This script sets up Cloudflare DNS for multiple tenants using the same domain

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TENANT_CONFIG="$SCRIPT_DIR/../tenants/tenant-config.yaml"
CLOUDFLARE_CONFIG_FILE="$SCRIPT_DIR/cloudflare-config.txt"
DOMAIN="mcce.uname.at"

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

# Function to save credentials
save_credentials() {
    cat > "$CLOUDFLARE_CONFIG_FILE" << EOF
# Cloudflare API Credentials for MCCE Multi-Tenant
# Generated: $(date)
CLOUDFLARE_API_TOKEN=$1
ZONE_ID=$2
EOF
    chmod 600 "$CLOUDFLARE_CONFIG_FILE"
    print_info "Credentials saved to $CLOUDFLARE_CONFIG_FILE"
}

# Function to setup DNS record
setup_dns_record() {
    local external_ip="$1"
    
    print_info "Setting up DNS record for $DOMAIN"
    
    # Check if DNS record already exists
    print_info "Checking if DNS record already exists..."
    EXISTING_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN&type=A" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")

    RECORD_ID=$(echo "$EXISTING_RECORD" | jq -r '.result[0].id // empty')

    if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "null" ]; then
        print_info "Updating existing DNS record (DNS-only for NodePort compatibility)..."
        RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$DOMAIN\",
                \"content\": \"$external_ip\",
                \"ttl\": 300,
                \"proxied\": false
            }")
    else
        print_info "Creating new DNS record (DNS-only for NodePort compatibility)..."
        RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$DOMAIN\",
                \"content\": \"$external_ip\",
                \"ttl\": 300,
                \"proxied\": false
            }")
    fi

    # Check if the request was successful
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
    if [ "$SUCCESS" = "true" ]; then
        print_status "DNS record created/updated successfully!"
    else
        print_error "Failed to create/update DNS record"
        echo "Response: $RESPONSE"
        exit 1
    fi
}

# Function to get external IP
get_external_ip() {
    print_info "Getting external IP..."
    
    # Try to get LoadBalancer IP first
    EXTERNAL_IP=$(kubectl get service consumer -n tenant-a -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" = "null" ]; then
        # If LoadBalancer IP is not available, get the node IP
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "")
        if [ -z "$NODE_IP" ]; then
            NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
        fi
        
        if [ -z "$NODE_IP" ]; then
            print_error "Could not determine external IP"
            exit 1
        fi
        
        EXTERNAL_IP="$NODE_IP"
        print_info "Using Node IP: $EXTERNAL_IP"
    else
        print_info "Using LoadBalancer IP: $EXTERNAL_IP"
    fi
    
    echo "$EXTERNAL_IP"
}

# Function to display tenant access URLs
display_tenant_urls() {
    print_status "Multi-Tenant Setup Complete!"
    echo ""
    print_info "Your tenants are now available at:"
    
    # Check if yq is available
    if command -v yq &> /dev/null; then
        local tenant_count=$(yq eval '.tenants | length' "$TENANT_CONFIG")
        
        for ((i=0; i<tenant_count; i++)); do
            local tenant_name=$(yq eval ".tenants[$i].name" "$TENANT_CONFIG")
            local display_name=$(yq eval ".tenants[$i].displayName" "$TENANT_CONFIG")
            local node_port=$(yq eval ".tenants[$i].nodePort" "$TENANT_CONFIG")
            
            echo "  🏢 $display_name:"
            echo "     http://$DOMAIN:$node_port"
            echo ""
        done
    else
        echo "  🏢 Tenant A: http://$DOMAIN:30000"
        echo "  🏢 Tenant B: http://$DOMAIN:30001"
        echo "  🏢 Tenant C: http://$DOMAIN:30002"
        echo ""
    fi
    
    print_info "Next steps:"
    echo "1. Set up OAuth secrets for each tenant:"
    echo "   ./scripts/setup-multi-tenant-oauth.sh all"
    echo ""
    echo "2. Deploy the ApplicationSet:"
    echo "   kubectl apply -f applicationsets/multi-tenant-applicationset.yaml"
    echo ""
    echo "3. Wait for DNS propagation (2-5 minutes)"
    echo ""
    echo "4. Test each tenant's login functionality"
}

# Main script logic
main() {
    print_info "🚀 Setting up Multi-Tenant DNS for MCCE..."
    echo ""
    
    # Check if config file exists and load credentials
    if [ -f "$CLOUDFLARE_CONFIG_FILE" ]; then
        print_info "Loading saved Cloudflare credentials..."
        source "$CLOUDFLARE_CONFIG_FILE"
    fi

    # If no arguments provided, try to use saved credentials
    if [ $# -eq 0 ]; then
        if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$ZONE_ID" ]; then
            print_error "No saved credentials found. Please provide them:"
            echo "Usage: $0 <cloudflare-api-token> <zone-id>"
            echo ""
            echo "To get your Cloudflare API Token:"
            echo "1. Go to https://dash.cloudflare.com/profile/api-tokens"
            echo "2. Create Token -> Custom token"
            echo "3. Permissions: Zone:Zone:Read, Zone:DNS:Edit"
            echo "4. Zone Resources: Include -> Specific zone -> uname.at"
            echo ""
            echo "To get your Zone ID:"
            echo "1. Go to https://dash.cloudflare.com"
            echo "2. Select your domain (uname.at)"
            echo "3. Copy the Zone ID from the right sidebar"
            echo ""
            echo "Example: $0 abc123def456... 1234567890abcdef1234567890abcdef"
            exit 1
        fi
        print_status "Using saved credentials"
    elif [ $# -eq 2 ]; then
        # New credentials provided, save them
        CLOUDFLARE_API_TOKEN="$1"
        ZONE_ID="$2"
        save_credentials "$CLOUDFLARE_API_TOKEN" "$ZONE_ID"
    else
        print_error "Invalid number of arguments"
        echo "Usage: $0 [cloudflare-api-token] [zone-id]"
        echo "Or run without arguments to use saved credentials"
        exit 1
    fi

    # Get external IP
    EXTERNAL_IP=$(get_external_ip)
    
    # Setup DNS record
    setup_dns_record "$EXTERNAL_IP"
    
    # Display tenant URLs
    display_tenant_urls
}

# Check for help flag
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "help" ]]; then
    echo "Multi-Tenant DNS Setup Script"
    echo ""
    echo "This script sets up a single DNS record that all tenants will use"
    echo "with different ports for access."
    echo ""
    echo "Usage:"
    echo "  $0 [cloudflare-api-token] [zone-id]"
    echo "  $0 --help"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use saved credentials"
    echo "  $0 abc123... 1234567890abcdef...     # Set new credentials"
    echo ""
    echo "Tenant Access URLs:"
    echo "  - Tenant A: http://mcce.uname.at:30000"
    echo "  - Tenant B: http://mcce.uname.at:30001"
    echo "  - Tenant C: http://mcce.uname.at:30002"
    exit 0
fi

# Run main function
main "$@" 