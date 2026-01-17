#!/bin/bash

#===============================================================================
# LLM Server Stress Test Suite for Strix Halo
#===============================================================================
# Tests various load conditions to identify crash triggers on AMD Strix Halo APU.
# Monitors GPU state, memory usage, and logs failures for debugging.
#
# Usage:
#   ./stress-test.sh                      # Run all tests
#   ./stress-test.sh concurrent           # Test concurrent requests
#   ./stress-test.sh sustained            # Sustained load over time
#   ./stress-test.sh burst                # Rapid fire bursts
#   ./stress-test.sh context              # Large context stress
#   ./stress-test.sh memory               # Memory pressure test
#   ./stress-test.sh long-generation      # Long output generation
#   ./stress-test.sh --port 8081          # Specify server port
#===============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/stress-results}"
LOG_FILE="$RESULTS_DIR/stress-test-$(date +%Y%m%d_%H%M%S).log"

# Server configuration
SERVER_HOST="${SERVER_HOST:-localhost}"
SERVER_PORT="${SERVER_PORT:-8081}"
API_URL="http://${SERVER_HOST}:${SERVER_PORT}"

# Test parameters
DEFAULT_TIMEOUT=120
MAX_RETRIES=3

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

#===============================================================================
# Logging
#===============================================================================

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"

    case "$level" in
        INFO)  echo -e "${BLUE}[INFO]${NC} $msg" ;;
        OK)    echo -e "${GREEN}[OK]${NC} $msg" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $msg" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $msg" ;;
        TEST)  echo -e "${MAGENTA}[TEST]${NC} $msg" ;;
    esac
}

print_header() {
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}  $1${NC}" | tee -a "$LOG_FILE"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
}

#===============================================================================
# System Monitoring
#===============================================================================

get_gpu_status() {
    rocm-smi --showuse --showmeminfo vram --showtemp 2>/dev/null | grep -E "(GPU\[|busy|Used|Temperature)" || echo "GPU status unavailable"
}

get_memory_status() {
    free -h | grep Mem | awk '{print "RAM: " $3 " / " $2 " (" $7 " available)"}'
}

