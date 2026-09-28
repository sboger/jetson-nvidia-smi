# jetson-nvidia-smi

A drop-in `nvidia-smi` shim that lets tools like
[SparkDash](https://github.com/MiaAI-Lab/sparkDash) monitor an NVIDIA **Jetson**
(Orin Nano / Orin NX / Xavier / Nano) as a generic `host` GPU node.

Jetson boards run Tegra JetPack Linux and have **no working `nvidia-smi`** —
the stock binary fails with
`NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver`.
This script installs as `/usr/bin/nvidia-smi` and answers the exact query
contract that SparkDash (and other SSH-based monitors) use, returning **live,
responsive** GPU stats.

## Why another nvidia-smi?

The previous shim on the author's Orin Nano faked its numbers:
`gpu_util` was statically `0 %` or `30 %` depending on whether a process named
`llama`/`ollama` was running, and `power.draw` was a hardcoded `3.8 W` /
`13.1 W`. It never tracked real load. This version reads real telemetry so the
dashboard actually moves when the GPU works:

| metric | idle | under load (`qwen2.5:7b` generation) |
|---|---|---|
| `utilization.gpu` | 0 % | 95–100 % |
| `power.draw` | ~7.4 W | ~22 W |
| `temperature.gpu` | ~49 °C | ~58 °C |

## What it reports

| nvidia-smi field | source |
|---|---|
| `utilization.gpu` | GPU engine busy % — kernel load node (`<gpu>/load`/10) |
| `power.draw` | Total board power, W — INA3221 `VDD_IN` rail (`mV×mA`) |
| `power.limit` | configurable constant (`POWER_LIMIT_W`, default 25 W) |
| `temperature.gpu` | GPU thermal zone |
| `memory.total` | Unified-memory pool (`MemTotal`) |
| `memory.used` | GPU/shared memory in use — **nvmap process table** (`/sys/kernel/debug/nvmap/iovmm/maps`) |
| `clocks.current.sm` / `clocks.max.sm` | GPU SM frequency (MHz), devfreq |
| `--query-compute-apps` | processes holding GPU memory (pid, name, MiB) |

### Design notes

* **Fully self-contained — no external services.** Every value is read
  directly from the kernel. The GPU-load node, nvmap process table, INA3221
  rails, GPU thermal zone and devfreq clocks are the *same* sources the
  `jetson-stats`/`jtop` daemon reads, but the shim needs **no jtop, no Python
  packages, no group membership and no daemon** — you can even leave
  `jtop.service` stopped.
* **Fast & stateless.** Reads are sub-millisecond and there is no cache file:
  the 3 nvidia-smi calls SparkDash issues in one poll complete in ~45 ms.
* Run it as **root** (SparkDash SSH user default is `root`) so it can read
  `/sys/kernel/debug/nvmap` and the INA3221 rails.

## Install

On the Jetson (as root):

```bash
sudo install -m 0755 nvidia-smi /usr/bin/nvidia-smi
# or: sudo ./install.sh
```

Requirements: Python 3 (stdlib only). Nothing else.

## SparkDash integration

Add the Jetson to SparkDash's `config/sparks.json` as a **host** node — see
[`config/sparks-example.json`](config/sparks-example.json). SparkDash SSHs to
the host and shells out to `nvidia-smi`; with this shim on the target every
query returns real numbers.

```json
{
  "sparks": [
    {
      "id": "jetson",
      "name": "Jetson Orin Nano",
      "kind": "host",
      "lanIp": "192.0.2.10",
      "ssh": { "host": "192.0.2.10", "user": "root", "auth": "key" },
      "llmPorts": []
    }
  ]
}
```

## CLI

```bash
nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,power.draw,power.limit,clocks.current.sm,clocks.max.sm --format=csv,noheader,nounits
nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits
nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader,nounits
nvidia-smi -L
nvidia-smi -q
nvidia-smi dmon
```

## Known limitations

* **Power is total board power**, not a discrete-GPU rail — Jetson integrates
  CPU+GPU in one package, so `power.draw` reflects the whole SoM (the figure a
  real Jetson `power` dashboard shows).
* **Throttle-reason fields** (`clocks_throttle_reasons.*`) always report
  `Not Active`; JetPack doesn't expose the discrete-GPU throttle register.
* **Unified memory**: `memory.total` is the shared CPU/GPU pool (`MemTotal`)
  and `memory.used` is actual nvmap/GPU allocation, consistent with SparkDash's
  unified-memory handling.

## License

MIT.
