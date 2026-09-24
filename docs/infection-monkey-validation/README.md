# Validating Kubernetes Microsegmentation with Infection Monkey (Breach & Attack Simulation)

This project is a follow-up to [`networkpolicy-microsegmentation`](../networkpolicy-microsegmentation): instead of only *building* default-deny network microsegmentation on a self-hosted Kubernetes cluster and validating it with my own tests, I put it in front of a real, independent breach-and-attack-simulation tool and let it try to prove me wrong.

## Overview

- **Target:** a self-hosted, 2-node k3s cluster running a full open-source 5G/4G mobile core ([Open5GS](https://github.com/open5gs/open5gs)), protected by 25 default-deny `NetworkPolicy` objects (see the companion project for how those were built).
- **Tool:** [Infection Monkey](https://github.com/guardicore/monkey), an open-source breach-and-attack-simulation platform built and maintained by Akamai (formerly Guardicore), using its built-in **"Network Segmentation"** scenario.
- **Assumption:** worst case for the defender — the simulated agent runs directly on a cluster **node**, outside of Kubernetes' own orchestration (never as a pod), representing an attacker who already has code execution on a machine with real network-layer access to the cluster. No perimeter to cross, no credentials assumed — the only thing standing between that agent and the protected workloads is the policy layer itself.
- **Result:** 0% of scanned machines compromised, 0 exploiters run, 0 credentials stolen, and — after cross-referencing the tool's own findings against the cluster's real pod-to-IP mapping — **zero of the protected core's Network Functions reachable at all.**

## Why simulate the attack instead of just describing the policy

Writing 25 `NetworkPolicy` objects and confirming they block a hand-crafted test pod (see the companion project) proves the mechanism works. It does not prove the mechanism holds up against a tool built specifically to hunt for segmentation gaps, run by an adversary who never has to ask permission. This project closes that gap with independent, adversarial evidence instead of self-graded tests.

## Architecture

![Architecture diagram: Monkey Agent runs bare-metal on the worker node, reports to Monkey Island, scan attempts against the protected open5gs namespace are blocked by NetworkPolicy, while other namespaces outside the policy's scope remain reachable as expected](./architecture.png)

The agent runs as a plain process on the worker node, deliberately **outside** the k3s orchestration layer — a pod would carry its own legitimate labels and identity, which is exactly what the policy set is designed to recognize and trust. Running it bare-metal simulates unauthorized code execution on the node itself, which is the more realistic and more dangerous starting point for an internal attacker.

## Methodology

1. **Scenario configuration** — Infection Monkey's built-in "Network Segmentation Testing" scenario, configured with the two network segments that matter for this test: the physical LAN (where the worker node lives) and the cluster's pod CIDR (where the protected workloads live). No credentials were provided, no exploiters were enabled — this test is specifically about network reachability, not exploitation.
2. **Execution** — the agent propagates from the worker node and attempts to reach every host it can see on both configured segments, recording what responds and on which ports.
3. **Evidence collected** — the tool's own Security Report (PDF), its Infection Map (topology graph of what the agent reached), and the agent's raw structured log (every scan attempt, per target, with response status) — kept as primary evidence rather than relying only on the tool's own summary.
4. **Cross-referencing** — every IP the tool reported as "reachable" was checked against the cluster's real `kubectl get pods -A -o wide` output, to confirm (or disprove) that reachable IPs actually belonged to the protected namespace.

## Findings

Two independent, real issues surfaced during this exercise — this section documents both honestly, including the one that had nothing to do with the policies at all.

**1. An infrastructure bug, unrelated to the policies.** Several workloads were intermittently failing health checks in a way that initially looked like a policy problem. Methodical investigation (ruling out the policies first, then live packet capture, then kernel routing/ARP tables) traced the real cause to the CNI layer: a node's IP autodetection had locked onto the wrong local interface after a temporary outage, silently misrouting inter-node traffic. Fixed at the CNI configuration level — nothing about the `NetworkPolicy` set was at fault, but it's a good example of why "something is unreachable" needs root-causing before it's attributed to a policy.

**2. A genuine microsegmentation gap.** One Network Function was missing from the two `NetworkPolicy` objects that authorize access to the cluster's database — an oversight from the original 25-policy rollout, not a design gap. Found by comparing real logs against the actual policy objects line by line, fixed through a proper branch → pull request → merge flow (the policies are GitOps-managed), and re-validated.

**3. A tool-side quirk, diagnosed rather than worked around blindly.** After a reset, the agent stopped being able to register with the dashboard due to a hardware-identifier conflict between the containerized dashboard and the bare-metal agent running on the same physical machine. Rather than treat this as a blocker, it was root-caused to a specific race condition in how the dashboard's container persists that identifier, which made it possible to get a clean, fully isolated run without the workaround leaving any trace in the final evidence.

## Final validation result

The Security Report from the final, isolated run shows:

- **0%** of discovered machines compromised, **0** credentials stolen, **0** exploiters executed (none were configured — this test measures reachability, not exploitation).
- A list of "reachable" IPs on the pod-CIDR segment — but cross-referencing every single one against the real pod-to-namespace mapping shows **none of them belong to the protected mobile-core namespace.** They are all workloads that were never in scope of the 25-policy set (platform/observability/GitOps tooling running in other namespaces) — expected behavior, not a leak.
- Zero Network Functions of the protected 5G/4G core reachable, scanned successfully, or exploited.
- A clean agent shutdown with no abnormal termination.

In short: an independent, adversarial tool — built by the same organization behind the segmentation product this exercise is modeled on — was pointed at the cluster under the worst realistic assumption for the defender, and the microsegmentation held.

## Evidence

From the final, isolated run — [`evidence/`](./evidence) in this folder:

- [`infection-map.png`](./evidence/infection-map.png) — the tool's own topology graph: the agent's scan attempts fan out from the worker node, no successful exploit paths (no red "Exploit" lines).
- [`security-report.pdf`](./evidence/security-report.pdf) — Monkey Island's generated Security Report: 0% of machines compromised, 0 exploiters run, 0 credentials stolen.
- [`agent-log.log`](./evidence/agent-log.log) — the agent's raw structured log, used to independently verify reachability results rather than relying only on the tool's own summary.

## Related work

- [`networkpolicy-microsegmentation`](../networkpolicy-microsegmentation) — the default-deny `NetworkPolicy` design this project validates.
- [`cloudflare-zero-trust`](../cloudflare-zero-trust) — perimeter-layer Zero Trust access control on the same lab, using Cloudflare Tunnel + Access.

## Credits

- [Infection Monkey](https://github.com/guardicore/monkey) — open-source breach-and-attack-simulation tool, built and maintained by Akamai (formerly Guardicore).
- [Open5GS](https://github.com/open5gs/open5gs) — open-source 5G/4G mobile core, used here as the protected workload.
