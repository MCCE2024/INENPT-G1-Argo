# Multi-Tenant OAuth Implementation

This document explains how to deploy and manage multiple tenant instances of the MCCE application stack with separate OAuth configurations.

## Overview

The multi-tenant setup provides:

- **3 Tenants**: Tenant A, Tenant B, and Tenant C
- **Separate OAuth Apps**: Each tenant has its own GitHub OAuth application
- **Namespace Isolation**: Each tenant runs in its own Kubernetes namespace
- **Port-based Access**: Same domain, different ports (30000, 30001, 30002)
- **Shared Database**: All tenants use the same database (defaultdb)

## Architecture

```
mcce.uname.at:30000 → Tenant A → namespace: tenant-a
mcce.uname.at:30001 → Tenant B → namespace: tenant-b
mcce.uname.at:30002 → Tenant C → namespace: tenant-c
```

Each tenant includes:

- **API Service**: REST API for message management
- **Consumer Service**: Web dashboard with GitHub OAuth
- **Producer Service**: Message generation service

## Prerequisites

1. **Kubernetes Cluster** with kubectl access
2. **ArgoCD** installed and configured
3. **Cloudflare Account** with API access to `uname.at` domain
4. **GitHub Account** to create OAuth applications
5. **yq** tool for YAML processing (optional but recommended)

## Setup Instructions

### Step 1: DNS Configuration

Set up the shared domain that all tenants will use:

```bash
# Using saved Cloudflare credentials
./scripts/setup-multi-tenant-dns.sh

# Or provide new credentials
./scripts/setup-multi-tenant-dns.sh <cloudflare-api-token> <zone-id>
```

This creates a single DNS A record pointing `mcce.uname.at` to your cluster IP.

### Step 2: Create GitHub OAuth Applications

Create **3 separate GitHub OAuth Apps** with these settings:

#### Tenant A (Development)

- **Application Name**: `MCCE Tenant A`
- **Homepage URL**: `http://mcce.uname.at:30000`
- **Authorization callback URL**: `http://mcce.uname.at:30000/auth/github/callback`

#### Tenant B (Staging)

- **Application Name**: `MCCE Tenant B`
- **Homepage URL**: `http://mcce.uname.at:30001`
- **Authorization callback URL**: `http://mcce.uname.at:30001/auth/github/callback`

#### Tenant C (Production)

- **Application Name**: `MCCE Tenant C`
- **Homepage URL**: `http://mcce.uname.at:30002`
- **Authorization callback URL**: `http://mcce.uname.at:30002/auth/github/callback`

**Note**: Save the Client ID and Client Secret for each application.

### Step 3: Configure OAuth Secrets

Set up OAuth secrets for all tenants:

```bash
# Interactive setup for all tenants
./scripts/setup-multi-tenant-oauth.sh all

# Or setup individual tenants
./scripts/setup-multi-tenant-oauth.sh tenant-a
./scripts/setup-multi-tenant-oauth.sh tenant-b
./scripts/setup-multi-tenant-oauth.sh tenant-c
```

The script will:

- Create Kubernetes namespaces for each tenant
- Generate secure session secrets
- Create `consumer-oauth-secret` in each namespace
- Display the OAuth app configuration details

### Step 4: Deploy Applications

Deploy all tenant applications using the ArgoCD ApplicationSet:

```bash
kubectl apply -f applicationsets/multi-tenant-applicationset.yaml
```

This will automatically create **9 ArgoCD Applications** (3 apps × 3 tenants):

- `tenant-a-api`, `tenant-a-consumer`, `tenant-a-producer`
- `tenant-b-api`, `tenant-b-consumer`, `tenant-b-producer`
- `tenant-c-api`, `tenant-c-consumer`, `tenant-c-producer`

### Step 5: Verify Deployment

Check that all applications are synced and healthy:

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check tenant namespaces
kubectl get namespaces | grep tenant

