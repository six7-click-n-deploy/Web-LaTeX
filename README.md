# App-Entwickler-Anleitung

Diese Anleitung richtet sich an App-Entwickler, die eine App für die Click-n-Deploy-Plattform bauen wollen. Sie beschreibt alle Anforderungen und Möglichkeiten — von der minimalen App bis hin zu erweiterten Funktionen wie Packer-Images, User-Management und File-Uploads.

---

## 1. Was ist eine App?

Eine App ist ein **Git-Repository** (GitHub oder GitLab) mit einem `terraform/`-Verzeichnis und einem optionalen `packer/`-Verzeichnis.

Die Plattform klont das Repo bei jedem Deploy auf einen versionierten Git-Tag, baut ggf. die in `packer/` definierten Images und wendet den `terraform/`-Plan gegen das OpenStack-Backend an. Die durch Terraform exportierten Outputs werden vom Backend gelesen, um Zugangsdaten an Endnutzer zu mailen und das Infrastruktur-Panel im UI zu befüllen.

---

## 2. Voraussetzungen für lokale Entwicklung

- **Terraform** >= 1.5
- **Packer** >= 1.9 (nur wenn ein eigenes Image gebaut wird)
- **OpenStack-Zugang** (`clouds.yaml`)

### Installation (macOS)

```bash
brew install terraform
brew install packer
```

### Installation (Windows)

```bash
winget install Hashicorp.Terraform
winget install Hashicorp.Packer
```

### OpenStack Auth (`clouds.yaml`)

Die `clouds.yaml` kann direkt aus OpenStack heruntergeladen werden:
**Profil (oben rechts) → OpenStack clouds.yaml-Datei herunterladen**

Die heruntergeladene Datei enthält kein Passwort — folgende Zeile muss manuell unter `auth:` ergänzt werden:

```yaml
password: "<DEIN PASSWORT>"
```

Standardpfad:

```
~/.config/openstack/clouds.yaml
```

Beispiel:

```yaml
clouds:
  openstack:
    auth:
      auth_url: <AUTH_URL>
      username: "<USERNAME>"
      password: "<PASSWORD>"
      project_name: "<PROJECT_NAME>"
      user_domain_name: "<USER_DOMAIN_NAME>"
    region_name: "<REGION_NAME>"
    interface: "public"
    identity_api_version: 3
```

> **Wichtig:** Der Profilname in der `clouds.yaml` **muss** `openstack` heißen — die Plattform erwartet genau diesen Namen.

---

## 3. Repository erstellen

### Option A: Template der Organisation nutzen (empfohlen)

Das Template-Repository unter [six7-click-n-deploy/template-app](https://github.com/six7-click-n-deploy/template-app) auf GitHub öffnen und oben rechts auf **"Use this template"** → **"Create a new repository"** klicken. Anschließend das neue Repository lokal klonen:

```bash
git clone <DEINE_REPO_URL>
cd <REPO_NAME>
```

Das Template enthält bereits eine vollständige Struktur:

```
template-app/
├── packer/
│   ├── template.pkr.hcl          # Packer Template (Image Build)
│   ├── variables.pkr.hcl         # Packer-Variablen
│   └── scripts/
│       └── provision.sh          # Provisioning Script
│
├── terraform/
│   ├── main.tf                   # OpenStack Ressourcen
│   ├── variables.tf              # Variablen
│   ├── outputs.tf                # Outputs
│   ├── user-data.yaml.tpl        # cloud-init Template
│   └── terraform.tfvars          # Lokale Konfiguration (nicht committen)
│
├── .github/
│   ├── workflows/
│   │   ├── packer.yml            # CI: packer fmt + validate
│   │   └── terraform.yml         # CI: terraform fmt + validate + tflint + tfsec
│   └── actions/
│       └── action.yml            # Custom Action: Packer installieren
├── .gitignore
└── README.md
```

Das Template setzt bereits **User-Management** und ein **Single-Packer-Image** um — beides ist optional und kann entfernt werden, wenn es nicht benötigt wird.

### Option B: Eigenes Repository ohne Template

Ein eigenes Git-Repository kann ebenfalls genutzt werden. Die Mindestanforderung ist ein `terraform/`-Verzeichnis mit den drei Pflichtdateien (siehe Abschnitt 4).

---

## 4. Minimale App (ohne Packer, ohne User-Management)

Die kleinste funktionierende App besteht aus drei Dateien im `terraform/`-Verzeichnis:

```
my-app/
└── terraform/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

### `terraform/main.tf`

```hcl
terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54"
    }
  }
}

