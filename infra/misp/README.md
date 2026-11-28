# Step 7 — MISP access locally and over a VPN

## Local configuration

In each instance's `docker-compose.yml`, `misp-nginx` uses:

```yaml
ports:
  - "${MISP_BIND_IP:-127.0.0.1}:${NGINX_HTTP_PORT:-8080}:8080"
  - "${MISP_BIND_IP:-127.0.0.1}:${NGINX_HTTPS_PORT:-8443}:8443"
```

Copy `template.env` to `.env` in the instance directory if `.env` does not already exist. For local testing, use:

```ini
MISP_BIND_IP=127.0.0.1
BASE_URL=https://localhost:8443
NGINX_HTTP_PORT=8080
NGINX_HTTPS_PORT=8443
```

## When the VPN is ready

Connect both machines using your chosen VPN, such as ZeroTier, Tailscale or WireGuard. The addresses below are examples; replace them with the actual VPN addresses assigned to your machines.

| Configuration | Your PC | Colleague's PC |
| --- | --- | --- |
| Instance | MISP A | MISP B |
| VPN IP | `10.10.10.10` | `10.10.10.20` |
| HTTPS port | `8443` | `8443` |
| Organization | Organization-A | Organization-B |

Both instances can use the same ports because they run on separate physical machines. If running both on one machine with the same binding address, assign different host ports and update each `BASE_URL` accordingly.

Your PC's `.env`:

```ini
MISP_BIND_IP=10.10.10.10
BASE_URL=https://10.10.10.10:8443
NGINX_HTTP_PORT=8080
NGINX_HTTPS_PORT=8443
```

Your colleague's `.env`:

```ini
MISP_BIND_IP=10.10.10.20
BASE_URL=https://10.10.10.20:8443
NGINX_HTTP_PORT=8080
NGINX_HTTPS_PORT=8443
```

After editing `.env`, run this command from the relevant instance directory to apply the configuration:

```powershell
docker compose up -d
```

Limit access to authorized peers through VPN access rules and Windows Firewall rules. Do not publish MariaDB, Redis or other internal services to the VPN. The optional MISP-Guard proxy is bound to loopback only.
