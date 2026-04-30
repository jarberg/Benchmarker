# Bootstrap ArgoCD into the cluster. After this applies, ArgoCD will pick
# up argocd/app-of-apps.yaml and the rest of the deployment becomes GitOps.
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.12"

  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      server = {
        service = { type = "ClusterIP" }
      }
    })
  ]

  depends_on = [module.eks]
}

resource "kubernetes_manifest" "argocd_project" {
  manifest = yamldecode(file("${path.module}/../argocd/project.yaml"))
  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_root_app" {
  manifest = yamldecode(file("${path.module}/../argocd/app-of-apps.yaml"))
  depends_on = [kubernetes_manifest.argocd_project]
}
