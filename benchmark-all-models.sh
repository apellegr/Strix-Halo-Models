#!/bin/bash

#===============================================================================
# Model Benchmark Script for Strix Halo
#===============================================================================
# Benchmarks all GGUF models and generates a comprehensive report.
#
# Usage:
#   ./benchmark-all-models.sh              # Benchmark all models
#   ./benchmark-all-models.sh --fast       # Skip massive models (>50GB)
#   ./benchmark-all-models.sh --category fast  # Only benchmark 'fast' category
#   ./benchmark-all-models.sh --skip-vision    # Skip vision models
#===============================================================================

set -euo pipefail

#===============================================================================
# Configuration
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${MODELS_DIR:-/home/apellegr/Strix-Halo-Models/models}"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/benchmarks}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/benchmark_${TIMESTAMP}.csv"
REPORT_FILE="${OUTPUT_DIR}/benchmark_${TIMESTAMP}.md"

# Binary paths
LLAMA_BENCH="${LLAMA_BENCH:-$HOME/.local/bin/llama-bench}"

# Benchmark settings
GPU_LAYERS=999
THREADS=$(nproc)

# Environment
export LD_LIBRARY_PATH="$HOME/.local/lib:${LD_LIBRARY_PATH:-}"
[ -f ~/.rocm-env.sh ] && source ~/.rocm-env.sh

# Filters
SKIP_MASSIVE=false
SKIP_VISION=false
CATEGORY_FILTER=""
MAX_SIZE_GB=100
LIST_ONLY=false

#===============================================================================
# Colors
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

#===============================================================================
# Helper Functions
#===============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}$1${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_model_size_gb() {
    local file=$1
    local size_bytes

    # Check if it's a split model
    if [[ "$file" =~ -00001-of-[0-9]+\.gguf$ ]]; then
        local dir=$(dirname "$file")
        local base=$(basename "$file" | sed 's/-00001-of-[0-9]*\.gguf$//')
        size_bytes=$(find "$dir" -name "${base}*.gguf" -type f -exec stat -c%s {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')
    else
        size_bytes=$(stat -c%s "$file" 2>/dev/null || echo 0)
    fi

    awk "BEGIN {printf \"%.2f\", ${size_bytes:-0}/1073741824}"
}

#===============================================================================
# Main
#===============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                echo "Usage: $0 [--fast] [--skip-vision] [--category CAT] [--max-size GB] [--list]"
                exit 0
                ;;
            --fast) SKIP_MASSIVE=true; shift ;;
            --skip-vision) SKIP_VISION=true; shift ;;
            --category) CATEGORY_FILTER="$2"; shift 2 ;;
            --max-size) MAX_SIZE_GB="$2"; shift 2 ;;
            --list) LIST_ONLY=true; shift ;;
            *) print_error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

