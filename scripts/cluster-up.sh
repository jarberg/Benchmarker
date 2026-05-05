#!/bin/bash
# scripts/cluster-up.sh
# Run this from inside the tools container to (re)build the local Kind cluster.
# Usage: bash scripts/cluster-up.sh
set -euo pipefail

CLUSTER_NAME=benchmarker
REGISTRY_CONTAINER=benchmarker-registry-1
POSTGRES_CONTAINER=benchmarker-postgres-1

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║       Benchmarker local cluster setup    ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── 1. Tear down existing cluster ────────────────────────────────────────────
echo "▶ Deleting existing Kind cluster (if any)..."
kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true

# ── 2. Create Kind cluster with containerd registry config baked in ───────────
echo "▶ Creating Kind cluster..."
kind create cluster --name "$CLUSTER_NAME" --config=- <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
  - |-
    [plugins."io.containerd.grpc.v1.cri".registry]
      config_path = "/etc/containerd/certs.d"
EOF

# ── 3. Connect containers to the kind network ────────────────────────────────
echo "▶ Connecting registry to kind network..."
docker network connect --alias registry kind "$REGISTRY_CONTAINER" 2>/dev/null || echo "  (already connected)"

echo "▶ Connecting postgres to kind network..."
docker network connect kind "$POSTGRES_CONTAINER" 2>/dev/null || echo "  (already connected)"

echo "▶ Connecting tools container to kind network..."
TOOLS_CONTAINER=$(hostname)
docker network connect kind "$TOOLS_CONTAINER" 2>/dev/null || echo "  (already connected)"
echo "  Waiting for network interface to come up..."
sleep 2

# ── 4. Configure containerd on each Kind node to use local HTTP registry ──────
echo "▶ Configuring containerd on Kind nodes..."
HOSTS_TOML='server = "http://registry:5000"

[host."http://registry:5000"]
  capabilities = ["pull", "resolve"]
  skip_verify = true'

for node in $(kind get nodes --name "$CLUSTER_NAME"); do
  echo "  → $node"
  docker exec "$node" mkdir -p /etc/containerd/certs.d/registry:5000
  echo "$HOSTS_TOML" | docker exec -i "$node" tee /etc/containerd/certs.d/registry:5000/hosts.toml > /dev/null
  docker exec "$node" kill -SIGHUP "$(docker exec "$node" pidof containerd)"
done
echo "  Waiting for containerd to reload..."
sleep 3

# ── 5. Fix kubeconfig to use Kind node's internal IP (not 127.0.0.1) ─────────
echo "▶ Updating kubeconfig server address..."
NODE_IP=$(docker inspect "${CLUSTER_NAME}-control-plane" \
  --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
kubectl config set-cluster "kind-${CLUSTER_NAME}" --server="https://${NODE_IP}:6443"
echo "  Control-plane IP: ${NODE_IP}"

# ── 6. Install ArgoCD ─────────────────────────────────────────────────────────
echo "▶ Installing ArgoCD..."
kubectl create namespace argocd 2>/dev/null || true
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --wait \
  --timeout 5m

# ── 7. Create app namespace and postgres bridge service ───────────────────────
echo "▶ Creating benchmarker namespace..."
kubectl create namespace benchmarker 2>/dev/null || true

echo "▶ Applying postgres Service + Endpoints..."
POSTGRES_IP=$(docker inspect "$POSTGRES_CONTAINER" \
  --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
echo "  Postgres IP on kind network: ${POSTGRES_IP}"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: benchmarker
spec:
  ports:
    - port: 5432
      targetPort: 5432
---
apiVersion: v1
kind: Endpoints
metadata:
  name: postgres
  namespace: benchmarker
subsets:
  - addresses:
      - ip: ${POSTGRES_IP}
    ports:
      - port: 5432
EOF

# ── 8. Apply ArgoCD app-of-apps ───────────────────────────────────────────────
echo "▶ Applying ArgoCD app-of-apps..."
kubectl apply -f argocd/app-of-apps.yaml

echo ""
echo "✓ Done! ArgoCD will sync the app shortly."
echo ""
echo "  Watch pods:       kubectl get pods -n benchmarker -w"
echo "  Watch ArgoCD:     kubectl get app -n argocd -w"
echo "  ArgoCD UI port-forward:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
