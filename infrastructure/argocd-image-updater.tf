# ArgoCD Image Updater installation
resource "helm_release" "argocd_image_updater" {
  name       = "argocd-image-updater"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  namespace  = "argocd"
  version    = "0.12.3"

  values = [
    yamlencode({
      config = {
        # Registry configuration for GHCR (public registry - no credentials needed)
        registries = [
          {
            name = "ghcr"
            api_url = "https://ghcr.io"
            prefix = "ghcr.io"
            # credentials not needed for public GHCR repositories
          }
        ]
      }
      
      # RBAC permissions
      serviceAccount = {
        create = true
        annotations = {}
      }
      
      # Resource limits
      resources = {
        limits = {
          cpu = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu = "50m"
          memory = "64Mi"
        }
      }
      
      # Update interval (check every 2 minutes)
      config = {
        interval = "2m"
        log_level = "info"
      }
    })
  ]

  depends_on = [helm_release.argocd]
} 