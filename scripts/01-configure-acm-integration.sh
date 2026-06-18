#!/usr/bin/env bash
# 01-configure-acm-integration.sh
#
# Konfiguruje integrację ACM <-> ArgoCD:
#   1. Labeluje klaster testowy jako cel POC
#   2. Tworzy Placement wybierający ten klaster
#   3. Tworzy ManagedClusterSetBinding (wykrywa nazwę clustersetu automatycznie)
#   4. Tworzy GitOpsCluster, który rejestruje klaster w ArgoCD
#
# Uruchom na klastrze ACM Hub, PO 00-install-gitops-operator.sh.
#
# Wymagana zmienna: CLUSTER_NAME (nazwa klastra testowego jak widoczna w ACM)

set -euo pipefail

CLUSTER_NAME="${1:-}"
if [ -z "$CLUSTER_NAME" ]; then
  echo "Użycie: $0 <nazwa-klastra-testowego>"
  echo ""
  echo "Dostępne zaimportowane klastry:"
  oc get managedclusters -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?\(@.type==\"ManagedClusterJoined\"\)].status
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "==> Sprawdzam że klaster $CLUSTER_NAME jest zaimportowany i JOINED..."
oc get managedcluster "$CLUSTER_NAME" || { echo "BŁĄD: klaster $CLUSTER_NAME nie istnieje w ACM"; exit 1; }

echo "==> Labeluję klaster jako cel POC..."
oc label managedcluster "$CLUSTER_NAME" poc-target=true --overwrite

echo "==> Tworzę Placement..."
oc apply -f "$REPO_ROOT/argocd/acm-placement.yaml"

echo "==> Wykrywam nazwę ManagedClusterSet dla klastra $CLUSTER_NAME..."
CLUSTERSET=$(oc get managedcluster "$CLUSTER_NAME" \
  -o jsonpath='{.metadata.labels.cluster\.open-cluster-management\.io/clusterset}')

if [ -z "$CLUSTERSET" ]; then
  echo "BŁĄD: klaster $CLUSTER_NAME nie ma przypisanego ManagedClusterSet."
  echo "Sprawdź ręcznie: oc get managedcluster $CLUSTER_NAME -o yaml | grep clusterset"
  exit 1
fi
echo "    Wykryto clusterset: $CLUSTERSET"

echo "==> Tworzę ManagedClusterSetBinding (clusterset: $CLUSTERSET)..."
sed "s/__CLUSTERSET__/$CLUSTERSET/g" "$REPO_ROOT/argocd/acm-clustersetbinding.template.yaml" | oc apply -f -

echo "==> Tworzę GitOpsCluster (rejestracja klastra w ArgoCD)..."
oc apply -f "$REPO_ROOT/argocd/acm-gitopscluster.yaml"

echo "==> Czekam aż ArgoCD cluster secret się pojawi (do 2 min)..."
for i in $(seq 1 12); do
  COUNT=$(oc get secrets -n openshift-gitops -l apps.open-cluster-management.io/cluster-name --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$COUNT" -gt 0 ]; then
    echo "    Cluster secret znaleziony."
    break
  fi
  echo "    ...czekam ($i/12)"
  sleep 10
done

echo ""
echo "==> WERYFIKACJA:"
echo "    oc get secrets -n openshift-gitops -l apps.open-cluster-management.io/cluster-name"
echo "    argocd cluster list   (wymaga zalogowania: argocd login <route-do-argocd>)"
echo ""
echo "==> Zapamiętaj nazwę ConfigMap wygenerowanego dla Placement - potrzebna w kroku 02:"
oc get configmap -n openshift-gitops | grep -i placement || echo "    (jeszcze się nie wygenerował, sprawdź za chwilę)"
