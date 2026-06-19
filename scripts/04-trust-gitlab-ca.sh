#!/usr/bin/env bash
# 04-trust-gitlab-ca.sh
#
# Dodaje firmowe CA (wewnetrzny urzad certyfikacji) do store zaufania TLS
# Platform ArgoCD na ACM Hub, zeby repo-server mogl czytac z firmowego
# GitLaba po HTTPS BEZ wylaczania weryfikacji TLS i bez bledu:
#   "x509: certificate signed by unknown authority"
#
# WAZNE (audyt/bezpieczenstwo):
#   - NIE wylaczamy weryfikacji TLS (zadnego insecure/skip-verify) - to czerwona
#     flaga w sektorze bankowym. Uczymy ArgoCD ufac firmowemu CA.
#   - Sam plik CA jest specyficzny dla srodowiska i NIE jest commitowany do repo
#     (moze ujawniac wewnetrzne PKI/nazwy hostow). Podajesz go z lokalnego pliku;
#     wzorzec *-ca.pem jest w .gitignore.
#
# Uzycie: ./04-trust-gitlab-ca.sh <gitlab-hostname> <sciezka-do-ca.pem>
# np.:    ./04-trust-gitlab-ca.sh gitlab.bank.pl ./gitlab-ca.pem
#
# Lancuch CA mozesz pobrac np.:
#   openssl s_client -showcerts -connect gitlab.bank.pl:443 \
#     -servername gitlab.bank.pl </dev/null 2>/dev/null \
#     | openssl x509 -out gitlab-ca.pem
#   (zwykle potrzebujesz root/intermediate CA, nie certu liscia serwera)

set -euo pipefail

HOST="${1:-}"
CA_FILE="${2:-}"
if [ -z "$HOST" ] || [ -z "$CA_FILE" ]; then
  echo "Uzycie: $0 <gitlab-hostname> <sciezka-do-ca.pem>"
  exit 1
fi

echo "==> Sprawdzam kontekst klastra (musi byc ACM Hub)..."
oc whoami
oc cluster-info | head -1

if [ ! -f "$CA_FILE" ]; then
  echo "BLAD: plik CA nie istnieje: $CA_FILE"
  exit 1
fi

echo "==> Walidacja pliku CA jako certyfikatu X.509..."
if ! openssl x509 -in "$CA_FILE" -noout -subject &>/dev/null; then
  echo "BLAD: $CA_FILE nie jest poprawnym certyfikatem PEM X.509."
  echo "Pobierz lancuch CA np.:"
  echo "  openssl s_client -showcerts -connect $HOST:443 -servername $HOST </dev/null"
  exit 1
fi
echo "    OK: $(openssl x509 -in "$CA_FILE" -noout -subject)"

echo "==> Sprawdzam czy instancja ArgoCD openshift-gitops istnieje..."
if ! oc get argocd openshift-gitops -n openshift-gitops &>/dev/null; then
  echo "BLAD: brak instancji ArgoCD openshift-gitops."
  echo "Najpierw uruchom 00-install-gitops-operator.sh na ACM Hub."
  exit 1
fi

# Zrodlo prawdy: wpisujemy CA do spec.tls.initialCerts CR-a ArgoCD.
# Patch budujemy jako plik YAML (cert jest wieloliniowy - bezpieczniej niz -p).
echo "==> Wpisuje CA do spec.tls.initialCerts CR-a ArgoCD (host: $HOST)..."
PATCH_FILE="$(mktemp)"
trap 'rm -f "$PATCH_FILE"' EXIT
{
  echo "spec:"
  echo "  tls:"
  echo "    initialCerts:"
  echo "      $HOST: |"
  sed 's/^/        /' "$CA_FILE"
} > "$PATCH_FILE"
oc patch argocd openshift-gitops -n openshift-gitops --type merge --patch-file "$PATCH_FILE"

# PULAPKA: operator wypelnia ConfigMap argocd-tls-certs-cm z initialCerts TYLKO
# przy jego tworzeniu. Jesli CM juz istnieje (instalacja domyslna tworzy go pusty),
# nasz wpis zostanie zignorowany. Dlatego kasujemy CM - operator odtworzy go
# z aktualnym initialCerts. To bezpieczne: CM trzyma wylacznie certy CA repo.
echo "==> Odswiezam ConfigMap argocd-tls-certs-cm (kasuje -> operator odtworzy)..."
oc delete configmap argocd-tls-certs-cm -n openshift-gitops --ignore-not-found

echo "    Czekam az operator odtworzy CM z wpisem dla $HOST (do 60s)..."
FOUND=0
for i in $(seq 1 12); do
  if oc get configmap argocd-tls-certs-cm -n openshift-gitops -o yaml 2>/dev/null \
       | grep -q "$HOST"; then
    echo "    OK: CA dla $HOST jest w argocd-tls-certs-cm."
    FOUND=1
    break
  fi
  echo "    ...czekam ($i/12)"
  sleep 5
done
if [ "$FOUND" -eq 0 ]; then
  echo "UWAGA: nie potwierdzilem wpisu dla $HOST w argocd-tls-certs-cm."
  echo "Sprawdz recznie:"
  echo "  oc get configmap argocd-tls-certs-cm -n openshift-gitops -o yaml"
  echo "  oc get argocd openshift-gitops -n openshift-gitops -o jsonpath='{.spec.tls.initialCerts}'"
fi

echo "==> Restartuje repo-server, zeby przeladowal trust store..."
oc rollout restart deployment/openshift-gitops-repo-server -n openshift-gitops
oc rollout status deployment/openshift-gitops-repo-server -n openshift-gitops --timeout=120s

echo ""
echo "==> GOTOWE. Zweryfikuj ze ArgoCD czyta juz repo (blad x509 powinien zniknac):"
echo "    oc get applicationset poc-namespace-factory -n openshift-gitops -o yaml | grep -A5 -i status"
echo "    oc get applications -n openshift-gitops"
