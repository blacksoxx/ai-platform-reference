#!/bin/sh
# Proof: a member of team-a can work in team-a and cannot list anything in team-b.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

k wait --for=jsonpath='{.status.phase}'=Active namespace/team-a namespace/team-b --timeout=300s >/dev/null

if k --as=alice --as-group=team-a get pods -n team-a >/dev/null 2>&1; then
  echo "alice (group team-a) can list pods in team-a"
else
  echo "alice (group team-a) cannot list pods in her own namespace"; exit 1
fi

if out=$(k --as=alice --as-group=team-a get pods -n team-b 2>&1); then
  echo "NOT isolated: alice can list pods in team-b"; echo "$out" | sed 's/^/      /'; exit 1
fi
echo "alice (group team-a) is forbidden in team-b"
echo "$out" | head -1 | cut -c1-140 | sed 's/^/      /'

if k --as=alice --as-group=team-a get resourcequota -n team-a >/dev/null 2>&1 \
   && ! k --as=alice --as-group=team-a delete resourcequota team-a -n team-a --dry-run=server >/dev/null 2>&1; then
  echo "alice can read but not remove the team's ResourceQuota"
else
  echo "the ResourceQuota is not protected from the team"; exit 1
fi
