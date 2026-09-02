# TelcoLab1 - GitOps Repo

Repositorio GitOps para K3s + Open5GS + MongoDB + WebUI + ArgoCD.

## Workflow
Cambios via rama `dev` + Pull Request antes de mergear a `main`.


## Highlights

- **[Zero Trust Network Access (Cloudflare Tunnel + Access)](docs/cloudflare-zero-trust/README.md)** — Grafana exposed to the internet with zero open inbound ports, gated by an identity policy. Validated end-to-end: authorized access works, unauthenticated sessions get challenged, and the underlying port times out when hit directly.
