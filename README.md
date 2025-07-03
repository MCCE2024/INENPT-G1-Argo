# INENPT-G1-Argo

03.07.2025

Multi-tenant Kubernetes application stack with ArgoCD GitOps, Sealed Secrets, and GitHub OAuth authentication.

[!NOTE]

> We worked mostly via the Liveshare extension, so there can often be uneven pushes in the Git repository.

## 📋 Overview

This repository contains the ArgoCD configuration and deployment automation for a multi-tenant application stack consisting of:

- **API Service**: REST API for message management with PostgreSQL database
- **Consumer Service**: Web dashboard with GitHub OAuth authentication
- **Producer Service**: Automated message generation service

### 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Multi-Tenant Architecture                    │
├─────────────────────────────────────────────────────────────────┤
│  mcce.uname.at:30000 → Tenant A → namespace: tenant-a          │
│  mcce.uname.at:30001 → Tenant B → namespace: tenant-b          │
│  mcce.uname.at:30002 → Tenant C → namespace: tenant-c          │
│  mcce.uname.at:30003 → Tenant D → namespace: tenant-d          │
├─────────────────────────────────────────────────────────────────┤
│  Each tenant includes:                                          │
│  • API Service (REST API + Database)                           │
│  • Consumer Service (Web Dashboard + OAuth)                    │
│  • Producer Service (Message Generation)                       │
└─────────────────────────────────────────────────────────────────┘
```

### 🔐 Security Features

- **Sealed Secrets**: Encrypted secrets safe for Git storage
- **Namespace Isolation**: Each tenant runs in separate Kubernetes namespace
- **OAuth Authentication**: GitHub OAuth integration per tenant
- **GitOps Workflow**: Declarative configuration with ArgoCD

## 📁 Repository Structure

```
INENPT-G1-Argo/
├── applications/                    # Helm charts for applications
│   ├── api/helm/                   # API service Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── configmap.yaml
│   │       └── deployment.yaml
│   ├── consumer/helm/              # Consumer service Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       └── service.yaml
│   └── producer/helm/              # Producer service Helm chart
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── cronjob.yaml
│           └── secret.yaml
├── applicationsets/                 # ArgoCD ApplicationSets
│   ├── master-applicationset.yaml  # Master ApplicationSet
│   └── tenants/                    # Tenant-specific ApplicationSets
│       ├── tenant-a/
│       │   └── applicationset.yaml
│       ├── tenant-b/
│       │   └── applicationset.yaml
│       ├── tenant-c/
│       │   └── applicationset.yaml
│       └── tenant-d/
│           └── applicationset.yaml
├── infrastructure/                  # Infrastructure as Code (OpenTofu)
│   ├── argocd.tf                   # ArgoCD deployment
│   ├── argocd-image-updater.tf     # ArgoCD Image Updater
│   ├── sealed-secrets.tf           # Sealed Secrets controller
│   └── kubeconfig.yaml             # Kubernetes cluster config
├── scripts/                        # Automation scripts
│   ├── setup-database.sh           # Database setup with sealed secrets
│   ├── setup-multi-tenant-oauth.sh # OAuth setup for all tenants
│   ├── get-kubeconfig.sh          # Kubernetes access
│   ├── get-argocd-info.sh         # ArgoCD access info
│   ├── setup-cloudflare-dns.sh    # DNS configuration
│   ├── ca.pem                      # Database CA certificate
│   ├── kubeconfig.yaml             # Kubernetes config
│   └── cloudflare-config.txt       # Cloudflare configuration
├── secrets/                        # Encrypted sealed secrets (safe for Git)
│   ├── tenant-a-api-db-sealed-secret.yaml      # Database secrets
│   ├── tenant-a-oauth-sealed-secret.yaml       # OAuth secrets
│   ├── tenant-b-api-db-sealed-secret.yaml      # Database secrets
│   ├── tenant-c-api-db-sealed-secret.yaml      # Database secrets
│   ├── tenant-c-oauth-sealed-secret.yaml       # OAuth secrets
│   ├── tenant-d-api-db-sealed-secret.yaml      # Database secrets
│   └── tenant-d-oauth-sealed-secret.yaml       # OAuth secrets
├── argocd-applicationsets.yaml     # Main ApplicationSet deployment
├── argocd-sync-config.yaml        # ArgoCD sync configuration
└── README.md                       # This comprehensive documentation
```

## 🚀 Quick Start

### Prerequisites

- **Kubernetes Cluster** with kubectl access
- **ArgoCD** installed and configured
- **Sealed Secrets Controller** deployed
- **GitHub Account** for OAuth applications
- **Cloudflare Account** for DNS management (optional)
- **Exo Account** for cluster deployment and DBaaS

Required CLI tools:

- `kubectl`
- `kubeseal` (Sealed Secrets CLI)
- `exo` (Exoscale CLI)
- `yq` (YAML processor)

### 🔧 Setup Instructions

#### Phase 1: Infrastructure Setup

```bash
# 1. Get Kubernetes cluster access
./scripts/get-kubeconfig.sh

