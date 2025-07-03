#!/usr/bin/bash

# Exoscale SKS Kubeconfig Fetcher Script
# This script fetches the kubeconfig for the INENPT-G1 SKS cluster

set -e  # Exit on any error

# Configuration
CLUSTER_NAME="inenpt-g1-sks-cluster"
ZONE="at-vie-1"
USER="admin"
GROUP="system:masters"
TTL=604800  # 7 days in seconds
KUBECONFIG_FILE="kubeconfig.yaml"

echo "🔧 Fetching kubeconfig for SKS cluster: $CLUSTER_NAME"
echo "📍 Zone: $ZONE"
echo "👤 User: $USER"
echo "🔒 Group: $GROUP"
echo "⏰ TTL: $TTL seconds (7 days)"
echo ""

# Check if exo CLI is available
if ! command -v exo &> /dev/null; then
    echo "❌ Error: exo CLI is not installed or not in PATH"
    echo "Please install the Exoscale CLI first:"
    echo "https://github.com/exoscale/cli"
    exit 1
fi

# Check if cluster exists
echo "🔍 Checking if cluster exists..."
if ! exo compute sks show "$CLUSTER_NAME" --zone "$ZONE" &> /dev/null; then
    echo "❌ Error: Cluster '$CLUSTER_NAME' not found in zone '$ZONE'"
    echo "Available clusters:"
    exo compute sks list
    exit 1
fi

# Backup existing kubeconfig if it exists
if [ -f "$KUBECONFIG_FILE" ]; then
    BACKUP_FILE="${KUBECONFIG_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
    echo "📦 Backing up existing kubeconfig to: $BACKUP_FILE"
    cp "$KUBECONFIG_FILE" "$BACKUP_FILE"
fi

# Generate new kubeconfig
echo "🚀 Generating new kubeconfig..."
exo compute sks kubeconfig "$CLUSTER_NAME" "$USER" \
    --zone "$ZONE" \
    --group "$GROUP" \
    --ttl "$TTL" > "$KUBECONFIG_FILE"

if [ $? -eq 0 ]; then
    echo "✅ Kubeconfig generated successfully: $KUBECONFIG_FILE"
else
    echo "❌ Failed to generate kubeconfig"
    exit 1
fi

# Test the connection
echo "🧪 Testing connection to cluster..."
if kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes &> /dev/null; then
    echo "✅ Connection test successful!"
    echo ""
    echo "📊 Cluster nodes:"
    kubectl --kubeconfig="$KUBECONFIG_FILE" get nodes
else
    echo "❌ Connection test failed"
    echo "The kubeconfig was generated but connection failed."
    echo "Please check your network connection and cluster status."
    exit 1
fi

# Copy to ~/.kube/config for default kubectl usage
echo ""
echo "📋 Copying kubeconfig to ~/.kube/config for default kubectl usage..."
mkdir -p ~/.kube

# Backup existing ~/.kube/config if it exists
if [ -f ~/.kube/config ]; then
    KUBE_BACKUP_FILE="$HOME/.kube/config.backup.$(date +%Y%m%d-%H%M%S)"
    echo "📦 Backing up existing ~/.kube/config to: $KUBE_BACKUP_FILE"
    cp ~/.kube/config "$KUBE_BACKUP_FILE"
fi

# Copy the new kubeconfig
cp "$KUBECONFIG_FILE" ~/.kube/config
chmod 600 ~/.kube/config  # Set proper permissions

echo "✅ Kubeconfig copied to ~/.kube/config"

# Copy to infrastructure folder for OpenTofu
INFRASTRUCTURE_KUBECONFIG="../infrastructure/kubeconfig.yaml"
echo "📋 Copying kubeconfig to infrastructure folder for OpenTofu..."

# Backup existing infrastructure kubeconfig if it exists
if [ -f "$INFRASTRUCTURE_KUBECONFIG" ]; then
    INFRA_BACKUP_FILE="../infrastructure/kubeconfig.yaml.backup.$(date +%Y%m%d-%H%M%S)"
    echo "📦 Backing up existing infrastructure kubeconfig to: $INFRA_BACKUP_FILE"
    cp "$INFRASTRUCTURE_KUBECONFIG" "$INFRA_BACKUP_FILE"
fi

# Copy the new kubeconfig to infrastructure folder
cp "$KUBECONFIG_FILE" "$INFRASTRUCTURE_KUBECONFIG"
chmod 600 "$INFRASTRUCTURE_KUBECONFIG"  # Set proper permissions

echo "✅ Kubeconfig copied to infrastructure folder: $INFRASTRUCTURE_KUBECONFIG"

# Test default kubectl
echo "🧪 Testing default kubectl (without --kubeconfig flag)..."
if kubectl get nodes &> /dev/null; then
    echo "✅ Default kubectl test successful!"
else
    echo "⚠️  Default kubectl test failed, but local kubeconfig works"
fi

echo ""
echo "🎉 Kubeconfig setup completed successfully!"
echo "💡 You can now use kubectl directly: kubectl get nodes"
echo "💡 Or use the local file: kubectl --kubeconfig=$KUBECONFIG_FILE <command>"
echo "💡 Or export KUBECONFIG=$(pwd)/$KUBECONFIG_FILE"
echo ""
echo "📁 Kubeconfig locations:"
echo "   • Local scripts folder: $KUBECONFIG_FILE"
echo "   • Default kubectl: ~/.kube/config"
echo "   • Infrastructure folder: $INFRASTRUCTURE_KUBECONFIG (for OpenTofu)" 