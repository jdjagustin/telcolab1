# TelcoLab1 - GitOps Repo

Repositorio GitOps para K3s + Open5GS + MongoDB + WebUI + ArgoCD.

## Workflow
Cambios via rama `dev` + Pull Request antes de mergear a `main`.


## Highlights

- **[Zero Trust Network Access (Cloudflare Tunnel + Access)](docs/cloudflare-zero-trust/README.md)** — Grafana exposed to the internet with zero open inbound ports, gated by an identity policy. Validated end-to-end: authorized access works, unauthenticated sessions get challenged, and the underlying port times out when hit directly.
- **[Internal segmentation (default-deny NetworkPolicy on Open5GS)](docs/networkpolicy-microsegmentation/README.md)** — 25 label-based `NetworkPolicy` objects locking the `open5gs` namespace down to only its real NF-to-NF relationships, built from the actual running config rather than generic docs. Validated end-to-end: an unlabeled pod gets blocked, and a full 5G registration → 5G-AKA auth → PDU session → real ping still works with every policy active.
