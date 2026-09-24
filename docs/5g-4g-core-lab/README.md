# Self-Hosted 5G/4G Core Lab — Bare-Metal Kubernetes, GitOps-Managed

A cloud-native mobile core network, built end-to-end on standards-based infrastructure: a Kubernetes platform following CNCF cloud-native patterns (GitOps delivery, declarative infrastructure, service-based networking) hosting a 3GPP-compliant 5G Core (Service-Based Architecture) interworking with a 4G EPC — deployed on a bare-metal cluster, with its own container registry, a full observability stack, and, layered on top, real network microsegmentation validated against an independent breach-and-attack-simulation tool.

This README documents the platform itself. The security work built on top of it is documented separately (see [Related projects](#related-projects) below).

## Overview

- **Core network:** [Open5GS](https://github.com/open5gs/open5gs), deployed with the full set of 5G Core Network Functions plus the 4G EPC Network Functions needed for interworking — not a minimal/demo subset.
- **Platform:** [k3s](https://k3s.io/) across 2 bare-metal nodes (a repurposed desktop as control-plane, a repurposed laptop as worker), [Calico](https://www.tigera.io/project-calico/) as CNI.
- **Delivery:** [ArgoCD](https://argo-cd.readthedocs.io/) — every workload on the cluster is declared in Git and continuously reconciled, not applied by hand.
- **Registry:** [Harbor](https://goharbor.io/), self-hosted, instead of depending on a public registry.
- **Observability:** `kube-prometheus-stack` (Prometheus + Grafana) and Loki for logs.
- **RAN simulation:** [UERANSIM](https://github.com/aligungr/UERANSIM) for the 5G radio/UE side, exercising real registration, authentication and user-plane traffic against the core.
- **Security layer on top:** default-deny Kubernetes `NetworkPolicy` microsegmentation across the whole core, adversarially validated with an independent breach-and-attack-simulation tool — see [Related projects](#related-projects).

## Why build this

Most hands-on Kubernetes/GitOps portfolios are built on generic web workloads. This project exists to get the same operational experience — GitOps delivery, observability, network security — against a workload that follows real standards on both sides of the stack: 3GPP-defined signaling (NGAP, PFCP, GTP, Diameter) and a Service-Based Architecture with dynamic NF discovery on the telecom side, and CNCF-defined cloud-native patterns (Kubernetes-native orchestration, GitOps continuous delivery) on the platform side — not simplified stand-ins for either.

## Architecture

![Architecture diagram: a Git repo feeds ArgoCD, which reconciles a k3s cluster running Calico CNI. The open5gs namespace hosts the 5G Core SBA network functions and the 4G EPC network functions, interworking over Diameter and GTP-C, protected by 25 default-deny NetworkPolicy objects. ArgoCD also manages Harbor and the observability stack. UERANSIM, running as an external process, connects to the 5G Core over NGAP and GTP-U.](./architecture.png)

**Core network functions deployed:**

| Domain | Network Functions |
|---|---|
| 5G Core (SBA) | AMF, AUSF, BSF, NRF, NSSF, PCF, SCP, SMF, UDM, UDR, UPF |
| 4G EPC (interworking) | HSS, MME, PCRF, SGW-C, SGW-U |
| Shared | MongoDB (subscriber data), WebUI |

The 5G Core follows the Service-Based Architecture's own discovery model: Network Functions don't address each other by fixed IP, they discover one another through the NRF (directly, or via the SCP as an indirect-communication proxy, depending on the NF). The 4G EPC interworks with it over Diameter (HSS↔MME, PCRF↔SMF) and GTP-C (MME↔SGW-C/SMF).

## Design decisions worth calling out

- **Real, repurposed hardware, not cloud VMs.** The control-plane node is a decade-old repurposed desktop; the worker is a repurposed laptop. Part of the point of this lab was learning to operate a cluster under real hardware constraints (limited RAM, mismatched CPU instruction sets between nodes) instead of provisioning uniform cloud instances.
- **CNI chosen for what it enables, not just connectivity.** The cluster originally ran Flannel, which provides overlay networking but does not enforce `NetworkPolicy` at all. Calico replaced it specifically to make the security layer possible — validated with zero pod loss during the migration and a full RAN registration cycle run before and after, to separate "did the CNI change break anything" from "do the policies break anything."
- **GitOps discipline, not just GitOps tooling.** Every change to the cluster goes through a branch, a pull request, and a review before merge — direct pushes to the main branch are disabled. ArgoCD is the only thing that applies changes to the live cluster.
- **Configuration mapped from the live cluster, not assumed from generic docs.** When building the network policy layer on top of this platform, every Network Function relationship was confirmed by reading the actual deployed `ConfigMap`/`Deployment`/`Service` objects rather than assuming Open5GS's generic reference architecture — which surfaced several real deviations from the documented default (see the microsegmentation project for details).

## Validated end-to-end

This isn't just a set of Deployments that report `Running` — the full 5G signaling path has been exercised against it with UERANSIM: SCTP/NG association and NG Setup, initial registration and 5G-AKA authentication, PDU Session establishment, and real user-plane traffic (UE → UPF → external network) with zero packet loss. That baseline is what the microsegmentation and breach-simulation work in the related projects was validated against, both before and after each change — to confirm that adding security controls never broke the thing they were protecting.

## Honest current scope

This is a working lab, not a finished product, and it's documented that way:

- 4G radio simulation (via srsRAN) is not functional yet — the 4G EPC Network Functions are deployed and interworking with the 5G side, but there's no live 4G RAN test today, only the 5G RAN path via UERANSIM.
- The two nodes run different k3s versions and have different CPU capabilities (one lacks a newer CPU instruction set that some container images require) — worked around today by being deliberate about which workloads land on which node, with version homogenization as known follow-up work.

## Related projects

- [`networkpolicy-microsegmentation`](../networkpolicy-microsegmentation) — the default-deny `NetworkPolicy` design built on top of this platform.
- [`infection-monkey-validation`](../infection-monkey-validation) — adversarially validating that microsegmentation with an independent breach-and-attack-simulation tool.
- [`cloudflare-zero-trust`](../cloudflare-zero-trust) — perimeter-layer Zero Trust access control for this lab's observability dashboard.

## Credits

- [Open5GS](https://github.com/open5gs/open5gs) — open-source 5G/4G mobile core.
- [k3s](https://k3s.io/) — lightweight Kubernetes distribution.
- [Calico](https://www.tigera.io/project-calico/) — CNI and network policy enforcement.
- [ArgoCD](https://argo-cd.readthedocs.io/) — GitOps continuous delivery.
- [UERANSIM](https://github.com/aligungr/UERANSIM) — open-source 5G UE/RAN simulator.
- [Harbor](https://goharbor.io/) — self-hosted container registry.
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts) and [Loki](https://grafana.com/oss/loki/) — observability.
