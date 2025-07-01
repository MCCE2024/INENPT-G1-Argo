#!/bin/bash

# Cloudflare DNS Setup Script for Consumer Application
# Usage: ./setup-cloudflare-dns.sh [cloudflare-api-token] [zone-id]

CLOUDFLARE_CONFIG_FILE="cloudflare-config.txt"

# Function to save credentials
save_credentials() {
    cat > "$CLOUDFLARE_CONFIG_FILE" << EOF
# Cloudflare API Credentials for MCCE
# Generated: $(date)
CLOUDFLARE_API_TOKEN=$1
ZONE_ID=$2
EOF
    chmod 600 "$CLOUDFLARE_CONFIG_FILE"  # Secure permissions
    echo "💾 Credentials saved to $CLOUDFLARE_CONFIG_FILE"
}

# Check if config file exists and load credentials
if [ -f "$CLOUDFLARE_CONFIG_FILE" ]; then
    echo "📁 Loading saved Cloudflare credentials..."
    source "$CLOUDFLARE_CONFIG_FILE"
fi

# If no arguments provided, try to use saved credentials
if [ $# -eq 0 ]; then
    if [ -z "$CLOUDFLARE_API_TOKEN" ] || [ -z "$ZONE_ID" ]; then
        echo "❌ No saved credentials found. Please provide them:"
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
    echo "✅ Using saved credentials"
elif [ $# -eq 2 ]; then
    # New credentials provided, save them
    CLOUDFLARE_API_TOKEN="$1"
    ZONE_ID="$2"
    save_credentials "$CLOUDFLARE_API_TOKEN" "$ZONE_ID"
else
    echo "❌ Invalid number of arguments"
    echo "Usage: $0 [cloudflare-api-token] [zone-id]"
    echo "Or run without arguments to use saved credentials"
    exit 1
fi
CONSUMER_DOMAIN="mcce.uname.at"
ARGOCD_DOMAIN="argo.uname.at"

echo "🚀 Setting up Cloudflare DNS for Consumer Dashboard and ArgoCD..."
echo "Consumer Domain: $CONSUMER_DOMAIN"
echo "ArgoCD Domain: $ARGOCD_DOMAIN"

# Get the external IP of the consumer service
echo "📡 Getting consumer service external IP..."
CONSUMER_IP=$(kubectl get service consumer -n tenant-a -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$CONSUMER_IP" ] || [ "$CONSUMER_IP" = "null" ]; then
    # If LoadBalancer IP is not available, get the node IP and NodePort
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    fi
    
    if [ -z "$NODE_IP" ]; then
        echo "❌ Could not determine node IP"
        exit 1
    fi
    
    CONSUMER_IP="$NODE_IP"
    echo "📍 Using Node IP for consumer: $CONSUMER_IP"
else
    echo "📍 Using LoadBalancer IP for consumer: $CONSUMER_IP"
fi

# Get the external IP of the ArgoCD service
echo "📡 Getting ArgoCD service external IP..."
ARGOCD_IP=$(kubectl get service argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$ARGOCD_IP" ] || [ "$ARGOCD_IP" = "null" ]; then
    echo "❌ Could not get ArgoCD LoadBalancer IP"
    exit 1
else
    echo "📍 Using LoadBalancer IP for ArgoCD: $ARGOCD_IP"
fi

# Function to create or update DNS record
create_or_update_dns_record() {
    local domain="$1"
    local ip="$2"
    local description="$3"
    local ttl="$4"
    local proxied="$5"
    
    echo "🔍 Checking if DNS record already exists for $domain..."
    EXISTING_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$domain&type=A" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")

    RECORD_ID=$(echo "$EXISTING_RECORD" | jq -r '.result[0].id // empty')

    if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "null" ]; then
        echo "📝 Updating existing DNS record for $description..."
        RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$domain\",
                \"content\": \"$ip\",
                \"ttl\": $ttl,
                \"proxied\": $proxied
            }")
    else
        echo "➕ Creating new DNS record for $description..."
        RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$domain\",
                \"content\": \"$ip\",
                \"ttl\": $ttl,
                \"proxied\": $proxied
            }")
    fi

    # Check if the request was successful
    SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
    if [ "$SUCCESS" = "true" ]; then
        echo "✅ DNS record for $description created/updated successfully!"
        return 0
    else
        echo "❌ Failed to create/update DNS record for $description"
        echo "Response: $RESPONSE"
        return 1
    fi
}

# Create DNS records
echo ""
echo "🌐 Setting up DNS records..."

# Consumer DNS record (DNS-only for NodePort compatibility)
if ! create_or_update_dns_record "$CONSUMER_DOMAIN" "$CONSUMER_IP" "Consumer Dashboard" 300 false; then
    exit 1
fi

# ArgoCD DNS record (DNS-only, 5 min TTL)
if ! create_or_update_dns_record "$ARGOCD_DOMAIN" "$ARGOCD_IP" "ArgoCD" 300 false; then
    exit 1
fi

echo ""
echo "🎉 All DNS records created/updated successfully!"
echo ""
echo "🌐 Your services are now available at:"
echo "   Consumer Dashboard: http://$CONSUMER_DOMAIN:30000"
echo "   ArgoCD:            https://$ARGOCD_DOMAIN"
echo ""
echo "🔧 Next steps:"
echo "1. Update your GitHub OAuth App settings:"
echo "   - Homepage URL: http://$CONSUMER_DOMAIN:30000"
echo "   - Authorization callback URL: http://$CONSUMER_DOMAIN:30000/auth/github/callback"
echo ""
echo "2. Wait a few minutes for DNS propagation"
echo "3. Test the domains:"
echo "   - Consumer: http://$CONSUMER_DOMAIN:30000"
echo "   - ArgoCD:   https://$ARGOCD_DOMAIN" 