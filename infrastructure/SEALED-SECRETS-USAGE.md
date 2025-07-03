# Sealed Secrets Usage Guide

This guide covers how to use Sealed Secrets in your Kubernetes cluster for secure GitOps workflows.

## 🔐 Overview

Sealed Secrets allows you to encrypt Kubernetes secrets so they can be safely stored in Git repositories. The controller in your cluster can decrypt them back into regular secrets.

## 📦 Installation of kubeseal CLI

### Linux/WSL

```bash
wget https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz
tar -xvf kubeseal-0.24.0-linux-amd64.tar.gz
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

### macOS

```bash
brew install kubeseal
```

### Windows

```powershell
# Using Chocolatey
choco install kubeseal

# Or download from GitHub releases and add to PATH
```

### Verify Installation

```bash
kubeseal --version
```

## 🚀 Basic Usage

### Step 1: Create a Regular Secret (Don't Apply!)

```yaml
# secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: my-app-secret
  namespace: default
type: Opaque
data:
  username: YWRtaW4= # admin (base64)
  password: cGFzc3dvcmQ= # password (base64)
```

### Step 2: Seal the Secret

```bash
# From file
kubeseal -f secret.yaml -w sealed-secret.yaml

# From kubectl command (recommended)
kubectl create secret generic my-app-secret \
  --dry-run=client \
  --from-literal=username=admin \
  --from-literal=password=password \
  -o yaml | kubeseal -o yaml > sealed-secret.yaml
```

### Step 3: Commit and Apply

```bash
# Safe to commit to Git
git add sealed-secret.yaml
git commit -m "Add application secrets"

# Apply to cluster
kubectl apply -f sealed-secret.yaml
```

### Step 4: Verify

```bash
# Check if SealedSecret was created
kubectl get sealedsecrets

# Check if regular Secret was created by controller
kubectl get secrets my-app-secret
```

## 🔧 Advanced Usage

### Encryption Scopes

#### Strict (Default)

Secret must be unsealed with the exact same name and namespace:

```bash
kubeseal -f secret.yaml -w sealed-secret.yaml
```

#### Namespace-wide

Can be unsealed by any secret within the same namespace:

```bash
kubeseal --scope namespace-wide -f secret.yaml -w sealed-secret.yaml
```

#### Cluster-wide

Can be unsealed anywhere in the cluster:

```bash
kubeseal --scope cluster-wide -f secret.yaml -w sealed-secret.yaml
```

### Working with Certificates

#### Fetch Public Certificate

```bash
kubeseal --fetch-cert > public.pem
```

#### Use Custom Certificate

```bash
kubeseal --cert=public.pem -f secret.yaml -w sealed-secret.yaml
```

#### Offline Sealing

```bash
# Get cert once
kubeseal --fetch-cert > public.pem

# Use offline (no cluster access needed)
kubeseal --cert=public.pem -f secret.yaml -w sealed-secret.yaml
```

### Raw Mode (Single Values)

```bash
# Encrypt a single value
echo -n "supersecret" | kubeseal --raw --from-file=/dev/stdin --name=my-secret --namespace=default

# Use in YAML
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: my-secret
  namespace: default
spec:
  encryptedData:
    password: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEQAx...
```

## 🔄 GitOps Workflow Integration

### With ArgoCD

1. **Create secrets locally**
2. **Seal them with kubeseal**
3. **Commit SealedSecrets to Git**
4. **ArgoCD syncs to cluster**
5. **Controller creates regular secrets**
6. **Applications use the secrets**

### Example Application

```yaml
# app-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          image: my-app:latest
          env:
            - name: DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: my-app-secret # This will be created by sealed-secrets controller
                  key: username
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: my-app-secret
                  key: password
```

## 🛠️ Multi-Tenant Usage

### Tenant-Specific Secrets

```bash
# Tenant A
kubectl create secret generic db-secret \
  --namespace=tenant-a \
  --dry-run=client \
  --from-literal=password=tenant-a-password \
  -o yaml | kubeseal -o yaml > tenant-a-db-secret.yaml

# Tenant B
kubectl create secret generic db-secret \
  --namespace=tenant-b \
  --dry-run=client \
  --from-literal=password=tenant-b-password \
  -o yaml | kubeseal -o yaml > tenant-b-db-secret.yaml
```

### Shared Secrets (Cluster-wide)

```bash
kubectl create secret generic shared-api-key \
  --namespace=shared-services \
  --dry-run=client \
  --from-literal=api-key=shared-key \
  -o yaml | kubeseal --scope cluster-wide -o yaml > shared-api-key.yaml
```

## 🔄 Key Management

### Backup Private Key

```bash
#!/bin/bash
# backup-sealed-secrets-key.sh

