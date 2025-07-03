#!/usr/bin/bash

# Database Setup Script
# 1. Gets the database URL from Exoscale
# 2. Prompts user for password
# 3. Downloads CA certificate
# 4. Creates sealed secret for database password (cluster-wide)
# 5. Updates API values file

set -e  # Exit on any error

# Configuration
DB_NAME="inenpt-g1-postgresql"
ZONE="at-vie-1"
API_VALUES_FILE="../applications/api/helm/values.yaml"
CA_CERT_FILE="ca.pem"
SEALED_SECRET_FILE="../secrets/api-db-sealed-secret.yaml"

echo "🗄️  Setting up database configuration for API with Sealed Secrets..."
echo ""

# Check if required tools are available
if ! command -v exo &> /dev/null; then
    echo "❌ Error: exo CLI is not installed or not in PATH"
    exit 1
fi

if ! command -v kubeseal &> /dev/null; then
    echo "❌ Error: kubeseal CLI is not installed or not in PATH"
    echo "💡 Install kubeseal: https://github.com/bitnami-labs/sealed-secrets#installation"
    exit 1
fi

# Create secrets directory if it doesn't exist
mkdir -p ../secrets

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

# Update values.yaml with CA certificate content
echo "🔐 Adding CA certificate content to values.yaml..."

# Check if CA certificate is already in values.yaml
if grep -q "BEGIN CERTIFICATE" "$API_VALUES_FILE"; then
    echo "💡 CA certificate already exists in values.yaml - replacing with fresh content"
    
    # Create a temporary file with the new certificate content
    TEMP_CERT_FILE=$(mktemp)
    cat "$CA_CERT_FILE" | sed 's/^/    /' > "$TEMP_CERT_FILE"
    
    # Use awk to replace the certificate content between caCert: | and the next non-indented line
    awk '
    /caCert: \|/ { 
        print $0
        # Read and print the new certificate content
        while ((getline line < "'$TEMP_CERT_FILE'") > 0) {
            print line
        }
        close("'$TEMP_CERT_FILE'")
        # Skip existing certificate content
        while (getline > 0 && /^    /) continue
        if (NF > 0) print $0
        next
    }
    { print }
    ' "$API_VALUES_FILE" > "${API_VALUES_FILE}.tmp" && mv "${API_VALUES_FILE}.tmp" "$API_VALUES_FILE"
    
    # Clean up temporary files
    rm -f "$TEMP_CERT_FILE"
else
    echo "💡 Adding CA certificate content for the first time"
    
    # Create a temporary file with the CA certificate content properly indented
    TEMP_CERT_FILE=$(mktemp)
    cat "$CA_CERT_FILE" | sed 's/^/    /' > "$TEMP_CERT_FILE"

    # Create a new values file with the CA certificate content
    TEMP_VALUES_FILE=$(mktemp)

    # Process the values file line by line
    while IFS= read -r line; do
        echo "$line" >> "$TEMP_VALUES_FILE"
        # If we find the caCert: | line, append the certificate content
        if [[ "$line" == *"caCert: |"* ]]; then
            cat "$TEMP_CERT_FILE" >> "$TEMP_VALUES_FILE"
        fi
    done < "$API_VALUES_FILE"

    # Replace the original file
    mv "$TEMP_VALUES_FILE" "$API_VALUES_FILE"

    # Clean up temporary files
    rm -f "$TEMP_CERT_FILE"
fi

echo "✅ CA certificate content updated in values.yaml"
echo "💡 The Helm template will now create ConfigMaps automatically when deployed"

# Check if API values file exists
if [ ! -f "$API_VALUES_FILE" ]; then
    echo "❌ Error: API values file not found: $API_VALUES_FILE"
    exit 1
fi

# Backup original values file
BACKUP_FILE="${API_VALUES_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
echo "📦 Backing up API values file to: $BACKUP_FILE"
cp "$API_VALUES_FILE" "$BACKUP_FILE"

# Create sealed secret for database password (cluster-wide)
echo "🔐 Creating sealed secret for database password..."
echo "💡 Using cluster-wide scope so it can be accessed from all namespaces"

# Create the sealed secret using kubeseal with cluster-wide scope
# This allows the secret to be accessed from any namespace
kubectl create secret generic api-db-secret \
    --from-literal=password="$DB_PASSWORD" \
    --namespace=default \
    --dry-run=client -o yaml | \
    kubeseal --controller-name=sealed-secrets --controller-namespace=sealed-secrets-system --scope cluster-wide -o yaml > "$SEALED_SECRET_FILE"

echo "✅ Sealed secret created: $SEALED_SECRET_FILE"
echo "🔒 Secret is cluster-wide and can be accessed from all namespaces"

# Apply the sealed secret to the cluster
echo "🚀 Applying sealed secret to cluster..."
kubectl apply -f "$SEALED_SECRET_FILE"

echo "✅ Sealed secret applied successfully!"

# Update API values file (without password)
echo "📝 Updating API values file..."

# Use sed to update only the database configuration lines (excluding password)
# Target only lines within the database section
sed -i.bak \
    -e "/^database:/,/^[^ ]/ { s|  host:.*|  host: \"$DB_HOST\"|; }" \
    -e "/^database:/,/^[^ ]/ { s|  port:.*|  port: $DB_PORT|; }" \
    -e "/^database:/,/^[^ ]/ { s|  name:.*|  name: \"$DB_DATABASE\"|; }" \
    -e "/^database:/,/^[^ ]/ { s|  user:.*|  user: \"$DB_USER\"|; }" \
    -e "/^database:/,/^[^ ]/ { s|  password:.*|  password: \"\" # Set via sealed secret|; }" \
    "$API_VALUES_FILE"

echo "✅ API values file updated successfully!"
echo ""
echo "📋 Summary:"
echo "================================"
echo "🗄️  Database Host: $DB_HOST"
echo "🚪 Database Port: $DB_PORT"
echo "👤 Database User: $DB_USER"
echo "💾 Database Name: $DB_DATABASE"
echo "🔐 Password Sealed Secret: api-db-secret (cluster-wide)"
echo "📜 CA Certificate: $CA_CERT_FILE"
echo "📝 Values File: $API_VALUES_FILE"
echo "📦 Backup File: $BACKUP_FILE"
echo "🔒 Sealed Secret File: $SEALED_SECRET_FILE"
echo ""
echo "🎉 Database setup with Sealed Secrets completed successfully!"
echo "💡 Next steps:"
echo "   1. Commit the sealed secret file to git - it's safe to store in version control!"
echo "   2. Commit the updated values file to git"
echo "   3. Deploy/sync the API application in ArgoCD"
echo "   4. The sealed secret will be automatically decrypted by the sealed-secrets controller"
echo "   5. Applications in any namespace can now reference the 'api-db-secret' secret"
echo ""
echo "🔒 Security Notes:"
echo "   - The sealed secret is encrypted and safe to store in Git"
echo "   - Only the sealed-secrets controller in your cluster can decrypt it"
echo "   - The secret is cluster-wide, so it can be accessed from all namespaces"
echo "   - Regular secret 'api-db-secret' will be created automatically in each namespace that needs it" 