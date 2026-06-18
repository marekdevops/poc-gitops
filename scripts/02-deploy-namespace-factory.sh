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

echo "==> Wykrywam nazwę ConfigMap wygenerowanego przez ACM dla Placement..."
PLACEMENT_CM=$(oc get configmap -n openshift-gitops -o name | grep -i poc-placement | sed 's#configmap/##' || true)

if [ -z "$PLACEMENT_CM" ]; then
  echo "BŁĄD: nie znalazłem ConfigMap dla poc-placement."
  echo "Sprawdź ręcznie: oc get configmap -n openshift-gitops"
  echo "Czy wykonałeś już 01-configure-acm-integration.sh?"
  exit 1
fi
echo "    Znaleziono: $PLACEMENT_CM"

echo "==> Renderuję ApplicationSet z GIT_REPO_URL=$GIT_REPO_URL ..."
sed -e "s#__GIT_REPO_URL__#$GIT_REPO_URL#g" \
    -e "s#__PLACEMENT_CONFIGMAP__#$PLACEMENT_CM#g" \
    "$REPO_ROOT/argocd/namespace-factory-appset.template.yaml" | oc apply -f -

echo ""
echo "==> GOTOWE. Sprawdź status:"
echo "    oc get applicationset -n openshift-gitops"
echo "    oc get applications -n openshift-gitops"
