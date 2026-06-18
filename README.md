# POC: namespace-as-code (ACM + ArgoCD)

Cel POC: dowiesc ze Git -> ACM -> Platform ArgoCD -> namespace (z labelami,
annotacjami i RBAC per grupa) dziala end-to-end, w sposob audytowalny.

Poza zakresem tego POC (swiadomie): Kyverno, ResourceQuota, NetworkPolicy,
ACS, prawdziwa integracja AD/LDAP. To faza 2.

## Wymagania wstepne

- Dostep `oc login` do klastra ACM Hub
- Dostep `oc login` do klastra testowego, ktory jest juz zaimportowany
  do ACM jako ManagedCluster (status JOINED)
- `argocd` CLI (opcjonalnie, do weryfikacji `argocd cluster list`)
- To repo wypchniete (`git push`) do Twojego wewnetrznego Gita - ArgoCD
  musi miec do niego siecio dostep z klastra ACM Hub

## Sekwencja krokow

### 0. Wypchnij to repo do wewnetrznego Gita

```bash
cd poc-gitops
git remote add origin <URL-twojego-wewnetrznego-repo>
git push -u origin main
```

### 1. Zainstaluj Platform ArgoCD na ACM Hub

```bash
oc login <acm-hub-cluster>
./scripts/00-install-gitops-operator.sh
```

### 2. Skonfiguruj integracje ACM <-> ArgoCD

Pozostajac zalogowanym na ACM Hub:

```bash
./scripts/01-configure-acm-integration.sh <nazwa-klastra-testowego-w-acm>
```

Skrypt sam wykryje ManagedClusterSet i poda nazwe wygenerowanego ConfigMap
dla Placement - zanotuj nazwe klastra testowego, jak widoczna jest w ACM:

```bash
oc get managedclusters
```

### 3. Wdroz namespace factory (ApplicationSet)

Wciaz na ACM Hub:

```bash
./scripts/02-deploy-namespace-factory.sh https://git.twojafirma.pl/poc-gitops.git
```

### 4. Stworz grupy testowe na klastrze TESTOWYM

Przelogowanie na klaster testowy (nie hub):

```bash
oc login <klaster-testowy>
./scripts/03-create-test-groups.sh <twoj-username>
```

### 5. Sprawdz ze namespace powstal

Poczekaj ~2-3 min po kroku 3, potem na klastrze testowym:

```bash
oc get ns poc-team-alpha-dev --show-labels
oc get rolebindings -n poc-team-alpha-dev
```

### 6. Test provisioningu przez PR (najwazniejszy dowod)

```bash
git checkout -b poc/add-namespace-beta
# stworz nowy plik values, np. namespace-factory/values/poc-team-beta/dev.yaml
git add .
git commit -m "poc: add namespace poc-team-beta-dev"
git push origin poc/add-namespace-beta
# zrob PR -> merge do main w Twoim Gicie
```

Po ~3 min od merge, na klastrze testowym:

```bash
oc get ns poc-team-beta-dev --show-labels
```

### 7. Walidacja automatyczna

Na klastrze testowym:

```bash
./scripts/99-validate-poc.sh
```

### 8. RBAC test reczny

```bash
oc login --as <twoj-username>
oc auth can-i create deployments -n poc-team-alpha-dev   # powinno: yes
oc auth can-i create rolebindings -n poc-team-alpha-dev  # powinno: no
```

### 9. Audit trail (do prezentacji)

```bash
git log --oneline namespace-factory/values/poc-team-alpha/dev.yaml
```

## Troubleshooting

- `argocd cluster list` nie widzi klastra testowego -> sprawdz
  `oc get secrets -n openshift-gitops -l apps.open-cluster-management.io/cluster-name`
  na hubie. Brak secreta = GitOpsCluster/Placement/ClusterSetBinding
  nie skonfigurowane poprawnie - wroc do kroku 2.

- ApplicationSet nie generuje Application -> sprawdz
  `oc get applicationset poc-namespace-factory -n openshift-gitops -o yaml`
  pod katem bledow w sekcji status. Czesty problem: zly URL repo lub
  repo niedostepne siecio z klastra ACM Hub.

- Namespace nie ma RoleBinding -> sprawdz czy grupy z kroku 4 istnieja
  na WLASCIWYM klastrze (testowym, nie hub) - RBAC jest per-klaster.