main() {
    parse_args "$@"

    print_header "Strix Halo Model Benchmark Suite"

    # Check for llama-bench
    if [[ ! -x "$LLAMA_BENCH" ]]; then
        print_error "llama-bench not found at $LLAMA_BENCH"
        exit 1
    fi

    # Find models
    print_info "Discovering models in $MODELS_DIR..."

    declare -a model_files=()
    declare -a model_names=()
    declare -a model_categories=()
    declare -a model_sizes=()

    while IFS= read -r model_file; do
        [[ -z "$model_file" ]] && continue

        # Skip split model parts (only keep first)
        [[ "$model_file" =~ -0000[2-9]-of- ]] && continue
        [[ "$model_file" =~ -000[1-9][0-9]-of- ]] && continue

        # Skip mmproj files
        [[ "$model_file" =~ mmproj ]] && continue

        local category=$(basename "$(dirname "$(dirname "$model_file")")")
        local model_name=$(basename "$(dirname "$model_file")")
        local size_gb=$(get_model_size_gb "$model_file")

        # Apply filters
        $SKIP_VISION && [[ "$category" == "vision" ]] && continue
        $SKIP_MASSIVE && (( $(echo "$size_gb > 50" | bc -l) )) && continue
        [[ -n "$CATEGORY_FILTER" && "$category" != "$CATEGORY_FILTER" ]] && continue
        (( $(echo "$size_gb > $MAX_SIZE_GB" | bc -l) )) && continue

        model_files+=("$model_file")
        model_names+=("$model_name")
        model_categories+=("$category")
        model_sizes+=("$size_gb")

    done < <(find "$MODELS_DIR" -name "*.gguf" -type f 2>/dev/null | sort)

    local total=${#model_files[@]}

    if [[ $total -eq 0 ]]; then
        print_error "No models found"
        exit 1
    fi

    print_success "Found $total models"
    echo ""

    # List mode
    if $LIST_ONLY; then
        printf "${BOLD}%-15s %-30s %10s${NC}\n" "CATEGORY" "MODEL" "SIZE"
        printf "%-15s %-30s %10s\n" "--------" "-----" "----"
        for i in "${!model_files[@]}"; do
            printf "%-15s %-30s %8s GB\n" "${model_categories[$i]}" "${model_names[$i]}" "${model_sizes[$i]}"
        done
        exit 0
    fi

    # Setup output
    mkdir -p "$OUTPUT_DIR"
    echo "category,model,size_gb,quant,params,pp512_ts,tg128_ts" > "$OUTPUT_FILE"

    print_header "Running Benchmarks"

    declare -a results=()
    local failed=0

    for i in "${!model_files[@]}"; do
        local model_file="${model_files[$i]}"
        local model_name="${model_names[$i]}"
        local category="${model_categories[$i]}"
        local size_gb="${model_sizes[$i]}"
        local file_name=$(basename "$model_file")

        echo -e "${CYAN}[$((i+1))/$total]${NC} ${BOLD}$model_name${NC} ($category, ${size_gb}GB)"

        # Run benchmark
        local output
        if ! output=$("$LLAMA_BENCH" -m "$model_file" -ngl $GPU_LAYERS -t $THREADS -fa 1 2>&1); then
            print_warning "  Failed to benchmark"
            ((failed++))
            continue
        fi

        # Parse results - extract number before ±
        local pp_speed=$(echo "$output" | grep "pp512" | grep -oP '\d+\.\d+(?= ±)' | head -1)
        local tg_speed=$(echo "$output" | grep "tg128" | grep -oP '\d+\.\d+(?= ±)' | head -1)
        local params=$(echo "$output" | grep -oP '\d+\.\d+ B' | head -1 | tr -d ' ')
        local quant=$(echo "$file_name" | grep -oP 'Q\d+_K_[A-Z]+|Q\d+_K|Q\d+' | head -1)

        pp_speed=${pp_speed:-0}
        tg_speed=${tg_speed:-0}
        params=${params:-"?"}
        quant=${quant:-"?"}

        print_success "  pp512: ${pp_speed} t/s | tg128: ${tg_speed} t/s"

        # Save results
        echo "$category,$model_name,$size_gb,$quant,$params,$pp_speed,$tg_speed" >> "$OUTPUT_FILE"
        results+=("$category|$model_name|$size_gb|$quant|$pp_speed|$tg_speed")
    done

    # Summary
    print_header "Results Summary"

    printf "${BOLD}%-12s %-28s %8s %10s %12s %10s${NC}\n" "Category" "Model" "Size" "Quant" "Prompt t/s" "Gen t/s"
    echo "─────────────────────────────────────────────────────────────────────────────────────"

    for result in "${results[@]}"; do
        IFS='|' read -r cat model size quant pp tg <<< "$result"
        printf "%-12s %-28s %6s GB %10s %12.1f %10.1f\n" "$cat" "$model" "$size" "$quant" "$pp" "$tg"
    done

    echo ""
    echo "─────────────────────────────────────────────────────────────────────────────────────"
    echo -e "Completed: $((total - failed)) | Failed: $failed"
    echo ""

    # Generate markdown report
    cat > "$REPORT_FILE" << EOF
# Strix Halo Benchmark Report

**Date:** $(date '+%Y-%m-%d %H:%M:%S')
**System:** AMD Ryzen AI Max+ 395 (128GB RAM)
**GPU:** AMD Radeon Graphics (gfx1151)
**Backend:** ROCm

## Results

| Category | Model | Size | Quant | Prompt (t/s) | Gen (t/s) |
|----------|-------|------|-------|--------------|-----------|
EOF

    for result in "${results[@]}"; do
        IFS='|' read -r cat model size quant pp tg <<< "$result"
        printf "| %s | %s | %s GB | %s | %.1f | %.1f |\n" "$cat" "$model" "$size" "$quant" "$pp" "$tg" >> "$REPORT_FILE"
    done

    echo "" >> "$REPORT_FILE"
    echo "*Generated by benchmark-all-models.sh*" >> "$REPORT_FILE"

    print_success "CSV: $OUTPUT_FILE"
    print_success "Report: $REPORT_FILE"
}

main "$@"
