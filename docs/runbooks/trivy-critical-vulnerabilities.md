# TrivyCriticalVulnerabilities

**Severity**: warning. **Fires when**: a running image has carried critical vulnerabilities
with a fix available for an hour (the operator runs with `ignoreUnfixed`, so unfixable ones
are not counted).

## Impact

No outage. A known, fixable critical CVE is in production; the window to fix it is the
platform's choice, and the alert keeps it visible instead of buried in a report.

## Check

```sh
kubectl get vulnerabilityreports -A -o custom-columns='NS:.metadata.namespace,NAME:.metadata.name,CRIT:.report.summary.criticalCount,HIGH:.report.summary.highCount' | awk '$3>0'
kubectl -n <namespace> get vulnerabilityreport <name> -o json | jq '.report.vulnerabilities[] | select(.severity=="CRITICAL") | {vulnerabilityID, resource, installedVersion, fixedVersion}'
```

The report names the package, the installed version and the fixed version.

## Fix

- A platform image (`ghcr.io/blacksoxx/ai-platform-reference/*`): rebuild from a newer base
  (`images/gpu-probe/Dockerfile` pins Ubuntu by digest; bump the digest), merge, and let
  `images.yml` build, push and sign it. The Deployment follows on its next sync.
- An upstream image (a chart's component): bump the chart version in both overlays of the
  component, or override the image tag in the component's values with the fixed version, and
  record the date and the reason in the values file.
- A tenant image: tell the team; their registry policy and signature policy still apply to
  the rebuilt image.

## After

The report updates on the operator's next scan (`operator.scanJobTTL`, or delete the
VulnerabilityReport to force a rescan); the alert resolves when the critical count is zero.
