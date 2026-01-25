# The Lean LLM-as-a-Service

This repo provides a production-style, CPU-only LLM API stack using:
- `llama.cpp` server for inference (OpenAI-compatible API + Prometheus metrics)
- Nginx for rate limiting and request logging
- Prometheus + Grafana + Alertmanager for monitoring and alerting

## Step A: Provision the server

1. Create a VM on cloud (4GB RAM / 2 vCPU)
2. Add your SSH key, then SSH in:
   - `ssh root@YOUR_DROPLET_IP`
3. Set up a firewall:
   - `ufw allow OpenSSH`
   - `ufw allow 80/tcp`
   - `ufw allow 3000/tcp`
   - `ufw allow 9090/tcp`
   - `ufw allow 9093/tcp`
   - `ufw enable`
4. Install Docker Engine and the Compose plugin:
   - `apt-get update`
   - `apt-get install -y docker.io docker-compose-plugin`
   - `systemctl enable --now docker`

## Step B: Prepare the model

The compose stack includes a `model-downloader` service that fetches the GGUF model
if it is missing. The file is stored at:
- `./models/Llama-3.2-1B-Instruct-Q4_K_M.gguf`

## Step C: API gateway (rate limiting)

The Nginx configuration is in `nginx/nginx.conf` and enforces:
- 5 requests per minute per IP
- burst up to 10 requests

## Step D: Monitoring

Prometheus scrapes:
- `llama` metrics at `http://llama:8000/metrics`
- node-exporter for CPU/memory on the host
- Nginx request metrics via `nginxlog-exporter`

Grafana is pre-provisioned with a dashboard:
- Prompt vs generation tokens/sec
- CPU usage
- Request load
- p95/p99 request latency
  - Powered by `nginxlog-exporter` histogram metrics

Alertmanager is included for basic alerting rules (high CPU, low memory, high p95/p99).
Edit the rules in `prometheus/alert_rules.yml` as needed.

## Run the stack

From the repo root:

```bash
docker compose up -d
```

If the model does not exist yet, it will be downloaded automatically before the
inference server starts.

## API usage

The gateway listens on port 80.

Example (OpenAI-compatible):

```bash
curl http://YOUR_DROPLET_IP/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}]
  }'
```

Local usage (bypass Nginx):

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}]
  }'
```

Streaming example:

```bash
curl http://YOUR_DROPLET_IP/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
    "stream": true,
    "messages": [{"role": "user", "content": "Stream a short reply."}]
  }'
```

Python example:

```python
import requests

resp = requests.post(
    "http://localhost/v1/chat/completions",
    json={
        "model": "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
        "messages": [{"role": "user", "content": "Say hello in one sentence."}],
        "temperature": 0.7,
    },
    timeout=60,
)
print(resp.json()["choices"][0]["message"]["content"])
```

## Performance check

```bash
./scripts/llm_perf_check.sh
```

## Benchmark suite

```bash
python3 ./scripts/llm_benchmark.py --requests 20 --concurrency 4 --max-tokens 128
```

Outputs:
- `benchmark.json`
- `benchmark.csv`

Tip: the Nginx gateway enforces rate limits. For heavy benchmarks, target the model
directly instead:

```bash
python3 ./scripts/llm_benchmark.py --base-url http://localhost:8000 --requests 20 --concurrency 4
```

## Model catalog

The catalog is exposed at:
- `http://YOUR_DROPLET_IP/models.json`

## Health endpoints

- Nginx: `http://YOUR_DROPLET_IP/health`
- Prometheus: `http://YOUR_DROPLET_IP:9090/-/healthy`
- Grafana: `http://YOUR_DROPLET_IP:3000/api/health`
- Alertmanager: `http://YOUR_DROPLET_IP:9093/-/healthy`
- Llama metrics: `http://YOUR_DROPLET_IP:8000/metrics` (direct access)

## Grafana

Visit `http://YOUR_DROPLET_IP:3000` and log in:
- user: `admin`
- pass: `admin`

