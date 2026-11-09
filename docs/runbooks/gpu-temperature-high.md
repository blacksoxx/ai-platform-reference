# GPUTemperatureHigh

**Severity**: warning. **Fires when**: `DCGM_FI_DEV_GPU_TEMP` is above 85 °C for 5 minutes.

## Impact

Above its thermal threshold the GPU lowers its clocks (throttling: inference latency rises,
tokens per second fall), and well above it the driver shuts it down (an XID error and the
loss of every Pod on it). A desktop box in a warm room and a Spark with blocked vents both get
here.

## Check

```sh
# which GPU, which node, which pod
# after: kubectl -n monitoring port-forward svc/monitoring-prometheus 19090:9090
curl -s 'http://127.0.0.1:19090/api/v1/query?query=DCGM_FI_DEV_GPU_TEMP>80'
# on the node
nvidia-smi --query-gpu=temperature.gpu,clocks.sm,clocks.max.sm,power.draw,fan.speed --format=csv   # NVIDIA
sensors; rocm-smi --showtemp --showclocks                                                           # AMD
```

Grafana, GPU folder: temperature, clocks and power over the last hours; a slow climb is the
room, a step is the workload.

## Fix

1. Room or airflow: vents, dust, ambient temperature. The Spark and the Halo are small boxes
   with small fans; keep them clear and cool.
2. Workload: if one Pod drives the GPU at full power continuously, cap its power on the node
   (`nvidia-smi -pl <watts>` on NVIDIA, a hardware decision to record) or move the workload.
3. Repeated alerts on one GPU with normal ambient conditions: fan or paste; a hardware case.

## After

Throttling shows as a drop in `DCGM_FI_DEV_SM_CLOCK`; once temperature falls the clocks
return without action.
