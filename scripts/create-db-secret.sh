#!/usr/bin/bash

# Database Secret Creator Script
# Creates a Kubernetes secret with database password for a specific namespace

set -e  # Exit on any error

# Configuration
DB_NAME="inenpt-g1-postgresql"
ZONE="at-vie-1"
SECRET_NAME="api-db-secret"

# Function to show usage
show_usage() {
    echo "Usage: $0 <namespace> [secret-name]"
    echo ""
    echo "Arguments:"
    echo "  namespace    - Kubernetes namespace to create the secret in"
    echo "  secret-name  - Name of the secret (optional, default: api-db-secret)"
    echo ""
    echo "Examples:"
    echo "  $0 default"
    echo "  $0 production"
    echo "  $0 tenant-a custom-secret-name"
    echo ""
    exit 1
}

# Check arguments
if [ $# -lt 1 ]; then
    echo "❌ Error: Namespace is required"
    show_usage
fi

NAMESPACE="$1"

# Use fixed secret name or custom name if provided
if [ $# -ge 2 ]; then
    SECRET_NAME="$2"
else
    SECRET_NAME="api-db-secret"
fi

echo "🔐 Creating database secret for namespace: $NAMESPACE"
echo "🏷️  Secret name: $SECRET_NAME"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if exo CLI is available
if ! command -v exo &> /dev/null; then
    echo "❌ Error: exo CLI is not installed or not in PATH"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "⚠️  Namespace '$NAMESPACE' does not exist. Creating it..."
    kubectl create namespace "$NAMESPACE"
    echo "✅ Namespace '$NAMESPACE' created"
fi

# Get database URI with password
echo "📡 Getting database connection details..."
DB_URI=$(exo dbaas show "$DB_NAME" --zone "$ZONE" --uri)

if [ -z "$DB_URI" ]; then
    echo "❌ Error: Could not retrieve database URI"
    exit 1
fi

# Extract password from URI
# URI format: postgres://user:password@host:port/database?sslmode=require
if [[ "$DB_URI" =~ postgres://([^:]+):([^@]+)@([^:]+):([0-9]+)/([^?]+) ]]; then
    DB_USER="${BASH_REMATCH[1]}"
    DB_PASSWORD="${BASH_REMATCH[2]}"
    DB_HOST="${BASH_REMATCH[3]}"
    DB_PORT="${BASH_REMATCH[4]}"
    DB_DATABASE="${BASH_REMATCH[5]}"
else
    echo "❌ Error: Could not parse database URI"
    exit 1
fi

echo "✅ Database connection details extracted"
echo "   Host: $DB_HOST"
echo "   Port: $DB_PORT"
echo "   User: $DB_USER"
echo "   Database: $DB_DATABASE"
echo ""

# Create the secret
echo "🔐 Creating Kubernetes secret..."
kubectl create secret generic "$SECRET_NAME" \
    --from-literal=password="$DB_PASSWORD" \
    --from-literal=host="$DB_HOST" \
    --from-literal=port="$DB_PORT" \
    --from-literal=user="$DB_USER" \
    --from-literal=database="$DB_DATABASE" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -

if [ $? -eq 0 ]; then
    echo "✅ Secret '$SECRET_NAME' created/updated successfully in namespace '$NAMESPACE'"
else
    echo "❌ Failed to create secret"
    exit 1
fi

echo ""
echo "📋 Secret Details:"
echo "================================"
echo "🏷️  Secret Name: $SECRET_NAME"
echo "🏠 Namespace: $NAMESPACE"
echo "🔑 Contains:"
echo "   - password (database password)"
echo "   - host (database host)"
echo "   - port (database port)"
echo "   - user (database user)"
echo "   - database (database name)"
echo ""
echo "💡 Usage in Helm templates:"
echo "   env:"
echo "   - name: DB_PASSWORD"
echo "     valueFrom:"
echo "       secretKeyRef:"
echo "         name: $SECRET_NAME"
echo "         key: password"
echo "   - name: DB_HOST"
echo "     valueFrom:"
echo "       secretKeyRef:"
echo "         name: $SECRET_NAME"
echo "         key: host"
echo ""
echo "🎉 Database secret setup completed successfully!" 