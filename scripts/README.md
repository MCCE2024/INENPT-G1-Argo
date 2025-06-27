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
7. `kubectl apply -f ../applicationsets/multi-tenant-applicationset.yaml` - Deploy applications

### Phase 4: DNS Setup (after apps are running)

8. `setup-multi-tenant-dns.sh <token> <zone-id>` - Setup Cloudflare DNS

## Quick Start

```bash
./get-kubeconfig.sh
cd ../infrastructure && terraform apply && cd ../scripts
./get-argocd-info.sh
./setup-database.sh
./create-db-secret.sh tenant-a
./create-db-secret.sh tenant-b
./create-db-secret.sh tenant-c
./setup-multi-tenant-oauth.sh all
kubectl apply -f ../applicationsets/multi-tenant-applicationset.yaml
# Wait for applications to be deployed, then:
./setup-multi-tenant-dns.sh <your-token> <your-zone-id>
```

All scripts include `--help` for detailed usage.