provider "openstack" {
  cloud = "openstack"
}

resource "openstack_compute_instance_v2" "vm" {
  name        = "my-app-vm"
  image_name  = "Ubuntu 22.04"
  flavor_name = var.flavor_name

  network {
    uuid = var.network_uuid
  }
}
```

### `terraform/variables.tf`

Variablen, die der AppStore oder der Nutzer beim Deployment konfiguriert, werden hier deklariert. Für lokales Testen kann eine `terraform.tfvars`-Datei angelegt werden (nicht committen — steht im `.gitignore`).

```hcl
################################################
# PFLICHT-Variablen
################################################
variable "users" {
  description = "Per-team roster — vom Worker injiziert. @platform:internal"
  type = map(list(object({
    email = string
  })))
  default = {}
}

# image_name ist nur Pflicht wenn packer existiert
variable "image_name" {
  description = "Glance-Image-Name — vom Worker zur Apply-Zeit gesetzt. @platform:internal"
  type        = string
}

################################################
# Beispiele frei konfigurierbarer Variable
################################################
variable "flavor_name" {
  description = "VM-Größe @openstack:flavor:name"
  type        = string
  default     = "gp1.small"
}

variable "network_uuid" {
  description = "Hauptnetzwerk @openstack:network:id"
  type        = string
}
```

### `terraform/outputs.tf`

Outputs werden vom AppStore ausgelesen und dem Nutzer angezeigt. Auch wenn keine Daten zurückgegeben werden sollen, **müssen** alle drei Outputs deklariert sein.

```hcl
output "user_accounts" {
  description = "User-Zugangsdaten"
  sensitive   = true
  value       = {}
}

output "team_vms" {
  description = "Details aller Team-VMs"
  value       = {}
}

output "teams_summary" {
  description = "Übersicht: Teams und User-Anzahl"
  value       = {}
}
```

### `terraform/terraform.tfvars` (lokal, nicht committen)

```hcl
flavor_name  = "gp1.small"
network_uuid = "34a00b87-57ce-42c4-8e1b-9ea8a657ec2e"
```

---

## 5. Pflichtanforderungen für den AppStore

Damit die App im AppStore korrekt funktioniert, **müssen** folgende Variablen in `variables.tf` deklariert sein:

### `users` (immer Pflicht)

```hcl
variable "users" {
  description = "Vom Worker injiziert. @platform:internal"
  type = map(list(object({
    email = string
  })))
  default = {}
}
```

Der AppStore injiziert beim Deployment die Teams und zugehörigen User in diese Variable. Die Struktur ist dabei eine Map, bei der der Key der Team-Name ist und der Wert eine Liste von Nutzern mit ihrer E-Mail-Adresse. Wie der App-Entwickler mit dieser Struktur intern umgeht (ob er Teams als getrennte VMs deployt, eine gemeinsame VM baut, etc.), ist ihm überlassen.

### `image_name` (Pflicht wenn `packer/` existiert)

```hcl
variable "image_name" {
  description = "Glance-Image-Name — vom Worker zur Apply-Zeit gesetzt. @platform:internal"
  type        = string
}
```

Der AppStore setzt diesen Wert automatisch auf den Namen des gebauten Packer-Images. Die Variable darf nicht im Deployment-Wizard erscheinen — dafür sorgt der `@platform:internal`-Marker (siehe Abschnitt 5.3).

---

## 6. Optionale Funktionen

### 6.1 Packer — Eigenes VM-Image bauen

Packer ermöglicht es, ein eigenes VM-Image zu bauen, das bereits alle nötigen Abhängigkeiten, Konfigurationen und Applikationen enthält. Statt bei jedem Deployment alles neu zu installieren, wird das Image einmalig gebaut und danach für alle Deployments wiederverwendet. Der AppStore baut das Packer-Image automatisch vor dem Terraform-Deployment.

#### Struktur

```
my-app/
├── packer/
│   ├── template.pkr.hcl
│   ├── variables.pkr.hcl
│   └── scripts/
│       └── provision.sh
└── terraform/
    └── ...
