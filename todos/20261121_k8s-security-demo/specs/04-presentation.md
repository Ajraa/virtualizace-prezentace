---
status: done
owner: coder-ui
---

# Spec 04 — HTML prezentace B

## Rozsah
Jeden samostatný soubor `prezentace-b.html` v kořeni repozitáře (vedle
`prezentace.html`). Offline, žádné nutné externí CDN. **Převzít vizuální styl,
CSS proměnné, navigaci a strukturu z `prezentace.html`** (stejný design systém:
tmavé téma, karty bad/good, pill/badge, `pre` bloky, footer s navigací šipkami/
mezerníkem/F, progress bar). Odznaky skriptů `<span class="badge">skript NN</span>`
odkazují na skripty z `k8s/scripts/`.

## Obsah (v češtině)
1. **Úvod / návaznost** — přímo naváže na závěr A: „V A jsme viděli TeamTNT —
   útok nešel přes aplikaci, ale přes vystavený control-plane (Docker API).
   U Kubernetes platí totéž na dvou vrstvách." Zadání č. 6 B.
2. **Topologie laboratoře** — 2 VM: k3s-server (VM1) + Docker node (VM2 z projektu A)
   jako k3s agent s Docker runtime. Diagram/flow.
3. **Proč k3s** — lehký, ale bezpečnostní modely identické s plným K8s.
4. **Mapa útočné plochy Kubernetes** — control-plane (API, kubelet, etcd/datastore),
   workload (pody, SA tokeny), node/runtime (Docker). TeamTNT/Hildegard jako reálné kampaně.
5–11. **Témata zadání**, u každého karta NEBEZPEČNÉ vs. HARDENED + odznak skriptu:
   - RBAC & ServiceAccount (cluster-admin + automount vs. minimální Role, `automountServiceAccountToken: false`) — skript 01/05
   - Secrets (ENV + nešifrovaný datastore vs. soubor v `/run/secrets` + `--secrets-encryption`) — skript 02/06
   - NetworkPolicy (plochá síť / laterální pohyb vs. default-deny + cílené povolení) — skript 03/07
   - Pod Security (privileged/root/hostPath vs. PSA `restricted`) — skript 08
   - Image security (`:latest` vs. digest pin + Trivy image/config sken) — skript 12
   - Resource limits (bez limitů → DoS vs. requests/limits + LimitRange/ResourceQuota) — skript 04/12
   - **Host / Docker runtime** (vystavené Docker API 2375 → převzetí nodu mimo K8s
     vs. zavřené API/mTLS + userns-remap + firewall) — skript 09/10. Zvýraznit jako
     pointu návaznosti na A.
6. **Tabulka** chybná konfigurace ↔ dopad ↔ Kubernetes/host nastavení, které brání.
7. **Závěrečná bezpečnostní analýza** — slide „Jaké riziko představuje nesprávná
   konfigurace Kubernetes?" (explicitní výstup zadání): shrnutí rizik, princip
   defense-in-depth přes obě vrstvy, least privilege, že K8s hardening sám nestačí
   bez hardeningu hostitele.

## Verify
- [ ] Soubor se otevře offline, navigace (šipky/mezerník/F) funguje jako v A.
- [ ] Vizuální styl konzistentní s `prezentace.html` (stejné CSS proměnné/komponenty).
- [ ] Pokryta VŠECHNA témata ze zadání B (RBAC, SA, Secrets, NetworkPolicy, Pod Security, image security, resource limits).
- [ ] Explicitní slide s bezpečnostní analýzou „Jaké riziko…".
- [ ] Jasná návaznost na TeamTNT slide z A + host-level obrana.
- [ ] Odznaky skriptů odpovídají reálným názvům v `k8s/scripts/`.
