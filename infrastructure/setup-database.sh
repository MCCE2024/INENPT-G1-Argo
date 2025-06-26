#!/usr/bin/bash

# Database Setup Script
# 1. Gets the database URL from Exoscale
# 2. Prompts user for password
# 3. Downloads CA certificate
# 4. Updates API values file

set -e  # Exit on any error

# Configuration
DB_NAME="inenpt-g1-postgresql"
ZONE="at-vie-1"
API_VALUES_FILE="../applications/api/helm/values.yaml"
CA_CERT_FILE="ca.pem"

echo "🗄️  Setting up database configuration for API..."
echo ""

# Check if exo CLI is available
if ! command -v exo &> /dev/null; then
    echo "❌ Error: exo CLI is not installed or not in PATH"
    exit 1
fi

# Check if database exists
echo "🔍 Checking if database exists..."
if ! exo dbaas show "$DB_NAME" --zone "$ZONE" &> /dev/null; then
    echo "❌ Error: Database '$DB_NAME' not found in zone '$ZONE'"
    echo "Available databases:"
    exo dbaas list
    exit 1
fi

# Get database connection details
echo "📡 Getting database connection details..."
DB_URI=$(exo dbaas show "$DB_NAME" --zone "$ZONE" --uri)

echo "🔍 Extracted URI: $DB_URI"

# Extract connection details from URI
# URI format: postgres://user:password@host:port/database?sslmode=require
if [[ "$DB_URI" =~ postgres://([^:]+):([^@]+)@([^:]+):([0-9]+)/([^?]+) ]]; then
    DB_USER="${BASH_REMATCH[1]}"
    DB_PASSWORD="${BASH_REMATCH[2]}"
    DB_HOST="${BASH_REMATCH[3]}"
    DB_PORT="${BASH_REMATCH[4]}"
    DB_DATABASE="${BASH_REMATCH[5]}"
    echo "✅ Password found in URI - no need to prompt!"
    SKIP_PASSWORD_PROMPT=true
else
    echo "❌ Error: Could not parse database URI: $DB_URI"
    exit 1
fi

echo "✅ Database details retrieved:"
echo "   Host: $DB_HOST"
echo "   Port: $DB_PORT"
echo "   User: $DB_USER"
echo "   Database: $DB_DATABASE"
echo ""

# Prompt for password (only if not already extracted from URI)
if [ "$SKIP_PASSWORD_PROMPT" != "true" ]; then
    echo "🔑 Please enter the database password:"
    echo "   (You can find this in your Exoscale console when you created the database)"
    read -s -p "Password: " DB_PASSWORD
    echo ""

    if [ -z "$DB_PASSWORD" ]; then
        echo "❌ Error: Password cannot be empty"
        exit 1
    fi
fi

# Test connection (optional - requires psql)
if command -v psql &> /dev/null; then
    echo "🧪 Testing database connection..."
    if PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_DATABASE" -c "SELECT 1;" &> /dev/null; then
        echo "✅ Database connection successful!"
    else
        echo "⚠️  Database connection test failed, but continuing..."
    fi
else
    echo "💡 psql not available, skipping connection test"
fi

# Download CA certificate
echo "📜 Downloading CA certificate..."
if exo dbaas ca-certificate "$DB_NAME" --zone "$ZONE" > "$CA_CERT_FILE"; then
    echo "✅ CA certificate downloaded: $CA_CERT_FILE"
else
    echo "❌ Failed to download CA certificate"
    exit 1
fi

# Check if API values file exists
if [ ! -f "$API_VALUES_FILE" ]; then
    echo "❌ Error: API values file not found: $API_VALUES_FILE"
    exit 1
fi

# Backup original values file
BACKUP_FILE="${API_VALUES_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
echo "📦 Backing up API values file to: $BACKUP_FILE"
cp "$API_VALUES_FILE" "$BACKUP_FILE"

# Create Kubernetes secret for database password
echo "🔐 Creating Kubernetes secret for database password..."
kubectl create secret generic api-db-secret \
    --from-literal=password="$DB_PASSWORD" \
    --namespace=default \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Database secret created/updated in Kubernetes"

# Update API values file (without password)
echo "📝 Updating API values file..."

# Use sed to update only the database configuration lines (excluding password)
sed -i.bak \
    -e "s|host:.*|host: \"$DB_HOST\"|" \
    -e "s|port:.*|port: $DB_PORT|" \
    -e "s|name:.*|name: \"$DB_DATABASE\"|" \
    -e "s|user:.*|user: \"$DB_USER\"|" \
    -e "s|password:.*|password: \"\" # Set via secret|" \
    "$API_VALUES_FILE"

echo "✅ API values file updated successfully!"
echo ""
echo "📋 Summary:"
echo "================================"
echo "🗄️  Database Host: $DB_HOST"
echo "🚪 Database Port: $DB_PORT"
echo "👤 Database User: $DB_USER"
echo "💾 Database Name: $DB_DATABASE"
echo "🔐 Password Secret: api-db-secret (in Kubernetes)"
echo "📜 CA Certificate: $CA_CERT_FILE"
echo "📝 Values File: $API_VALUES_FILE"
echo "📦 Backup File: $BACKUP_FILE"
echo ""
echo "🎉 Database setup completed successfully!"
echo "💡 Next steps:"
echo "   1. Commit the updated values file to git (password is now secure!)"
echo "   2. Deploy/sync the API application in ArgoCD"
echo "   3. The CA certificate is available at: $CA_CERT_FILE"
echo "   4. Password is stored securely in Kubernetes secret: api-db-secret" 