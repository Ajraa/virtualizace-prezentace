# Výzkum — Bezpečnost kontejnerizace

## 1. Proč jsou kontejnery jiné než VM

Kontejner **není bezpečnostní hranice jako VM**. Všechny kontejnery sdílejí
jádro hostitele. Izolaci dělají jen jaderné mechanismy:

- **namespaces** (pid, net, mnt, uts, ipc, user) — co kontejner *vidí*,
- **cgroups** — kolik zdrojů *smí*,
- **capabilities** — co *root uvnitř* smí dělat vůči jádru,
- **seccomp / AppArmor / SELinux** — filtr syscallů a MAC.

Když kterýkoli z nich vypneme (`--privileged`, `--cap-add`, bind-mount `/`,
`docker.sock`), hranice padá a "root v kontejneru" se stává "rootem na hostiteli".

## 2. Zvolená demonstrace úniku (rychlá, spolehlivá, offline)

Cíl: přečíst hostitelský `/etc/shadow` zevnitř kontejneru. Tři cesty seřazené
od nejjednodušší:

### 2a. Naivní bind-mount (nejrychlejší na ukázku)
```
docker run --rm -v /:/host:ro alpine cat /host/etc/shadow
```
Příčina: operátor sám připojil celý kořen hostitele. Žádný exploit netřeba.

### 2b. Privileged escape přes device hostitele
```
docker run --rm --privileged alpine sh -c 'fdisk -l; mkdir /m; mount /dev/sda1 /m; cat /m/etc/shadow'
```
Příčina: `--privileged` dá přístup ke všem `/dev` zařízením hostitele →
připojím jeho disk a čtu cokoliv.

### 2c. Únik přes Docker socket
```
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock docker \
  sh -c 'docker run --rm -v /:/host alpine cat /host/etc/shadow'
```
Příčina: kdo má přístup k `docker.sock`, je de facto root na hostiteli —
spustí si nový kontejner s namountovaným `/`.

### 2d. Starší CVE jako ilustrace řetězení "RCE → escape"
- **CVE-2019-5736 (runc)** — přepsání `runc` binárky z kontejneru → spuštění
  kódu na hostiteli. Historický, dnes záplatovaný; použijeme jen jako příběh:
  "appka v kontejneru má RCE, útočník se dostane dovnitř jako root a díky
  staré runc escapne na hostitele."
- **Shellshock (CVE-2014-6271)** — na image `bash:4.3` jde ukázat jednou
  proměnnou prostředí; hezky demonstruje "stará vrstva = stará díra", kterou
  odhalí scanner.

## 3. Nejčastější zranitelnosti ↔ Docker nastavení (jádro výstupu)

| # | Zranitelnost / chyba | Dopad | Docker nastavení, které pomáhá |
|---|----------------------|-------|-------------------------------|
| 1 | Běh jako **root (UID 0)** | RCE v appce = root v kontejneru | `USER 10001` v Dockerfile, `--user`, `--security-opt=no-new-privileges` |
| 2 | **`--privileged`** | Plný escape na hostitele | Nikdy nepoužívat; místo toho cílené `--cap-add` |
| 3 | **Nadbytečné capabilities** | `CAP_SYS_ADMIN` atd. umožní mount/escape | `--cap-drop=ALL` + přidat jen nutné (`NET_BIND_SERVICE`) |
| 4 | **Bind-mount `/` nebo citlivých cest** | Čtení/zápis souborů hostitele | Pojmenované volumes, `:ro`, mountovat jen potřebné podsložky |
| 5 | **Namountovaný `docker.sock`** | Triviální root escape | Nemountovat; pokud nutno, socket-proxy s omezeným API |
| 6 | **Zapisovatelný filesystem** | Perzistence útočníka, tamper | `--read-only` + `--tmpfs /tmp` |
| 7 | **Secrets v ENV / image vrstvách** | Únik klíčů (zůstávají v historii image) | Docker/BuildKit `--secret`, soubory mimo image, vault |
| 8 | **Zastaralé base image (staré CVE)** | Známé RCE/priv-esc v knihovnách | Pinovat verze, slim/distroless, pravidelný rebuild + sken |
| 9 | **Bez limitů zdrojů** | DoS hostitele (fork bomb, OOM) | `--memory`, `--cpus`, `--pids-limit` |
| 10 | **Plochá/sdílená síť** | Laterální pohyb mezi kontejnery | User-defined network, `--network none`, segmentace |
| 11 | **Default seccomp vypnutý** | Nebezpečné syscally | Nechat default seccomp zapnutý, `no-new-privileges` |
| 12 | **Image z neověřeného zdroje** | Dodavatelský řetězec | Oficiální/podepsané image, sken před nasazením |

## 4. Scanning: Trivy vs. Docker Scout

- **Trivy** (Aqua) — offline/CI friendly, zdarma, skenuje OS balíčky i app
  závislosti, misconfig, secrets. `trivy image <image>`.
- **Docker Scout** — integrováno v Docker Desktopu/CLI, vyžaduje **přihlášení**
  (`docker login`, účet Docker Hub). `docker scout cves <image>`,
  `docker scout recommendations <image>` navrhne lepší base image.

### Image k analýze (schválně mix starých a nových)
- `python:2.7` — EOL, stovky CVE → ukázka "proč neběžet na EOL".
- `node:8` — staré, mnoho CVE.
- `nginx:1.14` — staré, srovnání s `nginx:stable-alpine`.
- `debian:bullseye` vs `debian:bookworm-slim` vs `gcr.io/distroless/static`.
- Vlastní `vuln.Dockerfile` (root, kopíruje secret) vs `hardened.Dockerfile`.

### Typický návrh zabezpečení z nálezů
1. Přejít z plného base image na **slim / alpine / distroless**.
2. **Pinovat** konkrétní verze a pravidelně rebuildit.
3. Odstranit build nástroje z finálního image (multi-stage build).
4. Nepouštět jako root, přidat `HEALTHCHECK`, drop capabilities.
5. Secrets ven z image.

## 5. Zlatý standard — hardened spuštění
```
docker run -d --name app \
  --user 10001:10001 \
  --read-only --tmpfs /tmp \
  --cap-drop=ALL --cap-add=NET_BIND_SERVICE \
  --security-opt=no-new-privileges \
  --memory=256m --cpus=0.5 --pids-limit=100 \
  --network app-net \
  -v app-data:/data:rw \
  myapp:pinned-1.2.3
```
