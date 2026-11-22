---
status: done
owner: coder-data
---

# Spec 02 — Nezabezpečený deployment + demonstrace rizika

## Rozsah
Záměrně chybně nakonfigurovaný deployment a demo skripty, které ukážou, co
chybná konfigurace útočníkovi umožní. **Vše na vlastní laboratorní VM**, žádný
reálný malware/těžba — jen neškodné simulace (busy loop, čtení vlastního
`/etc/shadow`, výpis vlastních secrets). Manifesty do `k8s/manifests/insecure/`,
skripty do `k8s/scripts/`.

## Manifesty (k8s/manifests/insecure/)
- `01-workload.yaml` — Deployment `vulnapp` v `insecure-demo`: image `:latest`,
  `securityContext` privileged + runAsUser 0, `hostPath` mount `/` hostitele,
  bez resource limits, bez readinessProbe. Jedna služba.
- `02-rbac-overprivileged.yaml` — ServiceAccount `app-sa` + ClusterRoleBinding na
  `cluster-admin`, pod používá tento SA s automountovaným tokenem.
- `03-secret-plaintext.yaml` — Secret `app-secrets` (např. fake DB heslo/API klíč)
  předaný do podu jako **ENV proměnné**.

## Demo skripty (k8s/scripts/) — každý má insecure část; obrana je ve spec 03
- `01-rbac-escalation.sh` — z podu `vulnapp` přes token SA a API server vylistuje
  secrets napříč namespaces a vytvoří další pod → ukázka příliš širokého RBAC.
- `02-secret-exposure.sh` — ukáže secret v `kubectl describe pod` / `env` /
  (bez šifrování) čitelný v datastore; vysvětlí, proč ENV = únik.
- `03-no-netpol-lateral.sh` — dva pody ve dvou namespacech; bez NetworkPolicy se
  navzájem pingnou/curlnou + ukáže volný egress ven → prostor pro laterální pohyb a C2.
- `04-no-limits-dos.sh` — spustí pod s **neškodným busy-loop** (`while true; do :; done`
  nebo `yes > /dev/null`) bez limitů; `kubectl top` ukáže zabrané CPU nodu (DoS efekt).
- `09-host-docker-api.sh` — **klíčová návaznost na TeamTNT z projektu A**:
  ukáže, že když je na Docker nodu (VM2) vystavené Docker API na TCP 2375,
  lze přes `curl`/`docker -H tcp://<node>:2375` spustit kontejner s přístupem k FS
  hostitele a přečíst jeho `/etc/shadow` — a že tento kontejner **Kubernetes vůbec
  nevidí** (`kubectl get pods -A` ho neukáže). Pointa: RBAC/PSA tento vektor neřeší.
  Skript musí nejdřív bezpečně detekovat, zda je API otevřené, a jinak to jen nasimulovat/vysvětlit.

## Verify
- [ ] Manifesty se aplikují do `insecure-demo` a pod naběhne (je záměrně „funkční ale děravý").
- [ ] Skripty demonstrují dopad měřitelně (výpis secret, úspěšný cross-ns curl, CPU v `top`).
- [ ] `09-host-docker-api.sh` jasně odděluje: (a) co umožní vystavené Docker API,
      (b) že Kubernetes o tom neví — a odkazuje na obranu ve spec 03 (AC17).
- [ ] Žádná reálná těžba ani škodlivý payload; jen vlastní VM.
- [ ] Narace vysvětluje, které AC/téma zadání krok pokrývá.