```

#### `packer/variables.pkr.hcl`

Definiert die Eingabevariablen für den Packer-Build. Pflicht-Variablen:

```hcl
variable "image_name" {
  type        = string
  description = "Glance-Image-Name — vom Worker zur Build-Zeit gesetzt. @platform:internal"
}

variable "networks" {
  type        = list(string)
  description = "@openstack:network:id:list Build-Netzwerke"
  default     = ["<NETWORK-ID>"]
}

variable "security_groups" {
  type        = list(string)
  description = "@openstack:security_group:id:list Build-Security-Groups"
  default     = ["<SECURITY-GROUP-ID>"]
}
```

#### `packer/template.pkr.hcl`

Definiert die Build-Quelle und ruft das Provisioning Script auf:

```hcl
packer {
  required_plugins {
    openstack = {
      source  = "github.com/hashicorp/openstack"
      version = "~> 1"
    }
  }
}

source "openstack" "image" {
  image_name        = var.image_name
  source_image_name = "Ubuntu 22.04"
  flavor            = "gp1.small"
  networks          = var.networks
  security_groups   = var.security_groups
  ssh_username      = "ubuntu"
}

build {
  sources = ["source.openstack.image"]

  provisioner "shell" {
    script = "scripts/provision.sh"
  }
}
```

#### `packer/scripts/provision.sh`

Hier wird definiert, was ins Image kommt. Typische Inhalte:

- Pakete und Runtimes installieren
- App-Artefakte deployen (Binary, Container, Webapp)
- Konfigurationsdateien schreiben
- systemd-Services einrichten
- Optional: Reverse Proxy / TLS konfigurieren

```bash
#!/bin/bash
set -euo pipefail

apt-get update -y
apt-get install -y nginx

# App-Installation hier...

systemctl enable nginx
```

**Wichtige Regeln:**
- Keine Secrets hardcoden
- Idempotent schreiben (mehrfaches Ausführen darf nichts kaputt machen)

---

### 6.2 User-Management

User-Management ermöglicht es, jedem Endnutzer individuelle Zugangsdaten zu geben, sodass Nutzer abgegrenzt voneinander arbeiten können. Wie das User-Management technisch umgesetzt wird (getrennte VMs pro Team, Nutzerkonten auf einer VM, etc.) ist dem App-Entwickler überlassen.

Der AppStore liefert die Team- und Nutzerstruktur über die `users`-Variable (siehe Abschnitt 5). Die App muss die generierten Zugangsdaten über den `user_accounts`-Output zurückgeben, damit der AppStore sie per Mail an die Endnutzer versendet.

#### Struktur mit User-Management

```
my-app/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── user-data.yaml.tpl    # cloud-init Template für Zugangsdaten
└── ...
```

#### `terraform/user-data.yaml.tpl`

Das cloud-init-Template wird beim VM-Start ausgeführt und übergibt Laufzeit-Daten (Zugangsdaten, Dateien) an die VM. Es wird in `main.tf` über `templatefile()` gerendert:

```yaml
#cloud-config

bootcmd:
  # Vor write_files ausgeführt — Verzeichnisse anlegen die write_files benötigt
  - mkdir -p /etc/myapp/users
  - chown root:root /etc/myapp/users
  - chmod 750 /etc/myapp/users

