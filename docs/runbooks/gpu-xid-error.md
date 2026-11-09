# GPUXidError

**Severity**: critical. **Fires when**: `DCGM_FI_DEV_XID_ERRORS` is non-zero for a GPU for
1 minute. The value is the last XID code the driver reported.

## Impact

Depends on the code. Some XIDs are application faults (an illegal memory access in a kernel)
that only kill the offending process; others mean the GPU fell off the bus or the driver
reset it, which kills every Pod using it. The label `pod` on the metric names the workload
that was on the GPU.

## Check

```sh
# the code and the pod
curl -s 'http://127.0.0.1:19090/api/v1/query?query=DCGM_FI_DEV_XID_ERRORS>0'   # after kubectl -n monitoring port-forward svc/monitoring-prometheus 19090:9090
# on the node
dmesg -T | grep -i xid | tail -20
nvidia-smi -q -d PAGE_RETIREMENT,ECC | sed -n '1,60p'
```

NVIDIA's XID catalogue (docs.nvidia.com, "XID Errors") says what each code means; the ones
that matter most here: 13 (graphics engine exception, usually the application), 31 (memory
page fault, usually the application), 43 (reset requested), 45 (preemptive cleanup after a
fault), 48 (double-bit ECC error: hardware), 79 (GPU has fallen off the bus: hardware or
power), 94/95 (contained or uncontained ECC error).

## Fix

- Application codes (13, 31, 43, 45): the workload is at fault. Tell the team which Pod; the
  GPU is fine once the process is gone. Nothing to do on the platform.
- ECC or bus codes (48, 79, 94, 95): drain the node (`kubectl drain <node>
  --ignore-daemonsets --delete-emptydir-data`), reboot, run `nvidia-smi -q -d ECC` again. A
  recurring hardware XID is a support case; keep the node cordoned.

## After

The metric keeps the last code until the next error or a driver reload; the alert resolves
after a reload or reboot. Add the code and the pod to the incident note.
