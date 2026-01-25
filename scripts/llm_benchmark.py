#!/usr/bin/env python3
import argparse
import json
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib import request


def run_request(base_url, model, prompt, max_tokens, temperature):
    payload = {
        "model": model,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }
    data = json.dumps(payload).encode("utf-8")
    req = request.Request(
        f"{base_url}/v1/chat/completions",
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    start = time.time()
    with request.urlopen(req, timeout=120) as resp:
        body = resp.read()
    elapsed = time.time() - start
    parsed = json.loads(body.decode("utf-8"))
    usage = parsed.get("usage", {})
    completion_tokens = usage.get("completion_tokens", 0)
    prompt_tokens = usage.get("prompt_tokens", 0)
    return {
        "elapsed_s": elapsed,
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "tps": (completion_tokens / elapsed) if elapsed > 0 else 0.0,
    }


def main():
    parser = argparse.ArgumentParser(description="Benchmark LLM inference latency and throughput.")
    parser.add_argument("--base-url", default="http://localhost:8000")
    parser.add_argument("--model", default="Llama-3.2-1B-Instruct-Q4_K_M.gguf")
    parser.add_argument("--prompt", default="Write a short sentence about the weather.")
    parser.add_argument("--requests", type=int, default=10)
    parser.add_argument("--concurrency", type=int, default=2)
    parser.add_argument("--max-tokens", type=int, default=64)
    parser.add_argument("--temperature", type=float, default=0.7)
    parser.add_argument("--out-json", default="benchmark.json")
    parser.add_argument("--out-csv", default="benchmark.csv")
    args = parser.parse_args()

    results = []
    with ThreadPoolExecutor(max_workers=args.concurrency) as executor:
        futures = [
            executor.submit(
                run_request,
                args.base_url,
                args.model,
                args.prompt,
                args.max_tokens,
                args.temperature,
            )
            for _ in range(args.requests)
        ]
        for f in as_completed(futures):
            results.append(f.result())

    results.sort(key=lambda r: r["elapsed_s"])
    total = sum(r["elapsed_s"] for r in results)
    avg = total / len(results)
    p95 = results[int(len(results) * 0.95) - 1]["elapsed_s"]
    p99 = results[int(len(results) * 0.99) - 1]["elapsed_s"]
    avg_tps = sum(r["tps"] for r in results) / len(results)

    summary = {
        "requests": args.requests,
        "concurrency": args.concurrency,
        "avg_latency_s": round(avg, 4),
        "p95_latency_s": round(p95, 4),
        "p99_latency_s": round(p99, 4),
        "avg_tps": round(avg_tps, 2),
    }

    with open(args.out_json, "w", encoding="utf-8") as f:
        json.dump({"summary": summary, "results": results}, f, indent=2)

    with open(args.out_csv, "w", encoding="utf-8") as f:
        f.write("elapsed_s,prompt_tokens,completion_tokens,tps\n")
        for r in results:
            f.write(
                f"{r['elapsed_s']:.4f},{r['prompt_tokens']},{r['completion_tokens']},{r['tps']:.2f}\n"
            )

    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