write_files:
%{ for user in team_users ~}
  - path: '/etc/myapp/users/${user.email}.env'
    permissions: '0640'
    owner: 'root:myapp'
    content: |
      EMAIL=${user.email}
      PASSWORD=${user.password}
%{ endfor ~}

runcmd:
  - bash /usr/local/bin/myapp-provision.sh > /var/log/myapp-provision.log 2>&1
```

#### Output `user_accounts` (Pflicht für Mail-Versand)

Damit der AppStore Zugangsdaten per Mail versendet, **muss** `user_accounts` korrekt befüllt sein. Der Key **muss** die Form `<team-name>-<username>` haben:

```hcl
output "user_accounts" {
  sensitive = true
  value = {
    "team-a-alice" = {
      username = "alice"
      type     = "password"
      auth     = "hunter2"
      ip       = "10.0.1.42"
      port     = 8080
    }
  }
}
```

**Verfügbare Auth-Typen:**

| `type`     | Darstellung in der Mail        | Inhalt von `auth`          |
|------------|-------------------------------|---------------------------|
| `password` | "Password: …"                 | Passwort-String            |
| `ssh_key`  | Monospace SSH-Key-Block        | Public-Key oder Hinweistext |
| `oauth`    | "Login at …"-Link              | Login-URL                  |
| `none`     | Kein Credential-Block          | `auth` kann fehlen         |

#### `metadata.team` auf VM-Ressourcen

Damit der AppStore VMs im Infrastruktur-Panel dem richtigen Team zuordnet, **sollte** jede VM ein `metadata`-Tag mit dem Team-Key erhalten:

```hcl
resource "openstack_compute_instance_v2" "team_vm" {
  for_each = toset(local.teams)
  name     = "vm-${each.key}"

  metadata = {
    team = each.key
  }
  # ...
}
```

Ohne diesen Tag wird die VM im Panel unter "Shared" angezeigt.

---

### 6.3 `@openstack`-Marker für Variablen

Mit dem `@openstack`-Marker in der `description` einer Terraform- oder Packer-Variable steuert der App-Entwickler, welches UI-Element der AppStore-Wizard rendert. Ohne Marker erhält der Nutzer nur ein freies Textfeld. Je nach Marker öffnen sich Dropdown-Menüs (z.B. für Flavors oder Netzwerke), Multi-Select-Felder oder Datei-Upload-Felder.

#### Übersicht aller Marker-Möglichkeiten

```
@openstack:<type>[:<mode>][:<multi>][:<var_scope>]
```

| Slot         | Mögliche Werte                                                                                                           | Default                  |
|--------------|--------------------------------------------------------------------------------------------------------------------------|--------------------------|
| `type`       | `network`, `subnet`, `flavor`, `image`, `keypair`, `security_group`, `floating_ip_pool`, `volume`, `router`, `availability_zone`, `file` | —         |
| `mode`       | `id`, `name`                                                                                                             | `name`                   |
| `multi`      | `single`, `multi` / `list`                                                                                               | aus HCL-Typ abgeleitet   |
| `var_scope`  | `all`, `team`, `user`                                                                                                    | `all`                    |

Der `@openstack`-Prefix ist case-insensitive. Mehrere Marker pro Description sind erlaubt — der erste Marker mit bekanntem Type gewinnt.

#### Beispiele

```hcl
# Netzwerk-Picker (Name), Single-Select:
variable "network_name" {
  description = "@openstack:network:name Primäres Netzwerk"
  type        = string
}

# Netzwerk-Picker (UUID), Multi-Select (z.B. für Packer):
variable "networks" {
  description = "@openstack:network:id:list Build-Netzwerke"
  type        = list(string)
}

# Flavor-Picker, einer pro Team:
variable "team_flavor_ids" {
  description = "@openstack:flavor:id:single:team Flavor pro Team"
  type        = map(string)
  default     = {}
}

# Security-Group-Picker, Multi-Select:
variable "secgroups" {
  description = "@openstack:security_group:name:multi"
  type        = list(string)
}

