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
DOMAIN="mcce.uname.at"

echo "🚀 Setting up Cloudflare DNS for Consumer Dashboard..."
echo "Domain: $DOMAIN"

# Get the external IP of the consumer service
echo "📡 Getting consumer service external IP..."
EXTERNAL_IP=$(kubectl get service consumer -n test-tenant -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" = "null" ]; then
    # If LoadBalancer IP is not available, get the node IP and NodePort
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    fi
    
    if [ -z "$NODE_IP" ]; then
        echo "❌ Could not determine node IP"
        exit 1
    fi
    
    EXTERNAL_IP="$NODE_IP"
    echo "📍 Using Node IP: $EXTERNAL_IP"
else
    echo "📍 Using LoadBalancer IP: $EXTERNAL_IP"
fi

# Check if DNS record already exists
echo "🔍 Checking if DNS record already exists..."
EXISTING_RECORD=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$DOMAIN&type=A" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

RECORD_ID=$(echo "$EXISTING_RECORD" | jq -r '.result[0].id // empty')

if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "null" ]; then
    echo "📝 Updating existing DNS record (DNS-only for NodePort compatibility)..."
    RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{
            \"type\": \"A\",
            \"name\": \"$DOMAIN\",
            \"content\": \"$EXTERNAL_IP\",
            \"ttl\": 300,
            \"proxied\": false
        }")
else
    echo "➕ Creating new DNS record (DNS-only for NodePort compatibility)..."
    RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{
            \"type\": \"A\",
            \"name\": \"$DOMAIN\",
            \"content\": \"$EXTERNAL_IP\",
            \"ttl\": 300,
            \"proxied\": false
        }")
fi

# Check if the request was successful
SUCCESS=$(echo "$RESPONSE" | jq -r '.success')
if [ "$SUCCESS" = "true" ]; then
    echo "✅ DNS record created/updated successfully!"
    echo ""
    echo "🌐 Your consumer dashboard is now available at:"
    echo "   http://$DOMAIN:30000"
    echo ""
    echo "🔧 Next steps:"
    echo "1. Update your GitHub OAuth App settings:"
    echo "   - Homepage URL: http://$DOMAIN:30000"
    echo "   - Authorization callback URL: http://$DOMAIN:30000/auth/github/callback"
    echo ""
    echo "2. Wait a few minutes for DNS propagation"
    echo "3. Test the new domain: http://$DOMAIN:30000"
else
    echo "❌ Failed to create/update DNS record"
    echo "Response: $RESPONSE"
    exit 1
fi 