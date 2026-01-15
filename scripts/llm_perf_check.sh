#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost}"
MODEL="${MODEL:-Llama-3.2-1B-Instruct-Q4_K_M.gguf}"
PROMPT="${PROMPT:-Write a short sentence about the weather.}"
N="${N:-3}"
OUT_TOKENS="${OUT_TOKENS:-64}"
TEMP="${TEMP:-0.7}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required" >&2
  exit 1
fi

has_jq=0
if command -v jq >/dev/null 2>&1; then
  has_jq=1
fi

sum_total=0
sum_ttfb=0
sum_tps=0

echo "Target: ${BASE_URL}"
echo "Model: ${MODEL}"
echo "Requests: ${N}"
echo

for i in $(seq 1 "${N}"); do
  resp_file="$(mktemp)"

  metrics="$(
    curl -sS -o "${resp_file}" \
      -w "HTTP_CODE:%{http_code}\nTTFB:%{time_starttransfer}\nTOTAL:%{time_total}\n" \
      "${BASE_URL}/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"${MODEL}\",
        \"temperature\": ${TEMP},
        \"max_tokens\": ${OUT_TOKENS},
        \"messages\": [{\"role\": \"user\", \"content\": \"${PROMPT}\"}]
      }"
  )"

  http_code="$(echo "${metrics}" | sed -n 's/^HTTP_CODE://p')"
  ttfb="$(echo "${metrics}" | sed -n 's/^TTFB://p')"
  total="$(echo "${metrics}" | sed -n 's/^TOTAL://p')"

  if [[ "${http_code}" != "200" ]]; then
    echo "Request ${i} failed (HTTP ${http_code}). Response:" >&2
    cat "${resp_file}" >&2
    rm -f "${resp_file}"
    exit 1
  fi

  if [[ "${has_jq}" -eq 1 ]]; then
    completion_tokens="$(jq -r '.usage.completion_tokens // 0' "${resp_file}")"
    tps="$(awk -v t="${completion_tokens}" -v s="${total}" 'BEGIN { if (s > 0) printf "%.2f", t / s; else print "0.00" }')"
    sum_tps="$(awk -v a="${sum_tps}" -v b="${tps}" 'BEGIN { printf "%.6f", a + b }')"
  else
    completion_tokens="n/a"
    tps="n/a"
  fi

  sum_total="$(awk -v a="${sum_total}" -v b="${total}" 'BEGIN { printf "%.6f", a + b }')"
  sum_ttfb="$(awk -v a="${sum_ttfb}" -v b="${ttfb}" 'BEGIN { printf "%.6f", a + b }')"

  echo "Request ${i}: ttfb=${ttfb}s total=${total}s completion_tokens=${completion_tokens} tps=${tps}"
  rm -f "${resp_file}"
done

avg_total="$(awk -v s="${sum_total}" -v n="${N}" 'BEGIN { if (n > 0) printf "%.3f", s / n; else print "0.000" }')"
avg_ttfb="$(awk -v s="${sum_ttfb}" -v n="${N}" 'BEGIN { if (n > 0) printf "%.3f", s / n; else print "0.000" }')"

echo
echo "Average: ttfb=${avg_ttfb}s total=${avg_total}s"
if [[ "${has_jq}" -eq 1 ]]; then
  avg_tps="$(awk -v s="${sum_tps}" -v n="${N}" 'BEGIN { if (n > 0) printf "%.2f", s / n; else print "0.00" }')"
  echo "Average: tps=${avg_tps}"
else
  echo "Install jq to compute tokens/sec."
fi

