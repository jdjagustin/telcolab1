# TelcoLab1 — Cloud-Native 5G/4G Mobile Core, GitOps-Managed

![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s-326CE5?logo=kubernetes&logoColor=white)
![GitOps](https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo&logoColor=white)
![CNI](https://img.shields.io/badge/CNI-Calico-00ABDA?logo=projectcalico&logoColor=white)
![Core](https://img.shields.io/badge/5G%2F4G_Core-Open5GS-2E8B57)
![Segmentation](https://img.shields.io/badge/Segmentation-NetworkPolicy-C0392B)
![Validated](https://img.shields.io/badge/Validated_with-Infection_Monkey-8B0000)

A cloud-native mobile core network built end-to-end on standards-based infrastructure: a Kubernetes platform following CNCF cloud-native patterns (GitOps delivery, declarative infrastructure, service-based networking) hosting a 3GPP-compliant 5G Core (Service-Based Architecture) interworking with a 4G EPC — deployed on a bare-metal cluster, with its own container registry, a full observability stack, and, layered on top, real network security validated against an independent breach-and-attack-simulation tool.

## Workflow

Changes via a `dev` branch + Pull Request before merging to `main`.

## Highlights

- **[Cloud-native 5G/4G Core (CNCF + 3GPP standards)](docs/5g-4g-core-lab/README.md)** — a full Open5GS deployment across 5G Core (SBA) and 4G EPC network functions, running in interworking mode on a bare-metal Kubernetes cluster, delivered via GitOps (ArgoCD), with a self-hosted container registry and full observability stack. The platform everything below is built and validated on.
- **[Zero Trust Network Access (Cloudflare Tunnel + Access)](docs/cloudflare-zero-trust/README.md)** — Grafana exposed to the internet with zero open inbound ports, gated by an identity policy. Validated end-to-end: authorized access works, unauthenticated sessions get challenged, and the underlying port times out when hit directly.
- **[Internal segmentation (default-deny NetworkPolicy on Open5GS)](docs/networkpolicy-microsegmentation/README.md)** — 25 label-based `NetworkPolicy` objects locking the `open5gs` namespace down to only its real NF-to-NF relationships, built from the actual running config rather than generic docs. Validated end-to-end: an unlabeled pod gets blocked, and a full 5G registration → 5G-AKA auth → PDU session → real ping still works with every policy active.
- **[Adversarial microsegmentation validation (Infection Monkey, by Akamai/Guardicore)](docs/infection-monkey-validation/README.md)** — pointed Infection Monkey, the open-source breach-and-attack-simulation tool built by Akamai (formerly Guardicore), at the cluster under the worst-case assumption for the defender (an agent already running bare-metal on a node, not a pod). Surfaced and drove the fix of two real, independent issues, then closed with an isolated run showing zero reachable or exploitable core Network Functions.
- **[Webhook-to-SQL pipeline (HMAC-signed events, real PDU sessions)](docs/webhook-etl-pipeline/README.md)** — a live PDU session event read out of the SMF pod's own logs, signed with HMAC-SHA256, verified with a constant-time comparison, landed in S3-compatible storage, and loaded through an ETL step into a real PostgreSQL database queried with aggregate SQL. Validated end-to-end: a correctly signed event is accepted and lands in both storage and the database, a forged signature is rejected before touching either.
