resource "helm_release" "longhorn" {
  depends_on       = [rke_cluster.cluster]
  count            = var.longhorn_enabled ? 1 : 0
  name             = "longhorn"
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  namespace        = "longhorn"
  create_namespace = true

  set {
    name  = "persistence.defaultClass"
    value = "false"
  }
}

resource "helm_release" "vault" {
  depends_on       = [helm_release.longhorn]
  count            = var.vault_enabled ? 1 : 0
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.10.0"
  namespace        = "vault"
  create_namespace = true
  values = [
    file("helm-values/vault.yaml")
  ]

  set {
    name  = "server.ha.enabled"
    value = "false"
  }
}

resource "helm_release" "nginx" {
  depends_on = [rke_cluster.cluster]
  name       = "nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "3.10.1"

  namespace        = "nginx"
  create_namespace = true

  values = [
    file("helm-values/nginx-ingress.yaml")
  ]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  // Depends on Nginx Ingress for ArgoCD Web UI
  depends_on = [helm_release.nginx, kubernetes_namespace.argocd]

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version    = "3.6.4"

  values = [
    file("helm-values/argocd.yaml")
  ]
}

resource "kubernetes_config_map" "default_metallb_config" {
  depends_on = [rke_cluster.cluster]

  metadata {
    name      = "config"
    namespace = "metallb-system"
  }

  data = {
    config = <<EOF
        address-pools:
        - name: default-pool
          protocol: layer2
          addresses:
          - 192.168.1.100-192.168.1.200
        EOF
  }
}

resource "kubernetes_ingress" "dev_ingresses" {
  depends_on = [rke_cluster.cluster]

  for_each = var.dev_sub_domains

  metadata {
    name        = "${each.value["subdomain"]}-ingress"
    namespace   = each.value["namespace"]
    annotations = each.value["annotations"]
  }

  spec {
    rule {
      host = "${each.value["subdomain"]}.${var.dev_domain}"
      http {
        path {
          backend {
            service_name = each.value["service_name"]
            service_port = each.value["service_port"]
          }
        }
      }
    }
  }
}

