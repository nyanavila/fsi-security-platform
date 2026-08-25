# Activation keys + client registration — reference

## 1. Create activation keys in Satellite

Content → Activation Keys → Create Activation Key, for each:

| Key name | Environment | Content View | Repo sets to enable |
|---|---|---|---|
| `fsi-corebanking-rhel8-ak` | Library | Default Organization View | RHEL 8 BaseOS, RHEL 8 AppStream, Satellite Client 6 for RHEL 8 |
| `fsi-corebanking-rhel9-ak` | Library | Default Organization View | RHEL 9 BaseOS, RHEL 9 AppStream, Satellite Client 6 for RHEL 9 |
| `fsi-controlplane-ak` | Library | Default Organization View | RHEL 9 BaseOS, RHEL 9 AppStream, Satellite Client 6 for RHEL 9 |

Org label to use in all registration commands: **`Default_Organization`** (confirmed via `hammer organization info --name "Default Organization"` — display Name has a space, Label uses underscore).

## 2. Register clients — use Satellite's generated command, NOT a bare subscription-manager command

Satellite UI → **Hosts → Register** → select the right activation key → it generates a `curl | bash` one-liner with a short-lived bearer token baked in. **Use this generated command** rather than typing `subscription-manager register --activationkey=...` by hand — the generated version handles CA trust and server config correctly in one shot.

**Gotchas hit during the first build, all now avoidable:**

1. **The URL Satellite shows in the browser uses `localhost:8443`** — that's only valid because your browser was going through an SSH tunnel. On the actual target host, swap this for Satellite's real address:
   - Prefer the FQDN (`ip-10-0-1-215.us-east-2.compute.internal` or your Satellite's actual hostname) — **but this only resolves if the VPC has "Enable DNS hostnames" turned on** (see Terraform `main.tf` — `enable_dns_hostnames = true` is set for exactly this reason; if you ever build this manually again, don't forget it)
   - Also drop the `:8443` — that was your tunnel's local port, Satellite's real HTTPS port is `443`

2. **Self-signed cert** — since Satellite's cert is issued for its FQDN, hitting it by raw IP will fail cert validation. Either use the FQDN (works once DNS hostnames are enabled) or add `--insecure` to the curl command if using an IP.

3. **Security group** — `fsi-sg-controlplane` must allow inbound from `fsi-sg-corebanking`, not just the reverse. Clients registering to Satellite is client-initiated traffic **toward** the control plane — a separate direction from AAP-initiated automation traffic. This is already fixed in the Terraform SG rules above; don't remove that rule if editing later.

4. **Token expiry** — the bearer token in Satellite's generated command is short-lived (~4hrs). If you wait too long between generating and running it, regenerate fresh from **Hosts → Register**.

### Doing this via AAP instead of manual SSH

Once you have a working Machine Credential and static inventory in AAP:
- **Resources → Inventories → [inventory] → Hosts** → select target hosts → **Run Command**
- Module: `shell` (not `command` — need pipe support for `curl | bash`)
- Arguments: the corrected (FQDN, port 443, fresh token) registration command
- Credential: your SSH machine credential, Become enabled

## 3. Confirm registration

Satellite UI → **Hosts → All Hosts** — should show Satellite itself (self-registered at install), plus every host you've registered via activation key.

## 4. Bootstrapping to Satellite dynamic inventory in AAP

Once hosts are registered to Satellite, set up the live inventory source:
- **Resources → Credentials → Add** → type **Red Hat Satellite** → URL `https://<satellite-fqdn>`, username/password
- **Resources → Inventories → Add** → new inventory → **Sources** tab → Add → Source: Red Hat Satellite → select the credential → Save → **Sync**

From then on this inventory stays live-synced with whatever Satellite manages — no more manual host entry needed.
