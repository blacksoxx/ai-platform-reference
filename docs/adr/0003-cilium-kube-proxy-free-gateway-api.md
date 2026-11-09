# ADR 0003: Cilium without kube-proxy, Gateway API as the only entry point

**Status**: accepted, 2026-11-09

## Context

The lab nodes host other services on ports 80 and 443, tenants must be isolated at the
network level with evidence, and inference needs a reachable, TLS-terminated front door.
Options for the entry point: an ingress controller (ingress-nginx, Traefik), a separate
Gateway API implementation (Envoy Gateway), or Cilium's own Gateway API support. Options for
policy visibility: Kubernetes NetworkPolicy with any CNI, or Cilium policies with Hubble.

## Decision

Cilium is the CNI in both environments, with `kubeProxyReplacement: true` (a prerequisite of
its Gateway API support), Hubble, L2 announcements and LB-IPAM. One Gateway (class `cilium`)
is the only entry point; HTTPRoutes attach from any namespace. No ingress controller is
installed; RKE2's packaged one is turned off (`ingress-controller: none`). Tenant isolation is
expressed as `CiliumNetworkPolicy` and shown in Hubble. The Gateway API CRDs are the exact
version Cilium 1.20 documents (v1.6.3), applied by the bootstrap before Cilium.

## Consequences

- One networking component for CNI, service load balancing, policy, flow visibility and L7
  routing; one place to look when traffic does not flow.
- The Gateway's address comes from a pool announced with ARP: trivial on a kind network and
  on a lab LAN, not usable across routed networks without BGP (Cilium supports it).
- kube-proxy-free mode needs a kernel of 5.8 or newer and the API server address at install
  time (`k8sServiceHost`), which the bootstrap scripts handle.
- Routes must live with the Gateway Application: a route is only Healthy once a Gateway has
  accepted it, which shaped the sync-wave layout (architecture.md, section 3).
