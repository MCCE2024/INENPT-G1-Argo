# Scripts Directory

Automation scripts for INENPT-G1 multi-tenant Kubernetes setup.

## Execution Order

### Phase 1: Infrastructure

1. `get-kubeconfig.sh` - Get Kubernetes cluster access
2. Deploy ArgoCD: `cd ../infrastructure && terraform apply`
3. `get-argocd-info.sh` - Get ArgoCD access info

### Phase 2: Database

4. `setup-database.sh` - Configure database connection
5. `create-db-secret.sh <namespace>` - Create DB secrets per tenant

### Phase 3: Deploy Applications

6. `setup-multi-tenant-oauth.sh all` - Setup GitHub OAuth for all tenants
7. `kubectl apply -f ../argocd-applicationsets.yaml` - Deploy applications
8. `kubectl apply -f ../argocd-sync-config.yaml` - Deploy Sync Config

### Phase 4: DNS Setup (after apps are running)

8. `setup-multi-tenant-dns.sh <token> <zone-id>` - Setup Cloudflare DNS

## Quick Start

```bash
#installed programs neeeded
# exo
# kubectl

#initial setup after cluster deployment
./get-kubeconfig.sh
cd ../infrastructure && terraform apply && cd ../scripts
./get-argocd-info.sh
./setup-database.sh
#setup database changes the values file for the api helm chart
# because after the initial deployment we have a new db, with a new URL
# and a new user pair
# which needs to be pushed to the repo afterwards
kubectl apply -f ../argocd-applicationsets.yaml
kubectl apply -f ../argocd-sync-config.yaml

#If you are using cloudflare and want to add dns records
./setup-multi-tenant-dns.sh <your-token> <your-zone-id>

# setup db secrets for tenants
./create-db-secret.sh tenant-a
./create-db-secret.sh tenant-b
./create-db-secret.sh tenant-c
./create-db-secret.sh tenant-d

# Setup oauth
# One oauth app per tenant
# Oauth apps need to be created manually on Github
./setup-multi-tenant-oauth.sh tenant-a
./setup-multi-tenant-oauth.sh tenant-b
./setup-multi-tenant-oauth.sh tenant-c
./setup-multi-tenant-oauth.sh tenant-d

```

All scripts include `--help` for detailed usage.
