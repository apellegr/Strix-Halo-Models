#!/bin/bash

#===============================================================================
# Batch Size Sweep - Performance vs Stability Testing
#===============================================================================
# Tests different batch sizes to find optimal balance between speed and stability.
# For each batch size: measures performance, then runs stability test.
#
# Usage:
#   ./batch-size-sweep.sh                    # Test default batch sizes
#   ./batch-size-sweep.sh 128 256 512 1024   # Test specific batch sizes
#===============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/sweep-results}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RESULTS_FILE="$RESULTS_DIR/batch-sweep-$TIMESTAMP.csv"
REPORT_FILE="$RESULTS_DIR/batch-sweep-$TIMESTAMP.md"

# Server configuration
SERVER_PORT="${SERVER_PORT:-8081}"
MODEL_NAME="${MODEL_NAME:-qwen3-235b-thinking}"
CONFIG_FILE="$SCRIPT_DIR/model-configs.json"

# Test parameters
PERF_PROMPT="Write a detailed technical explanation of how neural networks learn through backpropagation. Include the mathematical foundations and practical considerations."
PERF_MAX_TOKENS=200
PERF_RUNS=3

STABILITY_BURST_SIZE=20
STABILITY_CONCURRENT=16
STABILITY_TIMEOUT=120

# Default batch sizes to test
DEFAULT_BATCH_SIZES=(128 256 384 512 768 1024)

#===============================================================================
# Colors
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

#===============================================================================
# Server Management
#===============================================================================

update_batch_size() {
    local batch_size=$1

    # Update the config file
    local tmp_file=$(mktemp)
    jq ".models[\"$MODEL_NAME\"].batch_size = $batch_size" "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
}

restart_server() {
    local batch_size=$1

    log "Stopping current server..."
    ./start-llm-server.sh stop "$MODEL_NAME" >/dev/null 2>&1
    sleep 3

    log "Updating batch_size to $batch_size..."
    update_batch_size "$batch_size"

    log "Starting server with batch_size=$batch_size..."
    ./start-llm-server.sh "$MODEL_NAME" "$SERVER_PORT" >/dev/null 2>&1

    # Wait for server to be ready
    local timeout=300
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s "http://localhost:$SERVER_PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then
            log_ok "Server ready with batch_size=$batch_size"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_error "Server failed to start with batch_size=$batch_size"
    return 1
}

#===============================================================================
# Performance Testing
#===============================================================================

measure_performance() {
    local batch_size=$1

    echo "  Measuring performance..." >&2

    local total_prompt_time=0
    local total_gen_time=0
    local total_prompt_tokens=0
    local total_gen_tokens=0
    local successful_runs=0

    for ((run=1; run<=PERF_RUNS; run++)); do
        local start_time=$(date +%s.%N)

        local response
        response=$(curl -s --max-time 180 \
            -H "Content-Type: application/json" \
            -d "{\"prompt\": \"$PERF_PROMPT\", \"max_tokens\": $PERF_MAX_TOKENS, \"temperature\": 0.7}" \
            "http://localhost:$SERVER_PORT/v1/completions" 2>&1)

        local end_time=$(date +%s.%N)

        if echo "$response" | jq -e '.choices[0].text' >/dev/null 2>&1; then
            local duration=$(echo "$end_time - $start_time" | bc)
            local prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
            local gen_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')

            total_prompt_tokens=$((total_prompt_tokens + prompt_tokens))
            total_gen_tokens=$((total_gen_tokens + gen_tokens))
            total_prompt_time=$(echo "$total_prompt_time + $duration" | bc)
            ((successful_runs++))

            echo "    Run $run: ${gen_tokens} tokens in ${duration}s" >&2
        else
            echo "    Run $run: Failed" >&2
        fi

        sleep 1
    done

    if [[ $successful_runs -gt 0 ]]; then
        local avg_time=$(echo "scale=2; $total_prompt_time / $successful_runs" | bc)
        local avg_gen_tokens=$(echo "scale=0; $total_gen_tokens / $successful_runs" | bc)
        local tokens_per_sec=$(echo "scale=2; $total_gen_tokens / $total_prompt_time" | bc)

        echo "$tokens_per_sec|$avg_time|$avg_gen_tokens|$successful_runs"
    else
        echo "0|0|0|0"
    fi
}

