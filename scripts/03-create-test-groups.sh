#!/usr/bin/env bash
# 03-create-test-groups.sh
#
# Tworzy grupy OpenShift symulujące grupy AD (POC nie wymaga jeszcze
# integracji LDAP/OIDC - mechanika RBAC jest identyczna).
#
# Uruchom na KLASTRZE TESTOWYM (nie na hubie ACM).
#
# Użycie: ./03-create-test-groups.sh <twoj-username>

set -euo pipefail

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
  echo "Użycie: $0 <twoj-username>"
  exit 1
fi

DEV_GROUP="poc-team-alpha-dev"
OPS_GROUP="poc-team-alpha-ops"

echo "==> Sprawdzam kontekst klastra (powinien to być klaster TESTOWY, nie hub)..."
oc whoami
oc cluster-info | head -1

for GROUP in "$DEV_GROUP" "$OPS_GROUP"; do
  if oc get group "$GROUP" &>/dev/null; then
    echo "==> Grupa $GROUP już istnieje - pomijam."
  else
    echo "==> Tworzę grupę $GROUP..."
    oc adm groups new "$GROUP"
  fi
done

echo "==> Dodaję $USERNAME do grupy $DEV_GROUP..."
oc adm groups add-users "$DEV_GROUP" "$USERNAME"

echo ""
echo "==> GOTOWE. Weryfikacja:"
oc get group "$DEV_GROUP" -o yaml | grep -A5 users
