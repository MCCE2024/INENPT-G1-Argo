# Scripts Directory

Automation scripts for INENPT-G1 multi-tenant Kubernetes setup with Sealed Secrets.

## 🔐 Sealed Secrets Integration

This setup uses **Sealed Secrets** for secure GitOps workflows:

- ✅ **Safe to store in Git** - Secrets are encrypted and can only be decrypted by your cluster
- ✅ **Cluster-wide access** - Secrets can be accessed from all namespaces
- ✅ **Automatic decryption** - The sealed-secrets controller handles decryption automatically

## Execution Order

### Phase 1: Infrastructure

1. `get-kubeconfig.sh` - Get Kubernetes cluster access
2. Deploy ArgoCD + Sealed Secrets: `cd ../infrastructure && terraform apply`
3. `get-argocd-info.sh` - Get ArgoCD access info

### Phase 2: Secrets Setup (Sealed Secrets)

4. `setup-database.sh` - Configure database connection + create sealed secret (cluster-wide)
5. `setup-multi-tenant-oauth.sh all` - Create OAuth sealed secrets for all tenants (namespace-scoped)

### Phase 3: Deploy Applications

6. `kubectl apply -f ../argocd-applicationsets.yaml` - Deploy applications
7. `kubectl apply -f ../argocd-sync-config.yaml` - Deploy Sync Config

### Phase 4: DNS Setup (after apps are running)

8. `setup-cloudflare-dns.sh <token> <zone-id>` - Setup Cloudflare DNS

## Quick Start

```bash
# Required programs:
# - exo (Exoscale CLI)
# - kubectl
# - kubeseal (Sealed Secrets CLI)

# Initial setup after cluster deployment
./get-kubeconfig.sh
cd ../infrastructure && terraform apply && cd ../scripts
./get-argocd-info.sh

# Setup database with sealed secrets (cluster-wide)
./setup-database.sh
# This script:
# - Gets database credentials from Exoscale
# - Creates a sealed secret (cluster-wide)
# - Updates API values file
# - Commits are safe - sealed secrets are encrypted!

# Multi-tenant OAuth (namespace-scoped per tenant)
./setup-multi-tenant-oauth.sh all
# This script:
# - Creates separate sealed secret for each tenant
# - Prompts for OAuth credentials per tenant
# - Namespace-scoped for tenant isolation
# - Safe to commit to git!

# Deploy applications
kubectl apply -f ../argocd-applicationsets.yaml
kubectl apply -f ../argocd-sync-config.yaml

# Setup DNS (if using Cloudflare)
./setup-cloudflare-dns.sh <your-token> <your-zone-id>

# Setup multi-tenant OAuth (creates GitHub OAuth apps per tenant)
./setup-multi-tenant-oauth.sh tenant-a
./setup-multi-tenant-oauth.sh tenant-b
./setup-multi-tenant-oauth.sh tenant-c
./setup-multi-tenant-oauth.sh tenant-d
```

## 🔐 Sealed Secrets Files

After running the setup scripts, you'll have encrypted secret files in `../secrets/`:

- `api-db-sealed-secret.yaml` - Database credentials (cluster-wide)
- `consumer-oauth-sealed-secret.yaml` - OAuth configuration for single-tenant (cluster-wide)
- `tenant-*-oauth-sealed-secret.yaml` - OAuth configuration for each tenant (namespace-scoped)

**These files are safe to commit to Git!** They're encrypted and can only be decrypted by your cluster.

## 📚 Legacy Scripts (Deprecated)

- `create-db-secret.sh` - ⚠️ Creates regular secrets per namespace (deprecated)
  - Use `setup-database.sh` instead for sealed secrets

## 📖 More Information

- [Sealed Secrets Usage Guide](../infrastructure/SEALED-SECRETS-USAGE.md)
- [Sealed Secrets Directory](../secrets/README.md)

All scripts include `--help` for detailed usage.
