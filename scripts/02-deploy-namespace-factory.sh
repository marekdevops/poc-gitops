#!/usr/bin/env bash
# 02-deploy-namespace-factory.sh
#
# Renderuje i aplikuje ApplicationSet, który spowoduje że Platform ArgoCD
# zacznie zarządzać namespace'ami zdefiniowanymi w katalogu
# namespace-factory/values/ tego repo.
#
# WYMAGANE: repo musi być już wypchnięte (git push) do Twojego wewnętrznego
# Gita, zanim ArgoCD będzie mógł je odczytać.
#
# Użycie: ./02-deploy-namespace-factory.sh <git-repo-url>
# np.:    ./02-deploy-namespace-factory.sh https://git.bank.pl/platform/poc-gitops.git

set -euo pipefail

GIT_REPO_URL="${1:-}"
if [ -z "$GIT_REPO_URL" ]; then
  echo "Użycie: $0 <git-repo-url>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# acm-placement to STAŁY, generyczny ConfigMap tworzony jednorazowo przez
# multicluster-integrations (komponent obslugujacy GitOpsCluster) -
# NIE jest tworzony per-Placement i NIE zawiera w nazwie "poc-placement".
# To konfiguracja generatora "clusterDecisionResource" dla ArgoCD, ktora
# mowi mu jak czytac obiekty Placement/PlacementDecision z OCM/ACM.
# Ktory konkretny Placement zostanie uzyty - to wybiera labelSelector
# WEWNATRZ generatora w ApplicationSet (cluster.open-cluster-management.io/placement: poc-placement),
# nie nazwa tego ConfigMap.
PLACEMENT_CM="acm-placement"

echo "==> Sprawdzam czy ConfigMap $PLACEMENT_CM istnieje w openshift-gitops..."
if ! oc get configmap "$PLACEMENT_CM" -n openshift-gitops &>/dev/null; then
  echo "BŁĄD: ConfigMap $PLACEMENT_CM nie istnieje w namespace openshift-gitops."
  echo "Sprawdź czy operator multicluster-integrations / GitOpsCluster jest"
  echo "poprawnie zainstalowany na klastrze ACM Hub:"
  echo "  oc get configmap -n openshift-gitops"
  echo "  oc get pods -n openshift-gitops | grep -i integration"
  exit 1
fi
echo "    OK: $PLACEMENT_CM istnieje."

echo "==> Sprawdzam zawartość ConfigMap (oczekiwane: apiVersion/kind dla Placement)..."
oc get configmap "$PLACEMENT_CM" -n openshift-gitops -o yaml | grep -A2 '^data:'

echo "==> Sprawdzam czy mój Placement (poc-placement) istnieje..."
if ! oc get placement poc-placement -n openshift-gitops &>/dev/null; then
  echo "BŁĄD: Placement poc-placement nie istnieje. Czy wykonałeś 01-configure-acm-integration.sh?"
  exit 1
fi
echo "    OK: Placement poc-placement istnieje."

echo "==> Sprawdzam czy PlacementDecision został wygenerowany dla poc-placement..."
DECISION_COUNT=$(oc get placementdecisions -n openshift-gitops -l cluster.open-cluster-management.io/placement=poc-placement --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$DECISION_COUNT" -eq 0 ]; then
  echo "UWAGA: brak PlacementDecision dla poc-placement. ApplicationSet nie wygeneruje"
  echo "       żadnej Application dopóki to się nie pojawi. Sprawdź:"
  echo "       - czy klaster testowy ma label poc-target=true"
  echo "       - oc describe placement poc-placement -n openshift-gitops"
else
  echo "    OK: znaleziono $DECISION_COUNT PlacementDecision."
fi

echo "==> Renderuję ApplicationSet z GIT_REPO_URL=$GIT_REPO_URL ..."
sed -e "s#__GIT_REPO_URL__#$GIT_REPO_URL#g" \
    "$REPO_ROOT/argocd/namespace-factory-appset.template.yaml" | oc apply -f -

echo ""
echo "==> GOTOWE. Sprawdź status:"
echo "    oc get applicationset poc-namespace-factory -n openshift-gitops -o yaml"
echo "    oc get applications -n openshift-gitops"
