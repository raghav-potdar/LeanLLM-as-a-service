# The Lean LLM-as-a-Service

This repo provides a production-style, CPU-only LLM API stack using:
- `llama-cpp-python` for inference (OpenAI-compatible API)
- Nginx for rate limiting
- Prometheus + Grafana for monitoring

## Step A: Provision the server

1. Create a DigitalOcean droplet (Premium Intel, Ubuntu).
2. Add your SSH key in the DigitalOcean UI, then SSH in:
   - `ssh root@YOUR_DROPLET_IP`
3. Set up a firewall:
   - `ufw allow OpenSSH`
   - `ufw allow 80/tcp`
   - `ufw allow 3000/tcp`
   - `ufw allow 9090/tcp`
   - `ufw enable`
4. Install Docker Engine and the Compose plugin:
   - `apt-get update`
   - `apt-get install -y docker.io docker-compose-plugin`
   - `systemctl enable --now docker`

## Step B: Prepare the model

1. Download the `Llama-3.2-1B-Instruct` GGUF model from Hugging Face.
2. Place it at:
   - `/home/madmax/Documents/Projects/LeanLLM-as-a-service/models/llama-3.2-1b-instruct.gguf`

## Step C: API gateway (rate limiting)

The Nginx configuration is in `nginx/nginx.conf` and enforces:
- 5 requests per minute per IP
- burst up to 10 requests

## Step D: Monitoring

Prometheus scrapes:
- `llama` metrics at `/metrics`
- node-exporter for CPU/memory on the host

Grafana is pre-provisioned with a dashboard:
- Tokens per second
- CPU usage

If the token metric name differs in your `llama-cpp-python` build, update the query in:
- `grafana/dashboards/llm.json`

## Run the stack

From the repo root:

```bash
docker compose up -d
```

## API usage

The gateway listens on port 80.

Example (OpenAI-compatible):

```bash
curl http://YOUR_DROPLET_IP/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama-3.2-1b-instruct",
    "messages": [{"role": "user", "content": "Say hello in one sentence."}]
  }'
```

## Grafana

Visit `http://YOUR_DROPLET_IP:3000` and log in:
- user: `admin`
- pass: `admin`