echo "Backing up sealed secrets private key..."
kubectl get secret -n sealed-secrets-system sealed-secrets-key -o yaml > sealed-secrets-key-backup-$(date +%Y%m%d).yaml
echo "Key backed up to sealed-secrets-key-backup-$(date +%Y%m%d).yaml"
echo "⚠️  Store this file securely - it's needed for disaster recovery!"
```

### Restore Private Key

```bash
# In case of disaster recovery
kubectl apply -f sealed-secrets-key-backup-YYYYMMDD.yaml
kubectl delete pod -n sealed-secrets-system -l app.kubernetes.io/name=sealed-secrets
```

### Key Rotation

Keys are automatically rotated every 30 days. Old keys are kept for decryption of existing secrets.

## 🔍 Troubleshooting

### Check Controller Status

```bash
# Check if controller is running
kubectl get pods -n sealed-secrets-system

# Check controller logs
kubectl logs -n sealed-secrets-system -l app.kubernetes.io/name=sealed-secrets

# Check controller service
kubectl get svc -n sealed-secrets-system
```

### Verify SealedSecret Processing

```bash
# List all SealedSecrets
kubectl get sealedsecrets -A

# Check specific SealedSecret
kubectl describe sealedsecret my-app-secret -n default

# Check if corresponding Secret was created
kubectl get secrets -A | grep -v "kubernetes.io"
```

### Common Issues

#### SealedSecret Not Decrypted

```bash
# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Check SealedSecret status
kubectl get sealedsecret <name> -n <namespace> -o yaml
```

#### Wrong Namespace/Name

```bash
# SealedSecrets are bound to specific namespace/name by default
# Recreate with correct metadata:
kubectl create secret generic correct-name \
  --namespace=correct-namespace \
  --dry-run=client \
  --from-literal=key=value \
  -o yaml | kubeseal -o yaml > fixed-sealed-secret.yaml
```

#### Certificate Issues

```bash
# Fetch fresh certificate
kubeseal --fetch-cert > fresh-cert.pem

# Verify certificate
openssl x509 -in fresh-cert.pem -text -noout
```

## 📋 Best Practices

### 1. **Naming Convention**

```bash
# Use descriptive names
my-app-database-secret
my-app-api-keys
shared-registry-credentials
```

### 2. **Namespace Organization**

```bash
# Tenant-specific secrets
tenant-a/database-secret
tenant-b/database-secret

# Shared secrets with cluster-wide scope
shared-services/registry-secret (cluster-wide)
```

### 3. **Version Control**

```bash
# Organize in directories
secrets/
├── tenant-a/
│   ├── database-secret.yaml
│   └── api-keys.yaml
├── tenant-b/
│   ├── database-secret.yaml
│   └── api-keys.yaml
└── shared/
    └── registry-secret.yaml
```

### 4. **Security**

- ✅ **Always** use `--dry-run=client` when creating secrets
- ✅ **Never** apply regular secrets to cluster
- ✅ **Backup** the controller's private key
- ✅ **Rotate** keys regularly (automated)
- ✅ **Use** appropriate scopes (strict by default)

### 5. **CI/CD Integration**

```yaml
# GitHub Actions example
- name: Seal secrets
  run: |
    kubeseal --fetch-cert > cert.pem
    find secrets/ -name "*.yaml" -exec kubeseal --cert=cert.pem -f {} -w {}.sealed \;

- name: Commit sealed secrets
  run: |
    git add secrets/*.sealed
    git commit -m "Update sealed secrets"
```

## 🔗 Integration Examples

### Database Secret

```bash
kubectl create secret generic postgres-secret \
  --namespace=production \
  --dry-run=client \
  --from-literal=username=postgres \
  --from-literal=password=supersecretpassword \
  --from-literal=database=myapp \
  -o yaml | kubeseal -o yaml > postgres-sealed-secret.yaml
```

### Registry Credentials

```bash
kubectl create secret docker-registry registry-secret \
  --namespace=default \
  --dry-run=client \
  --docker-server=ghcr.io \
  --docker-username=myuser \
  --docker-password=mytoken \
  -o yaml | kubeseal --scope cluster-wide -o yaml > registry-sealed-secret.yaml
```

### TLS Certificate

```bash
kubectl create secret tls tls-secret \
  --namespace=ingress-nginx \
  --dry-run=client \
  --cert=tls.crt \
  --key=tls.key \
  -o yaml | kubeseal -o yaml > tls-sealed-secret.yaml
```

---

## 📞 Support

- **Controller Issues**: Check logs in `sealed-secrets-system` namespace
- **CLI Issues**: Verify kubeseal version and cluster connectivity
- **Key Issues**: Ensure private key backup exists
- **Scope Issues**: Review encryption scope settings

**Remember**: Sealed Secrets are only as secure as your private key backup! 🔐