get_server_health() {
    local response
    response=$(curl -s --max-time 5 "${API_URL}/health" 2>/dev/null)
    if [[ "$response" == *'"status":"ok"'* ]]; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

log_system_state() {
    local label="${1:-checkpoint}"
    echo "" >> "$LOG_FILE"
    echo "=== System State: $label ===" >> "$LOG_FILE"
    echo "Timestamp: $(date)" >> "$LOG_FILE"
    get_memory_status >> "$LOG_FILE"
    get_gpu_status >> "$LOG_FILE" 2>&1
    echo "Server: $(get_server_health)" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

check_for_gpu_errors() {
    # Check recent kernel messages for GPU errors
    local errors
    errors=$(journalctl -k --since "1 minute ago" --no-pager 2>/dev/null | grep -i -E "(amdgpu.*error|gpu.*reset|wedged|timeout|failed)" | tail -5)
    if [[ -n "$errors" ]]; then
        log ERROR "GPU errors detected in kernel log:"
        echo "$errors" >> "$LOG_FILE"
        echo "$errors"
        return 1
    fi
    return 0
}

wait_for_server() {
    local timeout="${1:-60}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        if [[ "$(get_server_health)" == "healthy" ]]; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}

#===============================================================================
# Request Helpers
#===============================================================================

# Generate a prompt of specified token count (approximate)
generate_prompt() {
    local token_count="$1"
    local word_count=$((token_count * 3 / 4))  # Rough token to word ratio

    # Generate repeating text to reach target size
    local base_text="The quick brown fox jumps over the lazy dog. "
    local result=""
    local words_per_sentence=9
    local sentences_needed=$((word_count / words_per_sentence + 1))

    for ((i=0; i<sentences_needed; i++)); do
        result+="$base_text"
    done

    echo "$result"
}

# Make a completion request and return timing/status
make_request() {
    local prompt="$1"
    local max_tokens="${2:-50}"
    local timeout="${3:-$DEFAULT_TIMEOUT}"

    local start_time=$(date +%s.%N)
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" --max-time "$timeout" \
        -H "Content-Type: application/json" \
        -d "{\"prompt\": \"$prompt\", \"max_tokens\": $max_tokens, \"temperature\": 0.7}" \
        "${API_URL}/v1/completions" 2>&1)

    local curl_exit=$?
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -n -1)

    if [[ $curl_exit -ne 0 ]]; then
        echo "error|$curl_exit|$duration|curl_failed"
        return 1
    elif [[ "$http_code" != "200" ]]; then
        echo "error|$http_code|$duration|http_error"
        return 1
    elif [[ "$body" == *'"error"'* ]]; then
        echo "error|api|$duration|$(echo "$body" | jq -r '.error.message // .error // "unknown"' 2>/dev/null)"
        return 1
    else
        local tokens=$(echo "$body" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
        echo "ok|$http_code|$duration|$tokens"
        return 0
    fi
}

#===============================================================================
# Test Functions
#===============================================================================

test_concurrent_requests() {
    print_header "Test: Concurrent Requests"

    local concurrency_levels=(1 2 4 8 16 32)
    local requests_per_level=10
    local prompt="Write a short poem about technology."
    local max_tokens=100

    for concurrency in "${concurrency_levels[@]}"; do
        log TEST "Testing $concurrency concurrent requests..."
        log_system_state "before_concurrent_$concurrency"

        local success=0
        local failed=0
        local total_time=0
        local start=$(date +%s)

        # Launch concurrent requests
        local pids=()
        local results_file=$(mktemp)

        for ((i=0; i<requests_per_level; i++)); do
            (
                result=$(make_request "$prompt" $max_tokens 120)
                echo "$result" >> "$results_file"
            ) &
            pids+=($!)

            # Limit concurrent processes
            while [[ ${#pids[@]} -ge $concurrency ]]; do
                for pid_idx in "${!pids[@]}"; do
                    if ! kill -0 "${pids[$pid_idx]}" 2>/dev/null; then
                        unset 'pids[pid_idx]'
                    fi
                done
                pids=("${pids[@]}")  # Re-index array
                sleep 0.1
            done
        done

        # Wait for all to complete
        wait

        local end=$(date +%s)
        local wall_time=$((end - start))

        # Count results
        while IFS='|' read -r status code duration tokens; do
            if [[ "$status" == "ok" ]]; then
                ((success++))
                total_time=$(echo "$total_time + $duration" | bc)
            else
                ((failed++))
                log WARN "Request failed: $status|$code|$duration|$tokens"
            fi
        done < "$results_file"
        rm -f "$results_file"

        local avg_time=0
        [[ $success -gt 0 ]] && avg_time=$(echo "scale=2; $total_time / $success" | bc)
        local rps=$(echo "scale=2; $success / $wall_time" | bc 2>/dev/null || echo "0")

        log INFO "Concurrency $concurrency: $success/$requests_per_level succeeded, avg=${avg_time}s, ${rps} req/s"

        # Check for GPU errors
        if ! check_for_gpu_errors; then
            log ERROR "GPU errors detected at concurrency level $concurrency!"
            log_system_state "error_concurrent_$concurrency"
            return 1
        fi

        # Brief pause between levels
        sleep 2
    done

    log OK "Concurrent requests test completed"
    return 0
}

test_sustained_load() {
    print_header "Test: Sustained Load"

    local duration_minutes="${1:-5}"
    local requests_per_minute=30
    local prompt="Explain the concept of machine learning in simple terms."
    local max_tokens=150

    log TEST "Running sustained load for $duration_minutes minutes at ~$requests_per_minute req/min..."
    log_system_state "before_sustained"

    local total_requests=0
    local success=0
    local failed=0
    local start_time=$(date +%s)
    local end_time=$((start_time + duration_minutes * 60))
    local interval=$(echo "scale=2; 60 / $requests_per_minute" | bc)

    while [[ $(date +%s) -lt $end_time ]]; do
        local req_start=$(date +%s.%N)

        result=$(make_request "$prompt" $max_tokens 60)
        IFS='|' read -r status code duration tokens <<< "$result"

        ((total_requests++))
        if [[ "$status" == "ok" ]]; then
            ((success++))
        else
            ((failed++))
            log WARN "Request $total_requests failed: $code - $tokens"
        fi

        # Log progress every 30 seconds
        if [[ $((total_requests % 15)) -eq 0 ]]; then
            local elapsed=$(($(date +%s) - start_time))
            log INFO "Progress: $total_requests requests ($success ok, $failed failed) in ${elapsed}s"

            # Check for GPU errors periodically
            if ! check_for_gpu_errors; then
                log ERROR "GPU errors detected during sustained load!"
                log_system_state "error_sustained"
            fi
        fi

        # Pace requests
        local req_duration=$(echo "$(date +%s.%N) - $req_start" | bc)
        local sleep_time=$(echo "$interval - $req_duration" | bc)
        if [[ $(echo "$sleep_time > 0" | bc) -eq 1 ]]; then
            sleep "$sleep_time"
        fi
    done

    log_system_state "after_sustained"
    local success_rate=$(echo "scale=1; $success * 100 / $total_requests" | bc)
    log OK "Sustained load complete: $success/$total_requests (${success_rate}%) over $duration_minutes minutes"

    return 0
}

test_burst_requests() {
    print_header "Test: Burst Requests"

    local burst_sizes=(5 10 20 50)
    local prompt="What is 2+2?"
    local max_tokens=20

    for burst_size in "${burst_sizes[@]}"; do
        log TEST "Firing burst of $burst_size requests..."
        log_system_state "before_burst_$burst_size"

        local pids=()
        local results_file=$(mktemp)
        local start=$(date +%s.%N)

        # Fire all requests simultaneously
        for ((i=0; i<burst_size; i++)); do
            (make_request "$prompt" $max_tokens 60 >> "$results_file") &
            pids+=($!)
        done

        # Wait for all
        wait

        local end=$(date +%s.%N)
        local wall_time=$(echo "$end - $start" | bc)

        # Count results
        local success=0
        local failed=0
        while IFS='|' read -r status code duration tokens; do
            [[ "$status" == "ok" ]] && ((success++)) || ((failed++))
        done < "$results_file"
        rm -f "$results_file"

        log INFO "Burst $burst_size: $success/$burst_size succeeded in ${wall_time}s"

        if ! check_for_gpu_errors; then
            log ERROR "GPU errors detected after burst of $burst_size!"
            log_system_state "error_burst_$burst_size"
            return 1
        fi

        sleep 3
    done

    log OK "Burst requests test completed"
    return 0
}

test_large_context() {
    print_header "Test: Large Context Stress"

    # Test increasingly large prompts
    local context_sizes=(100 500 1000 2000 3000)
    local max_tokens=50

    for size in "${context_sizes[@]}"; do
        log TEST "Testing with ~$size token prompt..."
        log_system_state "before_context_$size"

        local prompt=$(generate_prompt $size)
        prompt+=" Summarize the above text in one sentence."

        local result
        result=$(make_request "$prompt" $max_tokens 180)
        IFS='|' read -r status code duration tokens <<< "$result"

        if [[ "$status" == "ok" ]]; then
            log OK "Context $size tokens: completed in ${duration}s"
        else
            log ERROR "Context $size tokens: failed - $code ($tokens)"
            log_system_state "error_context_$size"
        fi

        if ! check_for_gpu_errors; then
            log ERROR "GPU errors detected with context size $size!"
            return 1
        fi

        sleep 2
    done

    log OK "Large context test completed"
    return 0
}

test_long_generation() {
    print_header "Test: Long Generation"

    # Test generating increasingly long outputs
    local generation_lengths=(100 250 500 1000 2000)
    local prompt="Write a detailed story about a robot learning to paint. Include character development, plot twists, and a meaningful conclusion. Be creative and thorough."

    for length in "${generation_lengths[@]}"; do
        log TEST "Testing generation of $length tokens..."
        log_system_state "before_gen_$length"

        local timeout=$((length / 2 + 60))  # Rough estimate
        local result
        result=$(make_request "$prompt" $length $timeout)
        IFS='|' read -r status code duration tokens <<< "$result"

        if [[ "$status" == "ok" ]]; then
            local tps=$(echo "scale=1; $tokens / $duration" | bc 2>/dev/null || echo "?")
            log OK "Generated $tokens tokens in ${duration}s (${tps} t/s)"
        else
            log ERROR "Generation $length failed: $code ($tokens)"
            log_system_state "error_gen_$length"
        fi

        if ! check_for_gpu_errors; then
            log ERROR "GPU errors detected during $length token generation!"
            return 1
        fi

        sleep 3
    done

    log OK "Long generation test completed"
    return 0
}

test_memory_pressure() {
    print_header "Test: Memory Pressure"

    log TEST "Testing memory pressure with parallel large requests..."
    log_system_state "before_memory_pressure"

    # Large prompts + long generations in parallel
    local parallel_count=4
    local prompt=$(generate_prompt 1000)
    prompt+=" Analyze this text thoroughly and provide detailed insights."
    local max_tokens=500

    local pids=()
    local results_file=$(mktemp)

    log INFO "Launching $parallel_count parallel heavy requests..."

    for ((i=0; i<parallel_count; i++)); do
        (
            result=$(make_request "$prompt" $max_tokens 300)
            echo "worker_$i|$result" >> "$results_file"
        ) &
        pids+=($!)
    done

    # Monitor while waiting
    local check_interval=10
    while true; do
        local still_running=0
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                ((still_running++))
            fi
        done

        if [[ $still_running -eq 0 ]]; then
            break
        fi

        log INFO "Waiting... $still_running workers still running"
        get_memory_status

        if ! check_for_gpu_errors; then
            log ERROR "GPU errors during memory pressure test!"
            log_system_state "error_memory_pressure"
        fi

        sleep $check_interval
    done

    wait

    # Analyze results
    local success=0
    local failed=0
    while IFS='|' read -r worker status code duration tokens; do
        if [[ "$status" == "ok" ]]; then
            ((success++))
            log OK "$worker completed in ${duration}s"
        else
            ((failed++))
            log ERROR "$worker failed: $code"
        fi
    done < "$results_file"
    rm -f "$results_file"

    log_system_state "after_memory_pressure"
    log INFO "Memory pressure test: $success/$parallel_count succeeded"

    return 0
}

test_rapid_reconnect() {
    print_header "Test: Rapid Reconnect"

    log TEST "Testing rapid connection cycling..."

    local cycles=50
    local success=0
    local failed=0

    for ((i=1; i<=cycles; i++)); do
        # Quick health check
        if curl -s --max-time 2 "${API_URL}/health" | grep -q '"status":"ok"'; then
            ((success++))
        else
            ((failed++))
            log WARN "Health check $i failed"
        fi

        # Very short pause
        sleep 0.1

        if [[ $((i % 10)) -eq 0 ]]; then
            log INFO "Completed $i/$cycles connection cycles"
        fi
    done

    log OK "Rapid reconnect: $success/$cycles successful"

    if ! check_for_gpu_errors; then
        log ERROR "GPU errors after rapid reconnect test!"
        return 1
    fi

    return 0
}

#===============================================================================
# Main
#===============================================================================

show_help() {
    cat << EOF
LLM Server Stress Test Suite

Usage: $0 [test_name] [options]

Tests:
  all              Run all tests (default)
  concurrent       Test concurrent request handling
  sustained        Sustained load over time (default: 5 min)
  burst            Rapid fire request bursts
  context          Large context/prompt stress
  long-generation  Long output generation
  memory           Memory pressure with parallel heavy requests
  reconnect        Rapid connection cycling

Options:
  --port PORT      Server port (default: 8081)
  --host HOST      Server host (default: localhost)
  --duration MIN   Duration for sustained test (default: 5)
  --help           Show this help

Examples:
  $0                           # Run all tests
  $0 concurrent                # Just concurrent test
  $0 sustained --duration 10   # 10 minute sustained load
  $0 --port 8082 burst         # Test server on port 8082

Results are logged to: $RESULTS_DIR/
EOF
}

main() {
    local test_name="all"
    local sustained_duration=5

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)
                SERVER_PORT="$2"
                API_URL="http://${SERVER_HOST}:${SERVER_PORT}"
                shift 2
                ;;
            --host)
                SERVER_HOST="$2"
                API_URL="http://${SERVER_HOST}:${SERVER_PORT}"
                shift 2
                ;;
            --duration)
                sustained_duration="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                test_name="$1"
                shift
                ;;
        esac
    done

    # Setup
    mkdir -p "$RESULTS_DIR"

    print_header "LLM Server Stress Test Suite"
    log INFO "Server: $API_URL"
    log INFO "Log file: $LOG_FILE"
    log INFO "Test: $test_name"

    # Check server is up
    if [[ "$(get_server_health)" != "healthy" ]]; then
        log ERROR "Server at $API_URL is not responding!"
        log ERROR "Start the server first: ./start-llm-server.sh <model_name>"
        exit 1
    fi

    log OK "Server is healthy"
    log_system_state "initial"

    # Run tests
    local failed_tests=()

    case "$test_name" in
        all)
            test_concurrent_requests || failed_tests+=("concurrent")
            test_burst_requests || failed_tests+=("burst")
            test_large_context || failed_tests+=("context")
            test_long_generation || failed_tests+=("long-generation")
            test_memory_pressure || failed_tests+=("memory")
            test_rapid_reconnect || failed_tests+=("reconnect")
            test_sustained_load "$sustained_duration" || failed_tests+=("sustained")
            ;;
        concurrent)
            test_concurrent_requests || failed_tests+=("concurrent")
            ;;
        sustained)
            test_sustained_load "$sustained_duration" || failed_tests+=("sustained")
            ;;
        burst)
            test_burst_requests || failed_tests+=("burst")
            ;;
        context)
            test_large_context || failed_tests+=("context")
            ;;
        long-generation|longgen|generation)
            test_long_generation || failed_tests+=("long-generation")
            ;;
        memory)
            test_memory_pressure || failed_tests+=("memory")
            ;;
        reconnect)
            test_rapid_reconnect || failed_tests+=("reconnect")
            ;;
        *)
            log ERROR "Unknown test: $test_name"
            show_help
            exit 1
            ;;
    esac

    # Final status
    print_header "Test Summary"
    log_system_state "final"

    if [[ ${#failed_tests[@]} -eq 0 ]]; then
        log OK "All tests completed successfully!"
    else
        log ERROR "Failed tests: ${failed_tests[*]}"
    fi

    log INFO "Full log available at: $LOG_FILE"

    # Check for any GPU errors during the entire run
    echo ""
    log INFO "Checking for GPU errors in system log..."
    local recent_errors
    recent_errors=$(journalctl -k --since "30 minutes ago" --no-pager 2>/dev/null | grep -i -E "(amdgpu.*error|gpu.*reset|wedged|MES.*failed)" | tail -10)
    if [[ -n "$recent_errors" ]]; then
        log WARN "GPU errors found in recent kernel log:"
        echo "$recent_errors"
    else
        log OK "No GPU errors found in recent kernel log"
    fi

    return ${#failed_tests[@]}
}

main "$@"
