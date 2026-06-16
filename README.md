# The Lean LLM-as-a-Service

A production-style LLM API stack that runs a small quantized model (Llama-3.2-1B) with CPU or NVIDIA GPU inference, complete with monitoring, alerting, and rate limiting.

**Stack:**
- `llama.cpp` server — OpenAI-compatible inference API with built-in Prometheus metrics
- Nginx — API gateway with rate limiting and request logging
- Prometheus + Grafana + Alertmanager — monitoring, dashboards, and alerting
- Node Exporter + Nginxlog Exporter — host and HTTP metrics
- GPU Exporter — NVIDIA VRAM and utilization metrics (GPU mode only)

---

## Quick Start (CPU)

```bash
git clone https://github.com/raghav-potdar/LeanLLM-as-a-service
cd LeanLLM-as-a-service
docker compose up -d
```

The `model-downloader` service fetches `Llama-3.2-1B-Instruct-Q4_K_M.gguf` automatically on first run. The inference server starts once the download completes.

---

## Step A: Provision the server

1. Create a VM (minimum 4 GB RAM / 2 vCPU for CPU mode; 6 GB VRAM GPU for GPU mode)
2. SSH in and open firewall ports:

```bash
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 3000/tcp
ufw allow 9090/tcp
ufw allow 9093/tcp
ufw enable
```

3. Install Docker:

```bash
apt-get update
apt-get install -y docker.io docker-compose-plugin
systemctl enable --now docker
```

---

## Step B: Configuration

Copy the example env file (optional — defaults work out of the box for CPU):

```bash
cp .env.example .env
```

Key variables in `.env`:

| Variable | Default | Description |
|---|---|---|
| `LLAMA_IMAGE` | `ghcr.io/ggml-org/llama.cpp:server` | Inference server image |
| `LLAMA_GPU_LAYERS` | `0` | Layers to offload to GPU (0 = CPU only) |
| `LLAMA_THREADS` | `2` | CPU threads |
| `LLAMA_CTX_SIZE` | `4096` | Context window size (tokens) |
| `LLAMA_PARALLEL` | `1` | Parallel request slots |

---

## Step C: Run the stack

**CPU mode:**

```bash
docker compose up -d
```

**GPU mode (NVIDIA):**

```bash
docker compose -f docker-compose.yaml -f docker-compose.gpu.yml --profile gpu up -d
```

See the [GPU Support](#gpu-support) section below for prerequisites.

**Apply config changes:**

```bash
docker compose up -d                        # CPU
docker compose -f docker-compose.yaml -f docker-compose.gpu.yml --profile gpu up -d  # GPU
```

Docker Compose recreates only containers whose config changed.

---

## API Usage

The gateway listens on port 80. All requests are OpenAI-compatible.

**cURL:**

```bash
curl http://YOUR_SERVER_IP/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}]
  }'
```

**Streaming:**

```bash
curl http://YOUR_SERVER_IP/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama",
    "stream": true,
    "messages": [{"role": "user", "content": "Write a short poem."}]
  }'
```

**Python (openai SDK):**

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost/v1", api_key="none")

response = client.chat.completions.create(
    model="llama",
    messages=[{"role": "user", "content": "Say hello in one sentence."}],
    max_tokens=200
)
print(response.choices[0].message.content)
```

**Python (streaming):**

```python
for chunk in client.chat.completions.create(
    model="llama",
    messages=[{"role": "user", "content": "Write a short poem."}],
    stream=True
):
    print(chunk.choices[0].delta.content or "", end="", flush=True)
```

---

## Rate Limiting

Nginx enforces:
- 5 requests/minute per IP
- Burst up to 10 requests

For benchmarks, target the model directly to bypass rate limits:

```bash
python3 ./scripts/llm_benchmark.py --base-url http://localhost:8000 --requests 20 --concurrency 4
```

---

## Performance Check

Quick latency and TPS check:

```bash
./scripts/llm_perf_check.sh
```

Benchmark suite (outputs `benchmark.json` and `benchmark.csv`):

```bash
python3 ./scripts/llm_benchmark.py --requests 20 --concurrency 4 --max-tokens 128
```

---

## Monitoring

| Service | URL |
|---|---|
| Grafana | `http://YOUR_SERVER_IP:3000` (admin / admin) |
| Prometheus | `http://YOUR_SERVER_IP:9090` |
| Alertmanager | `http://YOUR_SERVER_IP:9093` |

**Grafana dashboard panels:**
- Tokens per second (prompt + generation)
- CPU usage %
- Requests processing vs deferred
- Token counters (rate)
- Request latency p95/p99
- GPU VRAM usage (GPU mode only)
- GPU utilization % (GPU mode only)

**Prometheus scrape jobs:**
- `llama` — inference metrics at `llama:8000/metrics`
- `node-exporter` — host CPU / memory
- `nginxlog-exporter` — HTTP request durations from Nginx access logs
- `gpu-exporter` — NVIDIA VRAM and utilization (active in GPU mode only)

**Alerting rules** (`prometheus/alert_rules.yml`):
- High CPU usage
- Low memory available
- High p95 / p99 request latency

---

## Model Catalog

```bash
curl http://YOUR_SERVER_IP/models.json
```

---

## Health Endpoints

| Service | Endpoint |
|---|---|
| Nginx | `http://YOUR_SERVER_IP/health` |
| Prometheus | `http://YOUR_SERVER_IP:9090/-/healthy` |
| Grafana | `http://YOUR_SERVER_IP:3000/api/health` |
| Alertmanager | `http://YOUR_SERVER_IP:9093/-/healthy` |
| Llama (internal) | `http://llama:8000/metrics` |

---

## GPU Support

### Prerequisites

**1. Install NVIDIA Container Toolkit:**

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-ct.gpg
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -s -L "https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list" \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-ct.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-ct.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

**2. Generate CDI device spec** (required for Docker to map the GPU):

```bash
sudo mkdir -p /etc/cdi
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
```

**3. Add your user to the docker group** (system Docker socket access):

```bash
sudo usermod -aG docker $USER
newgrp docker
```

**4. Verify nvidia runtime is registered:**

```bash
docker info | grep -i runtime
# Should show: Runtimes: ... nvidia ...
```

> If you use Docker Desktop, note that it runs in a VM and does not share the host's `nvidia-container-runtime`. Stop Docker Desktop (`systemctl --user stop docker-desktop`) and use the system Docker daemon (`docker context use default`) for GPU workloads.

### Configure `.env`

```bash
cp .env.example .env
```

Edit `.env` with GPU values:

```env
LLAMA_IMAGE=ghcr.io/ggml-org/llama.cpp:server-cuda
LLAMA_GPU_LAYERS=99
LLAMA_THREADS=4
LLAMA_CTX_SIZE=8192
LLAMA_PARALLEL=4
```

### Run in GPU mode

```bash
docker compose -f docker-compose.yaml -f docker-compose.gpu.yml --profile gpu up -d
```

The `docker-compose.gpu.yml` overlay applies the `nvidia` runtime and `NVIDIA_VISIBLE_DEVICES=all` to both the `llama` and `gpu-exporter` containers. The `--profile gpu` flag activates the GPU exporter service.

### CPU vs GPU comparison

| Setting | CPU (default) | GPU (NVIDIA) |
|---|---|---|
| Image | `llama.cpp:server` | `llama.cpp:server-cuda` |
| `LLAMA_GPU_LAYERS` | `0` | `99` |
| Context size | 4096 | 8192+ |
| Parallel slots | 1 | 4 |
| Expected TPS | ~15–20 | ~80–200+ |
