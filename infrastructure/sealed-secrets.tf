# Sealed Secrets Controller installation
# Provides secure secrets management for GitOps workflows

resource "kubernetes_namespace" "sealed_secrets" {
  metadata {
    name = "sealed-secrets-system"
    labels = {
      "app.kubernetes.io/name"     = "sealed-secrets"
      "app.kubernetes.io/instance" = "sealed-secrets-controller"
    }
  }
}

resource "helm_release" "sealed_secrets" {
  name       = "sealed-secrets"
  repository = "https://bitnami-labs.github.io/sealed-secrets"
  chart      = "sealed-secrets"
  namespace  = kubernetes_namespace.sealed_secrets.metadata[0].name
  version    = "2.17.3"

  values = [
    yamlencode({
      # Controller configuration
      controller = {
        # Resource limits for the controller
        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
        
        # Security context
        securityContext = {
          runAsNonRoot = true
          runAsUser    = 1001
          fsGroup      = 1001
        }
        
        # Pod security context
        podSecurityContext = {
          runAsNonRoot = true
          runAsUser    = 1001
          fsGroup      = 1001
        }
        
        # Additional labels for the controller
        labels = {
          "app.kubernetes.io/component" = "controller"
        }
      }
      
      # Service account configuration
      serviceAccount = {
        create = true
        name   = "sealed-secrets-controller"
        labels = {
          "app.kubernetes.io/component" = "controller"
        }
      }
      
      # RBAC configuration
      rbac = {
        create = true
        labels = {
          "app.kubernetes.io/component" = "rbac"
        }
      }
      
      # Service configuration
      service = {
        type = "ClusterIP"
        port = 8080
        labels = {
          "app.kubernetes.io/component" = "service"
        }
      }
      
      # Key renewal and rotation settings
      keyrenewperiod = "30d"  # Renew keys every 30 days
      
      # Metrics configuration
      metrics = {
        serviceMonitor = {
          enabled = false  # Set to true if you have Prometheus operator
        }
      }
      
      # Network policies (if needed)
      networkPolicy = {
        enabled = false  # Set to true if you need network isolation
      }
      
      # Additional environment variables
      env = [
        {
          name  = "SEALED_SECRETS_UPDATE_STATUS"
          value = "true"
        }
      ]
    })
  ]

  # Ensure ArgoCD is deployed first (sealed secrets will be used by ArgoCD applications)
  depends_on = [helm_release.argocd]
}

# Create a secret to backup the sealed secrets private key
# This is crucial for disaster recovery
resource "kubernetes_secret" "sealed_secrets_key_backup" {
  metadata {
    name      = "sealed-secrets-key-backup"
    namespace = kubernetes_namespace.sealed_secrets.metadata[0].name
    labels = {
      "app.kubernetes.io/name"      = "sealed-secrets"
      "app.kubernetes.io/component" = "key-backup"
    }
    annotations = {
      "description" = "Backup location for sealed secrets private key - CRITICAL for disaster recovery"
    }
  }

  # Note: The actual key will be populated by the controller
  # This creates the secret structure for manual key backup
  type = "Opaque"
  
  depends_on = [helm_release.sealed_secrets]
}

# Output the public certificate for kubeseal CLI usage
data "kubernetes_secret" "sealed_secrets_key" {
  metadata {
    name      = "sealed-secrets-key"
    namespace = kubernetes_namespace.sealed_secrets.metadata[0].name
  }
  
  depends_on = [helm_release.sealed_secrets]
}



# Outputs for reference
output "sealed_secrets_namespace" {
  description = "Namespace where Sealed Secrets controller is deployed"
  value       = kubernetes_namespace.sealed_secrets.metadata[0].name
}

output "sealed_secrets_service" {
  description = "Sealed Secrets controller service information"
  value = {
    name      = "sealed-secrets"
    namespace = kubernetes_namespace.sealed_secrets.metadata[0].name
    port      = 8080
  }
}

output "kubeseal_fetch_cert_command" {
  description = "Command to fetch the public certificate for kubeseal"
  value       = "kubectl get secret -n ${kubernetes_namespace.sealed_secrets.metadata[0].name} sealed-secrets-key -o jsonpath='{.data.tls\\.crt}' | base64 -d > public.pem"
} 