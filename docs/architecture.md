# Architecture

A private Open WebUI chat platform on a single Azure VM, fronted by Caddy over
HTTPS, backed by Azure OpenAI, and reachable only from an IP allow-list.

Everything lives in one resource group, `rg-openwebui`.

## Diagram
```mermaid
flowchart TB
    B["Browser<br/><i>allow-listed IP only</i>"]

    subgraph AZ["Azure subscription · rg-openwebui"]
        direction TB
        NSG["<b>NSG</b> — nsg-openwebui<br/>allow 22 + 443 from allowed_cidrs<br/>deny everything else"]
        PIP["<b>Public IP</b> — pip-openwebui<br/>Standard SKU, static<br/>survives stop/start, not a rebuild"]
        NIC["<b>NIC</b> — nic-openwebui<br/>VNet 10.10.0.0/16 · subnet 10.10.1.0/24<br/>private address assigned by Azure"]
        VM["<b>VM</b> — vm-openwebui<br/>Ubuntu 24.04 · Standard_D2s_v7 · centralus"]

        subgraph HOST["Inside the VM"]
            direction TB
            CADDY["<b>Caddy</b> :443<br/>TLS termination, internal CA cert<br/>published 80 + 443"]
            WEBUI["<b>Open WebUI</b> :8080<br/><i>expose only — never published</i>"]
        end

        subgraph DATA["Storage"]
            OS["OS disk 64 GB"]
            DD["<b>Data disk</b> 64 GB → /mnt/data<br/>database · chats · uploads"]
        end

        subgraph AI["Azure OpenAI"]
            AOAI["openwebui-aoai (S0)<br/>deployment <b>gpt-5-mini</b>"]
        end

        subgraph MON["Monitoring"]
            LAW["law-openwebui<br/>30-day retention · 0.5 GB/day cap"]
            ALERT["4 metric alerts<br/>cpu · memory · disk · network"]
            AG["ag-openwebui → email"]
        end

        SCHED["Auto-shutdown 22:00 UTC+3"]
    end

    B -->|"HTTPS 443"| NSG
    NSG --> PIP
    PIP --> NIC
    NIC --> VM
    VM --> CADDY
    CADDY -->|"plaintext, internal docker network"| WEBUI
    WEBUI --> DD
    WEBUI -->|"HTTPS 443 + api-key"| AOAI
    WEBUI --> OS
    VM -.->|"AllMetrics"| LAW
    LAW -.-> ALERT
    ALERT --> AG
    SCHED -.-> VM
```

## Request path

1. A browser on an allow-listed IP opens `https://<vm-public-ip>`.
2. The **NSG** allows TCP 443 (and 22 for SSH) from `allowed_cidrs` and denies
   everything else, by Azure's default `DenyAllInBound` rule.
3. The **public IP** is `Standard` SKU and statically allocated, so the address
   survives a stop/start.
4. **Caddy** terminates TLS with a locally-generated certificate and reverse
   proxies to `open-webui:8080` on the private Docker network.
5. **Open WebUI** calls Azure OpenAI over HTTPS with the API key from `.env`.

Port 8080 is declared with `expose`, never `ports`, so it is never bound on the
host and cannot be reached from outside the VM.

## Why each piece is here

| Component | Reason |
|---|---|
| Static public IP | A Caddy internal certificate is bound to a fixed address; a changing IP would invalidate it and break the documented access URL. |
| NSG on the subnet | First control point. Nothing is open unless explicitly allowed. |
| UFW + `DOCKER-USER` | Host firewall mirroring the NSG. Needed because Docker publishes ports via DNAT and otherwise bypasses UFW entirely. |
| Caddy | TLS termination plus a single entry point. Open WebUI does not terminate TLS itself. |
| Managed data disk | The Open WebUI database and uploads live here, so they survive VM reimage and destroy/rebuild cycles. |
| Azure OpenAI | Managed model deployment; no model hosting on the VM. |
| Auto-shutdown 22:00 | Cost control. The VM is a development/portfolio deployment and is not needed overnight. |

## Data flow

```mermaid
sequenceDiagram
    participant B as Browser
    participant N as NSG
    participant C as Caddy
    participant W as Open WebUI
    participant D as /mnt/data
    participant A as Azure OpenAI

    B->>N: HTTPS 443
    N->>N: source in allowed_cidrs?
    N-->>B: drop (RST) if not
    N->>C: HTTPS 443
    C->>W: http://open-webui:8080
    W->>D: read/write chat history, users, uploads
    W->>A: chat completion (api-key)
    A-->>W: completion
    W-->>C: response
    C-->>B: HTTPS response (Secure, SameSite=strict cookie)
```

## Trust boundaries

| Boundary | Control |
|---|---|
| Internet → Azure | NSG allow-list on 22 and 443 |
| Internet → VM host | UFW + `DOCKER-USER`, key-only SSH |
| VM host → container network | Only Caddy can reach Open WebUI; 8080 is not published |
| Container → Azure OpenAI | API key held in `.env` at mode 600, never in git |
| User → application | Open WebUI auth; registration open, but new accounts land as `pending` with no access until an admin approves |

## Known gaps

- **No log centralisation.** Container and syslog logs stay on the VM; only VM
  metrics reach Log Analytics. See `security.md` for why.
- **No high availability.** Single VM, single data disk, no load balancer. A
  regional outage takes the platform down.
- **Alerts are untested end to end.** Rules evaluate and report `Healthy`, but
  no alert has been deliberately fired to prove email delivery works.