# 2. Deploy ArgoCD + Sealed Secrets
cd infrastructure
terraform apply
cd ..

# 3. Get ArgoCD access information
./scripts/get-argocd-info.sh
```

#### Phase 2: Secrets Configuration

```bash
# 4. Setup database connection with sealed secrets
./scripts/setup-database.sh
# Creates: tenant-*-api-db-sealed-secret.yaml (one per tenant)

# 5. Setup OAuth for all tenants
./scripts/setup-multi-tenant-oauth.sh all
# Creates: tenant-*-oauth-sealed-secret.yaml (one per tenant)
```

#### Phase 3: Application Deployment

```bash
# 6. Deploy ApplicationSets
kubectl apply -f argocd-applicationsets.yaml

# 7. Deploy sync configuration
kubectl apply -f argocd-sync-config.yaml
```

#### Phase 4: DNS Configuration (Optional)

```bash
# 8. Setup Cloudflare DNS
./scripts/setup-cloudflare-dns.sh <api-token> <zone-id>
```

## 🔐 Sealed Secrets Integration

This project uses **Sealed Secrets** for secure GitOps workflows:

### What are Sealed Secrets?

Sealed Secrets are encrypted Kubernetes secrets that can only be decrypted by the sealed-secrets controller running in your cluster. This allows safe storage of secrets in Git repositories.

### Benefits

- ✅ **Safe to commit to Git** - Secrets are encrypted
- ✅ **Automatic decryption** - Controller handles decryption
- ✅ **Namespace isolation** - Tenant-specific secrets
- ✅ **GitOps compatible** - Declarative secret management

### Secret Types

| Secret Type                          | Scope      | Purpose                    |
| ------------------------------------ | ---------- | -------------------------- |
| `tenant-*-api-db-sealed-secret.yaml` | Per-tenant | Database credentials       |
| `tenant-*-oauth-sealed-secret.yaml`  | Per-tenant | GitHub OAuth configuration |

### Usage

```bash
# Create sealed secret manually
kubectl create secret generic my-secret \
  --from-literal=key=value \
  --namespace=tenant-a \
  --dry-run=client -o yaml | \
  kubeseal --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets-system \
  -o yaml > my-sealed-secret.yaml

# Apply to cluster
kubectl apply -f my-sealed-secret.yaml
```

## 🏢 Multi-Tenant Configuration

### Tenant Setup

Each tenant requires:

1. **GitHub OAuth Application**

   - Application Name: `MCCE Tenant X`
   - Homepage URL: `http://mcce.uname.at:3000X`
   - Callback URL: `http://mcce.uname.at:3000X/auth/github/callback`

2. **Kubernetes Namespace**

   - Automatically created by setup scripts
   - Isolated resources per tenant

3. **Sealed Secrets**
   - Database credentials
   - OAuth configuration

### Tenant Access URLs

After deployment:

- **Tenant A**: http://mcce.uname.at:30000
- **Tenant B**: http://mcce.uname.at:30001
- **Tenant C**: http://mcce.uname.at:30002
- **Tenant D**: http://mcce.uname.at:30003

### Adding New Tenants

1. Create tenant directory in `applicationsets/tenants/`
2. Configure GitHub OAuth application
3. Run setup scripts for new tenant
4. Update ApplicationSet configurations

## 📜 Scripts Documentation

### Database Setup (`setup-database.sh`)

Configures database connection with sealed secrets:

```bash
./scripts/setup-database.sh
```

**What it does:**

- Retrieves database credentials from Exoscale
- Downloads CA certificate
- Creates sealed secrets for each tenant namespace
- Updates API Helm values

### OAuth Setup (`setup-multi-tenant-oauth.sh`)

Configures GitHub OAuth for tenants:

```bash
# Setup all tenants
./scripts/setup-multi-tenant-oauth.sh all

# Setup specific tenant
./scripts/setup-multi-tenant-oauth.sh tenant-a
```

**What it does:**

- Creates Kubernetes namespaces
- Generates secure session secrets
- Creates OAuth sealed secrets per tenant
- Applies secrets to cluster

### Other Scripts

