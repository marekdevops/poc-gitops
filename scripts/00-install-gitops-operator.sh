#!/usr/bin/env bash
# 00-install-gitops-operator.sh
#
# Instaluje OpenShift GitOps Operator na klastrze ACM Hub.
# Uruchom będąc zalogowanym (oc login) na klaster ACM Hub.
#
# Po instalacji domyślna instancja ArgoCD "openshift-gitops" w namespace
# "openshift-gitops" staje się naszym Platform ArgoCD.

set -euo pipefail

echo "==> Sprawdzam kontekst klastra..."
oc whoami
oc cluster-info | head -1

echo "==> Sprawdzam czy operator GitOps jest już zainstalowany..."
if oc get csv -n openshift-operators 2>/dev/null | grep -q gitops; then
  echo "    Operator GitOps już zainstalowany - pomijam instalację."
else
  echo "==> Instaluję OpenShift GitOps Operator..."
  cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

  echo "==> Czekam aż operator wstanie (do 5 min)..."
  for i in $(seq 1 30); do
    if oc get csv -n openshift-operators 2>/dev/null | grep -q "gitops.*Succeeded"; then
      echo "    Operator gotowy."
      break
    fi
    echo "    ...czekam ($i/30)"
    sleep 10
  done
fi

echo "==> Czekam aż domyślna instancja ArgoCD będzie dostępna..."
for i in $(seq 1 30); do
  if oc get argocd openshift-gitops -n openshift-gitops &>/dev/null; then
    echo "    Instancja openshift-gitops istnieje."
    break
  fi
  echo "    ...czekam ($i/30)"
  sleep 10
done

echo "==> Aplikuję RBAC patch (tylko platform-team ma dostęp)..."
oc apply -f "$(dirname "$0")/../argocd/argocd-rbac-patch.yaml"

echo ""
echo "==> GOTOWE. Hasło admina (POC only - w prod SSO przez OAuth):"
echo "    oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-"
echo ""
echo "==> Route do UI:"
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='https://{.spec.host}{"\n"}' 2>/dev/null || echo "    (route jeszcze nie gotowa, sprawdź za chwilę: oc get route -n openshift-gitops)"