#===============================================================================
# Stability Testing
#===============================================================================

check_gpu_errors() {
    journalctl -k --since "2 minutes ago" --no-pager 2>/dev/null | \
        grep -c -i -E "(amdgpu.*error|gpu.*reset|wedged|MES.*failed)" || echo "0"
}

test_stability() {
    local batch_size=$1

    echo "  Testing stability..." >&2

    # Clear any recent GPU errors from consideration
    sleep 2

    local initial_errors=$(check_gpu_errors)

    # Burst test
    echo "    Running burst test ($STABILITY_BURST_SIZE requests)..." >&2
    local burst_success=0
    local burst_pids=()
    local burst_results=$(mktemp)

    for ((i=0; i<STABILITY_BURST_SIZE; i++)); do
        (
            result=$(curl -s --max-time $STABILITY_TIMEOUT \
                -H "Content-Type: application/json" \
                -d '{"prompt": "Hello", "max_tokens": 20}' \
                "http://localhost:$SERVER_PORT/v1/completions" 2>&1)
            if echo "$result" | grep -q '"choices"'; then
                echo "ok"
            else
                echo "fail"
            fi
        ) >> "$burst_results" &
        burst_pids+=($!)
    done

    wait
    burst_success=$(grep -c "ok" "$burst_results" || echo "0")
    rm -f "$burst_results"

    # Check for GPU errors after burst
    sleep 2
    local post_burst_errors=$(check_gpu_errors)
    local burst_errors=$((post_burst_errors - initial_errors))
    [[ $burst_errors -lt 0 ]] && burst_errors=0

    # Concurrent test
    echo "    Running concurrent test ($STABILITY_CONCURRENT parallel)..." >&2
    local concurrent_success=0
    local concurrent_results=$(mktemp)

    for ((i=0; i<STABILITY_CONCURRENT; i++)); do
        (
            result=$(curl -s --max-time $STABILITY_TIMEOUT \
                -H "Content-Type: application/json" \
                -d '{"prompt": "Explain briefly:", "max_tokens": 50}' \
                "http://localhost:$SERVER_PORT/v1/completions" 2>&1)
            if echo "$result" | grep -q '"choices"'; then
                echo "ok"
            else
                echo "fail"
            fi
        ) >> "$concurrent_results" &
    done

    wait
    concurrent_success=$(grep -c "ok" "$concurrent_results" || echo "0")
    rm -f "$concurrent_results"

    # Final GPU error check
    sleep 2
    local final_errors=$(check_gpu_errors)
    local total_gpu_errors=$((final_errors - initial_errors))
    [[ $total_gpu_errors -lt 0 ]] && total_gpu_errors=0

    # Determine stability rating
    local stability="STABLE"
    if [[ $total_gpu_errors -gt 0 ]]; then
        stability="CRASHED"
    elif [[ $burst_success -lt $STABILITY_BURST_SIZE || $concurrent_success -lt $STABILITY_CONCURRENT ]]; then
        stability="DEGRADED"
    fi

    echo "$burst_success/$STABILITY_BURST_SIZE|$concurrent_success/$STABILITY_CONCURRENT|$total_gpu_errors|$stability"
}

#===============================================================================
# Main
#===============================================================================