# Freies Textfeld pro User (kein OpenStack-Typ):
variable "github_handles" {
  description = "@openstack:::user GitHub-Username pro Endnutzer"
  type        = map(string)
  default     = {}
}

# Multi-Select Security Groups pro Team:
variable "team_secgroups" {
  description = "@openstack:security_group:name:multi:team"
  type        = map(list(string))
  default     = {}
}
```

#### `var_scope`: Werte pro Team oder pro User

Mit `:team` oder `:user` als letztem Slot rendert der Wizard einen Picker **pro Team bzw. pro User** und übergibt das Ergebnis als Map an Terraform.

**Pflicht:** Wenn `var_scope` `team` oder `user` ist, **muss** der HCL-Typ ein `map(...)` sein — sonst schlägt die Approval mit `MARKER_SCOPED_REQUIRES_MAP` fehl.

Kurzform für reinen `var_scope` ohne OpenStack-Typ: `@openstack::team` (Scope im Mode-Slot) ist äquivalent zu `@openstack:::team`.

In Packer-Variablen ist `var_scope=team` oder `=user` **verboten** — ein Packer-Build erzeugt ein einzelnes Image, das von allen Teams gemeinsam genutzt wird.

#### `@platform:internal` — Variablen aus dem Wizard ausblenden

Variablen, die vom AppStore automatisch zur Laufzeit gesetzt werden, **müssen** mit `@platform:internal` markiert werden, damit sie nicht im Deployment-Wizard für den Nutzer erscheinen und fälschlich überschrieben werden können.

```hcl
variable "image_name" {
  description = "Glance-Image-Name — vom Worker zur Apply-Zeit gesetzt. @platform:internal"
  type        = string
}

variable "users" {
  description = "Per-team roster — vom Worker injiziert. @platform:internal"
  type        = map(list(object({ email = string })))
  default     = {}
}
```

Folgende Variablen werden vom AppStore automatisch injiziert und **müssen** deklariert sein:

| Variable              | Wann injiziert                        |
|-----------------------|---------------------------------------|
| `users`               | Immer, sobald Teams im Deploy existieren |
| `image_name`          | Bei Single-Packer-Image-Apps          |
| `image_name_<key>`    | Bei Multi-Packer-Image-Apps (je Subdirectory-Key) |

---

### 6.4 File-Upload-Variablen

Mit dem `@openstack:file:`-Marker kann der App-Entwickler Datei-Uploads im AppStore-Wizard ermöglichen. Der Dateiinhalt wird base64-encodiert in eine Terraform-Map injiziert und kann per `cloud-init` auf der VM materialisiert werden.

**Pflicht** bei File-Uploads: Erlaubte Dateiendungen **müssen** angegeben werden. Als Trenner **muss** `|` verwendet werden (kein Komma).

#### Marker-Form

```
@openstack:file:<scope>:<ext1>|<ext2>|...
```

- `<scope>` ∈ `all` | `team` | `user`
- `<ext1>|<ext2>` — Pipe-separierte Liste erlaubter Extensions (lowercase, ohne Punkt)

File-Marker sind in Packer-Variablen **verboten**.

#### HCL-Typen je Scope

| Scope  | HCL-Typ |
|--------|---------|
| `all`  | `map(object({ name=string, content_b64=string, content_type=string, size=number }))` |
| `team` | `map(map(object({ name=string, content_b64=string, content_type=string, size=number })))` |
| `user` | `map(map(object({ name=string, content_b64=string, content_type=string, size=number })))` |

#### Beispiel: Ein Upload-Slot für alle Teams

```hcl
variable "assignment_files" {
  description = <<-EOT
    @openstack:file:all:pdf
    Aufgabenstellung — eine PDF für alle Teams.
  EOT
  type = map(object({
    name         = string
    content_b64  = string
    content_type = string
    size         = number
  }))
  default = {}
}
```

Konsum in `user-data.yaml.tpl`:

```yaml
write_files:
%{ for slot_key, file in assignment_files ~}
  - path: /opt/app/${file.name}
    permissions: "0644"
    encoding: b64
    content: ${file.content_b64}
