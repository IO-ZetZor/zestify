#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: $0 PID [DURATION_SECONDS]" >&2
    exit 2
fi

pid=$1
duration=${2:-60}
if ! [[ "$pid" =~ ^[0-9]+$ ]] || [ ! -d "/proc/$pid" ]; then
    echo "error: no process with pid $pid" >&2
    exit 1
fi
if ! [[ "$duration" =~ ^[0-9]+$ ]] || [ "$duration" -lt 1 ]; then
    echo "error: duration must be a positive integer" >&2
    exit 1
fi

clk_tck=$(getconf CLK_TCK)
page_size=$(getconf PAGESIZE 2>/dev/null || echo 4096)

read_cpu_ticks() {
    awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null || echo 0
}

prev_ticks=$(read_cpu_ticks)
prev_ns=$(date +%s%N)

for _ in $(seq 1 "$duration"); do
    sleep 1
    if [ ! -d "/proc/$pid" ]; then
        echo "process $pid exited"
        exit 1
    fi

    ticks=$(read_cpu_ticks)
    now_ns=$(date +%s%N)
    elapsed_ns=$((now_ns - prev_ns))
    delta_ticks=$((ticks - prev_ticks))

    cpu=$(awk -v t="$delta_ticks" -v clk="$clk_tck" -v ns="$elapsed_ns" \
        'BEGIN { printf "%.2f", (t / clk) / (ns / 1000000000) * 100 }')
    rss_kb=$(awk '/VmRSS:/ {print $2}' "/proc/$pid/status" 2>/dev/null || echo 0)
    rss_mb=$(awk -v kb="$rss_kb" 'BEGIN { printf "%.1f", kb / 1024 }')
    children=$(ps -o pid= --ppid "$pid" 2>/dev/null | wc -l | tr -d ' ')

    printf '%s cpu=%s%% rss=%sMB children=%s\n' "$(date +%H:%M:%S)" "$cpu" "$rss_mb" "$children"

    prev_ticks=$ticks
    prev_ns=$now_ns
done
