#!/usr/bin/env bash
# 99-validate-poc.sh
#
# Przegania scenariusze walidacyjne POC i wypisuje wynik gotowy do
# wklejenia w prezentacji. Uruchom na KLASTRZE TESTOWYM po tym jak
# namespace poc-team-alpha-dev zostal juz utworzony przez ArgoCD.
#
# Test 1 (provisioning przez PR) NIE jest tu zawarty - to wymaga
# realnego PR/merge w Twoim Gicie, zobacz README.md krok 6.

set -euo pipefail

NS="poc-team-alpha-dev"
DEV_GROUP="poc-team-alpha-dev"

echo "================================================================"
echo " POC namespace-as-code - walidacja"
echo "================================================================"

echo ""
echo "--- Test: namespace istnieje z poprawnymi labelami ---"
if oc get ns "$NS" &>/dev/null; then
  echo "OK: namespace $NS istnieje"
  oc get ns "$NS" --show-labels
else
  echo "BLAD: namespace $NS nie istnieje. Sprawdz ArgoCD: oc get applications -n openshift-gitops"
  exit 1
fi

echo ""
echo "--- Test: RBAC per grupa ---"
echo "Sprawdzam jakie RoleBinding sa przypisane do $NS:"
oc get rolebindings -n "$NS" -o custom-columns=NAME:.metadata.name,SUBJECT:.subjects[0].name,ROLE:.roleRef.name

echo ""
echo "--- Test: drift detection (selfHeal) ---"
ORIGINAL_TEAM=$(oc get ns "$NS" -o jsonpath='{.metadata.labels.team}')
echo "Wartosc oryginalna labela 'team': $ORIGINAL_TEAM"
echo "Wprowadzam reczna zmiane (symulacja driftu)..."
oc label ns "$NS" team=DRIFT-TEST --overwrite
echo "Czekam 60s na selfHeal..."
sleep 60
CURRENT_TEAM=$(oc get ns "$NS" -o jsonpath='{.metadata.labels.team}')
if [ "$CURRENT_TEAM" == "$ORIGINAL_TEAM" ]; then
  echo "OK: ArgoCD przywrocil wartosc '$ORIGINAL_TEAM' - selfHeal dziala"
else
  echo "UWAGA: aktualna wartosc to '$CURRENT_TEAM', oczekiwano '$ORIGINAL_TEAM'"
  echo "       sprawdz czy syncPolicy.automated.selfHeal: true jest ustawione"
fi

echo ""
echo "--- Test: ArgoCD widzi namespace jako Synced ---"
oc get applications -n openshift-gitops -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status | grep -i "$NS" || echo "Nie znaleziono Application dla $NS w ArgoCD"

echo ""
echo "================================================================"
echo " Walidacja zakonczona. Pozostale testy do wykonania recznie:"
echo " - Test provisioning przez PR: zobacz README.md"
echo " - Test 'oc auth can-i' jako user z grupy $DEV_GROUP"
echo " - Audit trail: git log namespace-factory/values/poc-team-alpha/dev.yaml"
echo " - ACM Console -> Search -> namespace:$NS"
echo "================================================================"
