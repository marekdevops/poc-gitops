# CLAUDE.md — POC namespace-as-code (ACM + ArgoCD)

## Cel projektu
POC dowodzacy ze Git -> ACM -> Platform ArgoCD -> namespace (labels/annotations
+ RBAC per grupa) dziala end-to-end, w sposob audytowalny, PRZED wejsciem na
srodowiska bankowe z realnymi aplikacjami.

## Zakres (swiadomie ograniczony - nie poszerzaj bez pytania)
W zakresie: Namespace + labels + annotations + RBAC (RoleBinding per grupa
OpenShift, symulujaca grupy AD).
POZA zakresem (faza 2, NIE dotykac teraz): Kyverno, ResourceQuota, LimitRange,
NetworkPolicy, ACS, Ansible remediation, prawdziwa integracja AD/LDAP/OIDC.
Jesli zadanie zaczyna dryfowac w te strone - zatrzymaj sie i zapytaj.

## Topologia - KRYTYCZNE, nie pomyl klastrow
- ACM Hub: tu zyje Platform ArgoCD (instancja `openshift-gitops` w namespace
  `openshift-gitops`). Tu odpalamy skrypty 00, 01, 02.
- Klaster testowy (spoke, zaimportowany do ACM jako ManagedCluster): ma JUZ
  swoja instancje ArgoCD uzywana przez dev team ("Application ArgoCD") -
  NIE DOTYKAC, NIE MODYFIKOWAC, nie wchodzi w zakres tego POC. Tu odpalamy
  tylko skrypty 03 i 99.
ZAWSZE sprawdzaj `oc whoami` i `oc cluster-info | head -1` przed odpaleniem
jakiegokolwiek skryptu - latwo pomylic kontekst miedzy hubem a klastrem testowym.

## Struktura repo
- `namespace-factory/` — Helm chart: Namespace (labels/annotations) +
  RoleBinding (dev/ops per grupa)
- `argocd/` — manifesty integracji ACM (Placement, ManagedClusterSetBinding,
  GitOpsCluster) + szablon ApplicationSet
- `scripts/00-04,99-*.sh` — bootstrap w kolejnosci numerycznej, kazdy
  idempotentny (`set -euo pipefail`, sprawdza stan przed dzialaniem).
  `04-trust-gitlab-ca.sh` jest opcjonalny (tylko gdy GitLab ma cert z
  wewnetrznego CA) i odpalany na ACM Hub.
- `README.md` — pelna instrukcja krok po kroku + sekcja troubleshooting,
  TRAKTUJ JAKO PRAWDE - jesli cos jest tam nieaktualne, popraw README,
  nie twórz równoległej dokumentacji

## Znane pulapki (juz odkryte w tej sesji - NIE powtarzaj tych bledow)
1. `configMapRef` w generatorze `clusterDecisionResource` w ApplicationSet
   to STALA nazwa `acm-placement` (generyczny ConfigMap tworzony raz przez
   komponent multicluster-integrations przy tworzeniu GitOpsCluster) -
   NIE nazwa wlasnego obiektu Placement (`poc-placement`). Ktory Placement
   zostaje uzyty wybiera `labelSelector` WEWNATRZ generatora, nie nazwa
   ConfigMap. Zobacz commit `ff238a4` po szczegoly poprawki.
2. RBAC jest per-klaster: grupy stworzone `oc adm groups` na hubie != grupy
   na klastrze testowym. Skrypt 03 MUSI byc odpalony na klastrze testowym,
   nie na hubie.
3. Generator `git` w ApplicationSet: nasz layout to env-jako-PLIK
   (`values/<team>/<env>.yaml`), wiec MUSI byc `git: files` z globem
   `namespace-factory/values/*/*.yaml`, NIE `git: directories`. Generator
   `directories` matchuje tylko katalogi -> z plikami zwraca 0 wynikow i
   ApplicationSet po cichu nie generuje zadnej Application (objaw: brak bledu,
   ale `oc get applications` puste). Dodatkowo `path[0]/path[1]` w szablonie to
   segmenty CALEJ sciezki od korzenia repo (namespace-factory/values), NIE
   team/env - uzywamy `path.basename` (katalog teamu) i `path.filename` (plik
   env), a nazwe Application bierzemy z tresci pliku `{{namespace.name}}` zeby
   uniknac kolizji `poc-ns-dev`. Generator `files` parsuje TRESC pliku values
   jako parametry szablonu, dlatego `{{namespace.name}}` jest dostepny.
4. ArgoCD + firmowy GitLab z wewnetrznym CA: ApplicationSet stworzy sie, ale
   w jego statusie bedzie `x509: certificate signed by unknown authority` i NIE
   wygeneruje Application (repo-server nie sklonuje repo). Fix: zaufaj CA przez
   `04-trust-gitlab-ca.sh` (NIGDY insecure/skip-verify - czerwona flaga
   audytowa). PULAPKA wewnatrz: operator wypelnia ConfigMap argocd-tls-certs-cm
   z `spec.tls.initialCerts` TYLKO przy tworzeniu CM; gdy CM juz istnieje, wpis
   jest ignorowany - dlatego skrypt kasuje CM, by operator odtworzyl go z
   aktualnym initialCerts, i restartuje repo-server. Cert CA NIE jest commitowany
   (wzorzec *-ca.pem/*.crt w .gitignore - moze ujawniac wewnetrzne PKI/hosty).

## Status (aktualizuj te sekcje po kazdej sesji roboczej)
- [x] 00-install-gitops-operator.sh — wykonany na ACM Hub, OK
- [x] 01-configure-acm-integration.sh — wykonany, Placement/CSB/GitOpsCluster
      zaaplikowane
- [ ] 02-deploy-namespace-factory.sh — poprawiony (fix configMapRef),
      WYMAGA ponownej weryfikacji na klastrze
- [ ] 03-create-test-groups.sh — nie odpalony
- [ ] 99-validate-poc.sh — nie odpalony
- [ ] Test provisioningu przez PR (krok 6 w README) — nie wykonany

## Konwencje
- Komentarze i komunikaty w skryptach: po polsku
- Kazdy skrypt bash: `set -euo pipefail`, sprawdza obecny stan przed
  wykonaniem akcji (idempotentnosc), jasne komunikaty bledow z konkretna
  komenda diagnostyczna do odpalenia
- Commit messages: prefix `poc:`/`fix:`, opis PO CO byla zmiana, nie tylko
  CO sie zmienilo - to ma byc material do audytu bankowego
- `syncPolicy.automated.prune: false` w ArgoCD na czas POC - nie zmieniaj
  bez wyraznej decyzji, bo prune na NS moze usunac dane

## Bezpieczenstwo / kontekst bankowy
To jest POC, ale projektowany pod regulowany sektor bankowy. Kazda zmiana
konfiguracji namespace ma przechodzic przez PR, nie przez recznego
`oc apply` z laptopa. Jesli wykonujesz cos recznie do debugowania, powiedz
to wyraznie i zaproponuj odpowiadajaca zmiane w Git.

## Nastepny krok (zacznij tutaj)
1. Sprawdz: `oc get configmap acm-placement -n openshift-gitops -o yaml`
   - oczekiwana zawartosc data: `apiVersion: cluster.open-cluster-management.io/v1beta1`,
     `kind: placementdecisions`
2. Jesli OK, odpal poprawiony `scripts/02-deploy-namespace-factory.sh <git-repo-url>`
3. Kontynuuj od kroku 4 w README.md (grupy testowe, walidacja)