%{ endfor ~}
```

#### Beispiel: Ein Slot pro Team

```hcl
variable "team_briefings" {
  description = "@openstack:file:team:pdf|docx Briefing-Doku pro Team"
  type = map(map(object({
    name         = string
    content_b64  = string
    content_type = string
    size         = number
  })))
  default = {}
}
```

Der äußere Map-Key ist die Team-ID, der innere der Slot-Key.

#### Wichtig: Verhalten beim Destroy

Beim Destroy eines Deployments entfernt der AppStore alle file-shaped Variablen aus dem `-var`-Set. File-Variablen dürfen deshalb **nicht** in `count = …` oder `for_each = …` referenziert werden — beim Destroy wäre der Wert leer und Terraform würde Ressourcen fälschlich löschen wollen.

---

### 6.5 Multi-Packer-Image-Apps

Statt eines einzelnen Images können mehrere Images parallel gebaut werden — z.B. ein separates Image für Webserver und Datenbank. Der Wechsel von Single- zu Multi-Image ist ausschließlich eine Frage des Verzeichnis-Layouts im `packer/`-Ordner.

#### Struktur

```
my-app/
├── packer/
│   ├── webserver/
│   │   ├── template.pkr.hcl
│   │   ├── variables.pkr.hcl
│   │   └── scripts/
│   │       └── provision.sh
│   └── database/
│       ├── template.pkr.hcl
│       ├── variables.pkr.hcl
│       └── scripts/
│           └── provision.sh
└── terraform/
    └── ...
```

Die Funktion der einzelnen Dateien (`template.pkr.hcl`, `variables.pkr.hcl`, `provision.sh`) ist dieselbe wie bei der Single-Image-App (siehe Abschnitt 6.1).

**Regeln für Subdirectory-Keys** (Verzeichnisnamen):
- Format: `[a-z][a-z0-9_-]{0,30}`
- Ungültige Keys führen zu einem `PackerTemplateDiscoveryError`
- Verzeichnisse ohne `template.pkr.hcl` (z.B. `_common/`, `scripts/`) werden ignoriert
- Build-Reihenfolge: alphabetisch nach Verzeichnisname (`database` baut vor `webserver`)
- Single- und Multi-Image gleichzeitig ist **verboten**: `packer/template.pkr.hcl` und `packer/<key>/template.pkr.hcl` dürfen nicht gleichzeitig existieren

#### Packer-Variablen je Subdirectory

In jedem Subdirectory referenziert das Template `var.image_name` — **nicht** `var.image_name_<key>`. Der AppStore injiziert pro Build den korrekten Namen:

```hcl
# packer/webserver/variables.pkr.hcl
variable "image_name" {
  type        = string
  description = "Glance-Image-Name — vom Worker zur Build-Zeit gesetzt. @platform:internal"
}
```

#### Terraform-Variablen für Multi-Image (Pflicht)

Für jeden Packer-Subdirectory-Key **muss** eine separate `image_name_<key>`-Variable in `variables.tf` deklariert werden:

```hcl
variable "image_name_webserver" {
  description = "Glance-Image-Name des Webserver-Images — vom Worker gesetzt. @platform:internal"
  type        = string
}

variable "image_name_database" {
  description = "Glance-Image-Name des Database-Images — vom Worker gesetzt. @platform:internal"
  type        = string
}
```

---

## 7. Lokales Deployment

### Nur Terraform (kein Packer)

```bash
cd terraform
terraform init
terraform validate
terraform plan        # Vorschau: zeigt was erstellt/geändert/gelöscht wird
terraform apply
```

### Mit Packer (erst Image bauen, dann deployen)

```bash
# 1. Packer-Image bauen
cd packer
packer init .
packer validate .
packer build .

