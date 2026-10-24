# Požadavky — Zadání č. 6 A: Bezpečnost kontejnerizace

## Cíl
Prakticky demonstrovat rozdíl mezi nezabezpečeným (root / privileged) kontejnerem
a bezpečně nastaveným (hardened) kontejnerem, včetně reálného využití chybné
konfigurace ke čtení hostitelského `/etc/shadow`. Dále provést analýzu několika
image nástroji Trivy a Docker Scout a navrhnout jejich zabezpečení.

Celé se předvádí na izolovaném testovacím VM (ne na produkci).

## Akceptační kritéria (AC)

### Demonstrace escape / eskalace
- [ ] AC1: Skript ukáže, jak z `--privileged` kontejneru připojit disk hostitele a přečíst `/etc/shadow`.
- [ ] AC2: Skript ukáže eskalaci přes namountovaný `/var/run/docker.sock`.
- [ ] AC3: Skript ukáže naivní bind-mount `-v /:/host` jako nejrychlejší únik dat.
- [ ] AC4: Zvolena jedna starší, dnes už neaktuální zranitelnost (CVE-2019-5736 runc / Shellshock) jako ilustrace řetězení "RCE v appce → escape".

### Srovnávací scénáře (least privilege)
- [ ] AC5: root vs non-root (`USER 10001`, mapování UID).
- [ ] AC6: Linux capabilities (`--cap-drop=ALL`, přidání jen `NET_BIND_SERVICE`).
- [ ] AC7: privileged vs. default vs. hardened.
- [ ] AC8: read-only filesystem (`--read-only` + `tmpfs` pro zápis).
- [ ] AC9: secrets (ukázka, proč ne v ENV/image, použití `--secret` / souborů).
- [ ] AC10: volumes (nebezpečné bind-mounty vs. pojmenované volumes, `:ro`).
- [ ] AC11: síťová izolace (vlastní user-defined network, `--network none`).
- [ ] AC12: omezení zdrojů (`--memory`, `--cpus`, `--pids-limit`).

### Vulnerability scanning
- [ ] AC13: Trivy sken několika image (záměrně staré + aktuální) s uložením výstupu.
- [ ] AC14: Docker Scout sken (vyžaduje přihlášení účtem — `docker login`).
- [ ] AC15: Návrh zabezpečení na základě nálezů (přechod na slim/distroless, pinování verzí, aktualizace).

### Výstupy
- [ ] AC16: Tabulka nejčastějších zranitelností ↔ Docker nastavení, které jim brání.
- [ ] AC17: HTML prezentace pokrývající všechna témata ze zadání.
- [ ] AC18: Skripty ve složce `scripts/` spustitelné na VM.

## Mimo rozsah
- Žádné útoky na cizí/cizí infrastrukturu — vše jen na vlastním VM.
- Žádný reálný malware; "exploit" je čtení `/etc/shadow` z vlastního hostitele jako důkaz dopadu.
