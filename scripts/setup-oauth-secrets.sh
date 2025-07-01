#!/bin/bash

# GitHub OAuth Setup Script for Consumer Application
# Usage: ./setup-oauth-secrets.sh <client-id> <client-secret>

if [ $# -ne 2 ]; then
    echo "Usage: $0 <github-client-id> <github-client-secret>"
    echo "Example: $0 Ov23liAbcdef1234567890 1234567890abcdef1234567890abcdef12345678"
    exit 1
fi

GITHUB_CLIENT_ID="$1"
GITHUB_CLIENT_SECRET="$2"
SESSION_SECRET=$(openssl rand -hex 32)

echo "Setting up GitHub OAuth secrets..."
echo "Client ID: $GITHUB_CLIENT_ID"
echo "Session Secret: $SESSION_SECRET (generated)"

# Create the secret in the test-tenant namespace
kubectl create secret generic consumer-oauth-secret \
    --namespace=test-tenant \
    --from-literal=github-client-id="$GITHUB_CLIENT_ID" \
    --from-literal=github-client-secret="$GITHUB_CLIENT_SECRET" \
    --from-literal=session-secret="$SESSION_SECRET" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ OAuth secrets created successfully!"
echo ""
echo "GitHub OAuth App Configuration:"
echo "- Homepage URL: http://mcce.uname.at:30000"
echo "- Authorization callback URL: http://mcce.uname.at:30000/auth/github/callback"
echo ""
echo "Next steps:"
echo "1. Create a GitHub OAuth App with the URLs above"
echo "2. Run this script with your Client ID and Client Secret"
echo "3. Restart the consumer deployment: kubectl rollout restart deployment consumer -n test-tenant" 