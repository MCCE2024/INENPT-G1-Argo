# Sealed Secrets

This directory contains sealed secrets that are safe to store in version control.

## 🔐 What are Sealed Secrets?

Sealed Secrets are encrypted Kubernetes secrets that can only be decrypted by the sealed-secrets controller running in your cluster. This allows you to safely store secrets in Git repositories as part of your GitOps workflow.

## 📁 Files in this directory

- `api-db-sealed-secret.yaml` - Database credentials for the API application (cluster-wide)
- `consumer-oauth-sealed-secret.yaml` - OAuth configuration for single-tenant Consumer application (cluster-wide)
- `tenant-a-oauth-sealed-secret.yaml` - OAuth configuration for tenant-a (namespace-scoped)
- `tenant-b-oauth-sealed-secret.yaml` - OAuth configuration for tenant-b (namespace-scoped)
- `tenant-c-oauth-sealed-secret.yaml` - OAuth configuration for tenant-c (namespace-scoped)
- `tenant-d-oauth-sealed-secret.yaml` - OAuth configuration for tenant-d (namespace-scoped)
- Add other sealed secrets here as needed

## 🔒 Security

- ✅ **Safe to commit to Git** - These files are encrypted and can only be decrypted by your cluster
- ✅ **Cluster-wide scope** - These secrets can be accessed from all namespaces
- ✅ **Automatic decryption** - The sealed-secrets controller automatically creates regular Kubernetes secrets

## 🚀 Usage

1. **Generate sealed secrets** using the `setup-database.sh` script or manually with `kubeseal`
2. **Commit to Git** - Sealed secrets are safe to store in version control
3. **Deploy via ArgoCD** - The sealed-secrets controller will automatically decrypt them
4. **Reference in applications** - Use the regular secret names in your Helm templates

## 📖 More Information

See the [Sealed Secrets Usage Guide](../infrastructure/SEALED-SECRETS-USAGE.md) for detailed instructions on how to work with sealed secrets.