# 2. Terraform deployen
cd ../terraform
terraform init
terraform validate
terraform plan
terraform apply
```

**Nach `terraform apply` stehen folgende Outputs zur Verfügung:**
- `user_accounts` — Zugangsdaten (sensitiv, abrufbar mit `terraform output -json user_accounts`)
- `team_vms` — Details aller Team-VMs mit IP-Adressen und App-URL
- `teams_summary` — Übersicht der Teams mit jeweiliger User-Anzahl

---

## 8. Cleanup

### Infrastruktur entfernen

```bash
cd terraform
terraform destroy
```

### Packer-Image entfernen (optional)

```bash
openstack image list
openstack image delete <IMAGE_ID>
```

---

## 9. Checks und CI/CD

Vor dem Pushen können folgende Checks lokal ausgeführt werden:

**Einmalige Installation (macOS):**

```bash
brew install tflint    
brew install tfsec     
```

**Terraform:**

```bash
cd terraform
terraform fmt          # Formatierung korrigieren
terraform validate     # Syntax prüfen
terraform plan         # Deployment-Vorschau
tflint --recursive     # Linter
tfsec .                # Security-Check
```

**Packer:**

```bash
cd packer
packer fmt .           # Formatierung korrigieren
packer validate .      # Syntax prüfen
```

### GitHub Actions Workflow (bei Nutzung des Templates)

Wer das Template der Organisation nutzt, erhält automatisch zwei vorkonfigurierte GitHub Actions Workflows:

| Workflow         | Datei                          | Was wird geprüft                                  |
|------------------|--------------------------------|---------------------------------------------------|
| Terraform CI     | `.github/workflows/terraform.yml` | `terraform fmt`, `terraform validate`, `tflint`, `tfsec` |
| Packer CI        | `.github/workflows/packer.yml`    | `packer fmt`, `packer validate`                   |

Diese Workflows laufen automatisch bei jedem Push. Schlägt einer der Checks fehl, wird der Workflow als fehlgeschlagen markiert.

---

## 10. App dem AppStore hinzufügen

### Release / Git-Tag erstellen

Die Plattform deployt ausschließlich versionierte Git-Tags — keinen Branch. Vor dem Hinzufügen der App im AppStore **muss** ein Release mit einem Git-Tag im folgenden Format erstellt werden:

```
v<Major>.<Minor>.<Patch>
```

Beispiel: `v1.0.0`, `v0.2.1`

Tags in anderen Formaten funktionieren zwar technisch, sortieren aber nur lexikographisch und können im Wizard zur falschen "neueste Version"-Anzeige führen.

Zu jedem Release **muss** eine umfassende Beschreibung erstellt werden (siehe unten).

### App registrieren

Bei **privaten Repositories** muss zunächst der Collaborator `six7clickndeploy` hinzugefügt werden, damit der AppStore Zugriff hat:
**Settings → Collaborators → Add people → `six7clickndeploy`**

Bei öffentlichen Repositories ist dieser Schritt nicht notwendig.

Danach die **GitHub-URL des Repositories** im AppStore unter **"App hinzufügen"** eintragen:

```
https://github.com/<dein-username>/<repo-name>
```

Der AppStore liest daraufhin die Konfiguration (Variablen, Packer-Template, Terraform) automatisch aus dem Repository ein.

### Pflichtangaben in der App-Beschreibung

Bei der Registrierung und bei jedem neuen Release **muss** eine umfassende Beschreibung der App hinterlegt werden. Diese muss mindestens folgende Punkte abdecken:

- **User-Management:** Ist ein User-Management vorhanden? Wie ist es geregelt? (z.B. ein Account pro User, gemeinsame Zugangsdaten pro Team)
- **VM-Deployment:** Wie viele VMs werden deployed? (z.B. eine VM pro Team, eine VM pro User, eine gemeinsame VM)
- **Konfigurierbare Variablen:** Welche Variablen kann der Deployer konfigurieren und wie werden diese befüllt? (z.B. Flavor-Auswahl, Netzwerk, Datei-Upload)
- **Änderungen im Release:** Was wurde in dieser Version geändert oder hinzugefügt?