# Check services in each namespace
kubectl get services -n tenant-a
kubectl get services -n tenant-b
kubectl get services -n tenant-c
```

## Access URLs

After deployment, your tenants will be available at:

- **Tenant A**: http://mcce.uname.at:30000
- **Tenant B**: http://mcce.uname.at:30001
- **Tenant C**: http://mcce.uname.at:30002

## Configuration Details

### Tenant Configuration

Tenant settings are defined in `tenants/tenant-config.yaml`:

```yaml
tenants:
  - name: "tenant-a"
    namespace: "tenant-a"
    displayName: "Tenant A"
    nodePort: 30000
    domain: "mcce.uname.at"
    database:
      name: "defaultdb"
    resources:
      limits:
        cpu: "500m"
        memory: "512Mi"
```

### OAuth Secret Structure

Each tenant gets its own OAuth secret with:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: consumer-oauth-secret
  namespace: <tenant-namespace>
data:
  github-client-id: <base64-encoded-client-id>
  github-client-secret: <base64-encoded-client-secret>
  session-secret: <base64-encoded-session-secret>
```

### ApplicationSet Template

The ApplicationSet generates applications with tenant-specific values:

```yaml
tenant:
  name: "{{tenant}}"
  port: { { nodePort } }
service:
  type: NodePort
  nodePort: { { nodePort } }
api:
  baseUrl: "http://{{tenant}}-api-service:80"
```

## Management Operations

### Adding a New Tenant

1. **Update Configuration**: Add tenant to `tenants/tenant-config.yaml`
2. **Create OAuth App**: Set up GitHub OAuth application
3. **Configure Secrets**: Run `./scripts/setup-multi-tenant-oauth.sh <new-tenant>`
4. **Update ApplicationSet**: Add tenant to the generator list
5. **Apply Changes**: `kubectl apply -f applicationsets/multi-tenant-applicationset.yaml`

### Updating OAuth Credentials

```bash
# Update specific tenant
./scripts/setup-multi-tenant-oauth.sh tenant-a

# Update all tenants
./scripts/setup-multi-tenant-oauth.sh all
```

### Removing a Tenant

1. **Delete Applications**: Remove from ApplicationSet and apply
2. **Clean up Secrets**: `kubectl delete secret consumer-oauth-secret -n <tenant-namespace>`
3. **Delete Namespace**: `kubectl delete namespace <tenant-namespace>`
4. **Revoke OAuth App**: Delete GitHub OAuth application

## Troubleshooting

### OAuth Issues

```bash
# Check OAuth secret
kubectl get secret consumer-oauth-secret -n tenant-a -o yaml

# Check consumer logs
kubectl logs -n tenant-a deployment/consumer

# Test OAuth flow
curl -I http://mcce.uname.at:30000/auth/github
```

### DNS Issues

```bash
# Test DNS resolution
nslookup mcce.uname.at

# Check if ports are accessible
telnet mcce.uname.at 30000
```

### ArgoCD Issues

```bash
# Check application status
kubectl get applications -n argocd

# View application details
kubectl describe application tenant-a-consumer -n argocd

# Check ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server
```

## Security Considerations

1. **OAuth Isolation**: Each tenant has separate OAuth apps and secrets
2. **Namespace Isolation**: Tenants run in separate Kubernetes namespaces
3. **Resource Limits**: Each tenant has defined resource constraints
4. **Session Security**: Unique session secrets per tenant
5. **Network Policies**: Consider implementing network policies for additional isolation

## Monitoring

Monitor tenant health and usage:

```bash
# Check resource usage per tenant
kubectl top pods -n tenant-a
kubectl top pods -n tenant-b
kubectl top pods -n tenant-c

# Monitor application metrics
kubectl get pods -n tenant-a -o wide
```

## Backup and Recovery

Important data to backup:

- OAuth secrets in each namespace
- Tenant configuration files
- ArgoCD application definitions
- Cloudflare DNS configuration

```bash
# Backup OAuth secrets
kubectl get secret consumer-oauth-secret -n tenant-a -o yaml > tenant-a-oauth-backup.yaml
```

## Support

For issues or questions:

1. Check application logs in the respective tenant namespace
2. Verify OAuth app configuration in GitHub
3. Ensure DNS resolution is working
4. Check ArgoCD application sync status