- `get-kubeconfig.sh` - Retrieves Kubernetes cluster access
- `get-argocd-info.sh` - Shows ArgoCD access information
- `setup-cloudflare-dns.sh` - Configures DNS records

## 🛠️ Management Operations

### Viewing Sealed Secrets

```bash
# List all sealed secrets
kubectl get sealedsecrets -A

# Check specific tenant
kubectl get sealedsecrets -n tenant-a

# View secret content (encrypted)
kubectl get sealedsecret api-db-secret -n tenant-a -o yaml
```

### Updating Secrets

```bash
# Update database secrets
./scripts/setup-database.sh

# Update OAuth secrets for specific tenant
./scripts/setup-multi-tenant-oauth.sh tenant-a

# Update all OAuth secrets
./scripts/setup-multi-tenant-oauth.sh all
```

### Monitoring Applications

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check application pods
kubectl get pods -n tenant-a

# View application logs
kubectl logs -n tenant-a deployment/consumer
```

## 🔍 Troubleshooting

### Common Issues

#### Sealed Secret Not Decrypted

```bash
# Check sealed secret status
kubectl describe sealedsecret api-db-secret -n tenant-a

# Check controller logs
kubectl logs -n sealed-secrets-system -l app.kubernetes.io/name=sealed-secrets
```

#### OAuth Authentication Fails

```bash
# Check OAuth secret
kubectl get secret consumer-oauth-secret -n tenant-a -o yaml

# Check consumer service logs
kubectl logs -n tenant-a deployment/consumer
```

#### Database Connection Issues

```bash
# Check database secret
kubectl get secret api-db-secret -n tenant-a

# Check API service logs
kubectl logs -n tenant-a deployment/api
```

### Useful Commands

```bash
# Check all tenant namespaces
kubectl get namespaces | grep tenant

# Check services in tenant namespace
kubectl get services -n tenant-a

# Check resource usage
kubectl top pods -n tenant-a

# Test connectivity
kubectl exec -n tenant-a deployment/consumer -- curl http://api-service:80/health
```

## 🔒 Security Considerations

### Sealed Secrets Security

- **Encryption**: Secrets encrypted with cluster-specific keys
- **Scope**: Namespace-scoped secrets for tenant isolation
- **Backup**: Private keys should be backed up for disaster recovery

### Multi-Tenant Security

- **Namespace Isolation**: Each tenant runs in separate namespace
- **Resource Limits**: Defined CPU/memory limits per tenant
- **Network Policies**: Consider implementing for additional isolation
- **OAuth Isolation**: Separate OAuth apps per tenant

### Best Practices

1. **Regular Key Rotation**: Sealed secrets keys rotate automatically
2. **Secret Backup**: Backup sealed-secrets private keys
3. **Access Control**: Use RBAC for ArgoCD access
4. **Monitoring**: Monitor secret decryption status

## 📊 Monitoring and Observability

### Health Checks

```bash
# Check all applications
kubectl get applications -n argocd

# Check sealed secrets status
kubectl get sealedsecrets -A

# Check pod health
kubectl get pods -A | grep -E "(tenant-|argocd|sealed-secrets)"
```

### Logs

```bash
# ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# Sealed secrets controller logs
kubectl logs -n sealed-secrets-system -l app.kubernetes.io/name=sealed-secrets

# Application logs
kubectl logs -n tenant-a deployment/api
kubectl logs -n tenant-a deployment/consumer
kubectl logs -n tenant-a deployment/producer
```

## 🆘 Support

### Getting Help

1. **Check Application Logs**: Review pod logs in tenant namespaces
2. **Verify Secrets**: Ensure sealed secrets are properly decrypted
3. **Check ArgoCD**: Verify application sync status
4. **Test Connectivity**: Validate service-to-service communication

### Backup and Recovery

Important components to backup:

- Sealed secrets private keys
- ArgoCD configuration
- Database credentials
- OAuth application settings

```bash
# Backup sealed secrets private key
kubectl get secret -n sealed-secrets-system sealed-secrets-key -o yaml > sealed-secrets-key-backup.yaml
```

## 📝 Contributing

When making changes:

1. **Test Locally**: Validate changes in development environment
2. **Update Documentation**: Keep README and scripts documentation current
3. **Security Review**: Ensure secrets are properly encrypted
4. **GitOps Workflow**: All changes should go through Git

## 📄 License

This project is part of the INENPT-G1 course work.

---

**🔐 Remember**: All sealed secret files in this repository are encrypted and safe to commit to version control. Only the sealed-secrets controller in your cluster can decrypt them.