main() {
    local batch_sizes=("${@:-${DEFAULT_BATCH_SIZES[@]}}")

    mkdir -p "$RESULTS_DIR"

    print_header "Batch Size Sweep: Performance vs Stability"

    log "Model: $MODEL_NAME"
    log "Batch sizes to test: ${batch_sizes[*]}"
    log "Results will be saved to: $RESULTS_FILE"
    echo ""

    # Save original batch size
    local original_batch=$(jq -r ".models[\"$MODEL_NAME\"].batch_size" "$CONFIG_FILE")
    log "Original batch_size: $original_batch"

    # Initialize results file
    echo "batch_size,tokens_per_sec,avg_response_time,burst_test,concurrent_test,gpu_errors,stability" > "$RESULTS_FILE"

    # Initialize report
    cat > "$REPORT_FILE" << EOF
# Batch Size Sweep Results

**Model:** $MODEL_NAME
**Date:** $(date)
**System:** AMD Ryzen AI Max+ 395 (Strix Halo)

## Test Parameters
- Performance: $PERF_RUNS runs, $PERF_MAX_TOKENS tokens each
- Stability Burst: $STABILITY_BURST_SIZE simultaneous requests
- Stability Concurrent: $STABILITY_CONCURRENT parallel requests

## Results

| Batch Size | Tokens/sec | Avg Time | Burst Test | Concurrent | GPU Errors | Stability |
|------------|------------|----------|------------|------------|------------|-----------|
EOF

    # Test each batch size
    for batch_size in "${batch_sizes[@]}"; do
        print_header "Testing batch_size=$batch_size"

        if ! restart_server "$batch_size"; then
            log_error "Failed to start server with batch_size=$batch_size, skipping..."
            echo "$batch_size,0,0,0/0,0/0,0,FAILED" >> "$RESULTS_FILE"
            echo "| $batch_size | - | - | - | - | - | FAILED |" >> "$REPORT_FILE"
            continue
        fi

        # Performance test
        local perf_result
        perf_result=$(measure_performance "$batch_size")
        IFS='|' read -r tps avg_time avg_tokens runs <<< "$perf_result"

        log_ok "Performance: ${tps} tok/s (avg ${avg_time}s, $runs/$PERF_RUNS runs)"

        # Stability test
        local stability_result
        stability_result=$(test_stability "$batch_size")
        IFS='|' read -r burst concurrent gpu_errors stability <<< "$stability_result"

        if [[ "$stability" == "STABLE" ]]; then
            log_ok "Stability: $stability (burst: $burst, concurrent: $concurrent, GPU errors: $gpu_errors)"
        elif [[ "$stability" == "CRASHED" ]]; then
            log_error "Stability: $stability (burst: $burst, concurrent: $concurrent, GPU errors: $gpu_errors)"
        else
            log_warn "Stability: $stability (burst: $burst, concurrent: $concurrent, GPU errors: $gpu_errors)"
        fi

        # Save results
        echo "$batch_size,$tps,$avg_time,$burst,$concurrent,$gpu_errors,$stability" >> "$RESULTS_FILE"
        echo "| $batch_size | $tps | ${avg_time}s | $burst | $concurrent | $gpu_errors | $stability |" >> "$REPORT_FILE"

        # Brief pause between tests
        sleep 5
    done

    # Add summary to report
    cat >> "$REPORT_FILE" << EOF

## Recommendations

Based on the sweep results, choose a batch size that:
1. Has STABLE status (no GPU crashes)
2. Maximizes tokens/sec for your workload
3. Handles your expected concurrent load

Note: Lower batch sizes are more stable but may have slower prompt processing.
Higher batch sizes process prompts faster but risk GPU scheduler crashes under load.

## Raw Data
See: $(basename "$RESULTS_FILE")
EOF

    # Restore original batch size
    print_header "Restoring Configuration"
    log "Restoring original batch_size=$original_batch..."
    restart_server "$original_batch"

    # Print summary
    print_header "Sweep Complete"
    echo ""
    cat "$RESULTS_FILE" | column -t -s','
    echo ""
    log_ok "Results saved to: $RESULTS_FILE"
    log_ok "Report saved to: $REPORT_FILE"
}

main "$@"
