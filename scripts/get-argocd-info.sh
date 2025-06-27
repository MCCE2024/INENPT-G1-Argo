#!/usr/bin/bash

# ArgoCD Info Fetcher Script
# Gets the LoadBalancer IP and initial admin password for ArgoCD

set -e  # Exit on any error

# Configuration
NAMESPACE="argocd"
SERVICE_NAME="argocd-server"
SECRET_NAME="argocd-initial-admin-secret"

echo "🔍 Getting ArgoCD access information..."
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if ArgoCD namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "❌ Error: ArgoCD namespace '$NAMESPACE' not found"
    echo "Please deploy ArgoCD first using: terraform apply"
    exit 1
fi

# Get LoadBalancer IP
echo "🌐 Getting ArgoCD LoadBalancer IP..."
EXTERNAL_IP=$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" = "null" ]; then
    echo "⏳ LoadBalancer IP not yet assigned. Checking status..."
    kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE"
    echo ""
    echo "💡 The LoadBalancer might still be provisioning. Wait a few minutes and run this script again."
    exit 1
fi

# Get service ports
HTTP_PORT=$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="http")].port}')
HTTPS_PORT=$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[?(@.name=="https")].port}')

# Get initial admin password
echo "🔑 Getting ArgoCD initial admin password..."
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    ADMIN_PASSWORD=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)
else
    echo "⚠️  Initial admin secret not found. It might have been deleted after first login."
    ADMIN_PASSWORD="<Secret not found - may have been deleted>"
fi

# Display results
echo ""
echo "🎉 ArgoCD Access Information:"
echo "================================"
echo "🌐 External IP:    $EXTERNAL_IP"
echo "🔗 HTTP URL:       http://$EXTERNAL_IP:$HTTP_PORT"
echo "🔗 HTTPS URL:      https://$EXTERNAL_IP:$HTTPS_PORT"
echo "👤 Username:       admin"
echo "🔑 Password:       $ADMIN_PASSWORD"
echo ""
echo "💡 Access ArgoCD at: https://$EXTERNAL_IP"
echo "💡 Login with: admin / $ADMIN_PASSWORD"
echo ""

# Optional: Test connectivity
echo "🧪 Testing connectivity..."
if curl -k -s --connect-timeout 5 "https://$EXTERNAL_IP" > /dev/null; then
    echo "✅ ArgoCD is accessible!"
else
    echo "⚠️  Could not connect to ArgoCD (this might be normal if it's still starting)"
fi

echo ""
echo "📋 Quick commands:"
echo "  kubectl get pods -n $NAMESPACE     # Check ArgoCD pods"
echo "  kubectl get svc -n $NAMESPACE      # Check ArgoCD services"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=argocd-server  # Check logs" 