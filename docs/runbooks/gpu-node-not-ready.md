# GPUNodeNotReady

**Severity**: critical. **Fires when**: a node that advertises `nvidia.com/gpu` or
`amd.com/gpu` has had `Ready=false` for 5 minutes.

## Impact

Every GPU workload on that node is stopped or stuck; new GPU Pods for that vendor queue in
KAI until the node returns. Inference loses the backend on that node (InferenceBackendDown
follows).

## Check

```sh
kubectl get node <node> -o wide
kubectl describe node <node> | sed -n '/Conditions:/,/Addresses:/p'
kubectl get events --field-selector involvedObject.name=<node> --sort-by=.lastTimestamp | tail -20
```

On the node (ssh): `systemctl status rke2-agent`, `journalctl -u rke2-agent -n 100`,
`nvidia-smi` (NVIDIA) or `ls /dev/kfd /dev/dri` (AMD), disk and memory pressure
(`df -h`, `free -g`).

## Fix

1. Kubelet or runtime down: `systemctl restart rke2-agent`; if containerd is wedged, reboot
   the node. Pods reschedule when the node is Ready.
2. Node unreachable: check the network path (Tailscale or LAN), then the host itself.
3. Driver fault: `dmesg | grep -i -E 'nvrm|xid|amdgpu'`; a driver that cannot recover needs a
   reboot. For repeated XID errors see [gpu-xid-error.md](gpu-xid-error.md).
4. Resource pressure: find the consumer with `crictl stats` on the node, evict it, and set
   limits for it in Git.

## After

If the node was down for long, check that the KAI queues drained (`kubectl get pods -A -l
kai.scheduler/queue --field-selector=status.phase=Pending`) and that inference is back on
both backends (dashboard Inference, "Backends up").
