#!/bin/bash

#===============================================================================
# Strix Halo 395+ Model Downloader (128GB Unified Memory) - v3 FIXED
#===============================================================================
# This script downloads the best GGUF models optimized for AMD Ryzen AI Max+ 395
# with 128GB LPDDR5X unified memory (~96-115GB available for GPU compute via GTT)
#
# IMPORTANT: Uses bartowski's repos where possible for single-file downloads.
# Unsloth repos use subdirectories for quantization levels.
#===============================================================================

set -e

# Configuration
MODELS_DIR="${MODELS_DIR:-$HOME/llm-models}"
ENABLE_HF_TRANSFER="${ENABLE_HF_TRANSFER:-1}"
DRY_RUN="${DRY_RUN:-0}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#===============================================================================
# Helper Functions
#===============================================================================

print_header() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_disk_space() {
    local required_gb=$1
    local available_gb=$(df -BG "$MODELS_DIR" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    
    if [ -n "$available_gb" ] && [ "$available_gb" -lt "$required_gb" ]; then
        print_warning "Low disk space: ${available_gb}GB available, ${required_gb}GB+ recommended"
        return 1
    fi
    return 0
}

# Download a single file
download_model() {
    local repo=$1
    local filename=$2
    local subdir=$3
    local description=$4
    
    local target_dir="$MODELS_DIR/$subdir"
    mkdir -p "$target_dir"
    
    echo -e "${GREEN}→${NC} Downloading: ${YELLOW}$description${NC}"
    echo -e "  Repository: $repo"
    echo -e "  File: $filename"
    echo -e "  Target: $target_dir/"
    
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[DRY RUN - Skipping download]${NC}\n"
        return 0
    fi
    
    if [ -f "$target_dir/$filename" ]; then
        print_warning "File already exists, skipping: $target_dir/$filename"
        return 0
    fi
    
    if hf download "$repo" "$filename" \
        --local-dir "$target_dir"; then
        print_success "Downloaded: $filename\n"
    else
        print_error "Failed to download: $filename\n"
        return 1
    fi
}

# Download files matching a pattern (for split files or folders)
download_model_pattern() {
    local repo=$1
    local pattern=$2
    local subdir=$3
    local description=$4
    
    local target_dir="$MODELS_DIR/$subdir"
    mkdir -p "$target_dir"
    
    echo -e "${GREEN}→${NC} Downloading: ${YELLOW}$description${NC}"
    echo -e "  Repository: $repo"
    echo -e "  Pattern: $pattern"
    echo -e "  Target: $target_dir/"
    
    if [ "$DRY_RUN" = "1" ]; then
        echo -e "  ${YELLOW}[DRY RUN - Skipping download]${NC}\n"
        return 0
    fi
    
    if hf download "$repo" \
        --include "$pattern" \
        --local-dir "$target_dir";
    then 
        print_success "Downloaded: $pattern\n"
    else
        print_error "Failed to download: $pattern\n"
        return 1
    fi
}

#===============================================================================
# Installation and Setup
#===============================================================================

setup_environment() {
    print_header "Setting Up Environment"
    
    # Check for Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    
    # Check if huggingface-cli is available
    if ! command -v hf &> /dev/null; then
        print_info "Installing huggingface_hub..."
        pip install --upgrade huggingface_hub hf_transfer --quiet
    fi
    
    # Enable fast transfers
    if [ "$ENABLE_HF_TRANSFER" = "1" ]; then
        export HF_HUB_ENABLE_HF_TRANSFER=1
        print_info "HF Transfer enabled for faster downloads"
    fi
    
    # Create models directory
    mkdir -p "$MODELS_DIR"
    print_info "Models directory: $MODELS_DIR"
    
    # Check disk space (recommend at least 500GB for full suite)
    check_disk_space 500
    
    print_success "Environment setup complete"
}

#===============================================================================
# Model Categories - Using verified repos and filenames
#===============================================================================

download_fast_models() {
    print_header "FAST MODELS (3B-9B) - 20-50+ tok/s on Strix Halo"
    
    # Llama 3.2 3B - Ultra fast (bartowski repo - single file)
    download_model "bartowski/Llama-3.2-3B-Instruct-GGUF" \
        "Llama-3.2-3B-Instruct-Q6_K_L.gguf" \
        "fast/llama-3.2-3b" \
        "Llama 3.2 3B Instruct (Q6_K_L) - ~3GB, ultra fast"
    
    # Llama 3.1 8B - Great all-rounder (bartowski repo)
    download_model "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF" \
        "Meta-Llama-3.1-8B-Instruct-Q5_K_M.gguf" \
        "fast/llama-3.1-8b" \
        "Llama 3.1 8B Instruct (Q5_K_M) - ~6GB, excellent quality"
    
    # Mistral 7B v0.3 - Fast and efficient (bartowski repo)
    download_model "bartowski/Mistral-7B-Instruct-v0.3-GGUF" \
        "Mistral-7B-Instruct-v0.3-Q5_K_M.gguf" \
        "fast/mistral-7b" \
        "Mistral 7B v0.3 Instruct (Q5_K_M) - ~5GB, fast inference"
    
    # Qwen 2.5 7B - Strong multilingual (bartowski repo - single file!)
    download_model "bartowski/Qwen2.5-7B-Instruct-GGUF" \
        "Qwen2.5-7B-Instruct-Q5_K_M.gguf" \
        "fast/qwen2.5-7b" \
        "Qwen 2.5 7B Instruct (Q5_K_M) - ~5GB, great reasoning"
    
    # Gemma 2 9B - Google's efficient model (bartowski repo)
    download_model "bartowski/gemma-2-9b-it-GGUF" \
        "gemma-2-9b-it-Q5_K_M.gguf" \
        "fast/gemma-2-9b" \
        "Gemma 2 9B IT (Q5_K_M) - ~7GB, accurate responses"
}

download_balanced_models() {
    print_header "BALANCED MODELS (14B-32B) - 10-25 tok/s on Strix Halo"
    
    # Qwen 2.5 14B - Excellent quality/speed ratio (bartowski)
    download_model "bartowski/Qwen2.5-14B-Instruct-GGUF" \
        "Qwen2.5-14B-Instruct-Q5_K_M.gguf" \
        "balanced/qwen2.5-14b" \
        "Qwen 2.5 14B Instruct (Q5_K_M) - ~10GB, strong reasoning"
    
    # Qwen 2.5 32B - Best in class for size (bartowski)
    download_model "bartowski/Qwen2.5-32B-Instruct-GGUF" \
        "Qwen2.5-32B-Instruct-Q4_K_M.gguf" \
        "balanced/qwen2.5-32b" \
        "Qwen 2.5 32B Instruct (Q4_K_M) - ~20GB, excellent quality"
    
    # DeepSeek R1 Distill Qwen 32B - Top reasoning (bartowski)
    download_model "bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF" \
        "DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf" \
        "balanced/deepseek-r1-32b" \
        "DeepSeek R1 Distill Qwen 32B (Q4_K_M) - ~20GB, chain-of-thought"
    
    # Gemma 2 27B - High quality responses (bartowski)
    download_model "bartowski/gemma-2-27b-it-GGUF" \
        "gemma-2-27b-it-Q4_K_M.gguf" \
        "balanced/gemma-2-27b" \
        "Gemma 2 27B IT (Q4_K_M) - ~17GB, very capable"
    
    # Mistral Small 24B (bartowski)
    download_model "bartowski/Mistral-Small-24B-Instruct-2501-GGUF" \
        "Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf" \
        "balanced/mistral-small-24b" \
        "Mistral Small 24B Instruct (Q4_K_M) - ~15GB, efficient"
}

download_large_models() {
    print_header "LARGE MODELS (70B) - 3-15 tok/s on Strix Halo"
    
    # Llama 3.3 70B - Best open 70B model (bartowski - split files in folder)
    download_model_pattern "bartowski/Llama-3.3-70B-Instruct-GGUF" \
        "Llama-3.3-70B-Instruct-Q4_K_M/*" \
        "large/llama-3.3-70b" \
        "Llama 3.3 70B Instruct (Q4_K_M) - ~42GB, flagship quality"
    
    # DeepSeek R1 Distill Llama 70B - Advanced reasoning (bartowski)
    download_model_pattern "bartowski/DeepSeek-R1-Distill-Llama-70B-GGUF" \
        "DeepSeek-R1-Distill-Llama-70B-Q4_K_M/*" \
        "large/deepseek-r1-70b" \
        "DeepSeek R1 Distill Llama 70B (Q4_K_M) - ~42GB, deep reasoning"
    
    # Qwen 2.5 72B - Strong multilingual 70B (bartowski)
    download_model_pattern "bartowski/Qwen2.5-72B-Instruct-GGUF" \
        "Qwen2.5-72B-Instruct-Q4_K_M/*" \
        "large/qwen2.5-72b" \
        "Qwen 2.5 72B Instruct (Q4_K_M) - ~43GB, excellent all-around"
}

download_massive_models() {
    print_header "MASSIVE MODELS (100B+) - 1-5 tok/s on Strix Halo"
    print_warning "These models push the limits of 128GB - slower but functional"
    
    # Llama 4 Scout 17B-16E (MoE, 109B total params) - unsloth
    # Files are in Q4_K_M subdirectory
    download_model_pattern "unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF" \
        "Q4_K_M/*" \
        "massive/llama-4-scout" \
        "Llama 4 Scout 17B-16E MoE (Q4_K_M) - ~60GB, multimodal"
    
    # Also download the vision projector for Llama 4
    download_model "unsloth/Llama-4-Scout-17B-16E-Instruct-GGUF" \
        "mmproj-BF16.gguf" \
        "massive/llama-4-scout" \
        "Llama 4 Scout Vision Projector (BF16) - ~1.7GB"
    
    # Qwen 3 235B A22B (MoE) - unsloth Dynamic quant
    # Use UD (Unsloth Dynamic) Q3_K_XL for best quality that fits
    download_model_pattern "unsloth/Qwen3-235B-A22B-Instruct-2507-GGUF" \
        "*UD-Q3_K_XL*" \
        "massive/qwen3-235b" \
        "Qwen 3 235B-A22B MoE (UD-Q3_K_XL) - ~97GB, frontier model"
   
    # Qwen 3 235B A22B Thinking (MoE) - Extended reasoning model
    # Use Q3_K_M for best quality that fits in 128GB
    download_model_pattern "unsloth/Qwen3-235B-A22B-Thinking-2507-GGUF" \
        "Q3_K_M/*" \
        "massive/qwen3-235b-thinking" \
        "Qwen 3 235B-A22B Thinking (Q3_K_M) - ~97GB, state-of-art reasoning"

    # Mistral Large 123B (bartowski - split files)
    download_model_pattern "bartowski/Mistral-Large-Instruct-2407-GGUF" \
        "Mistral-Large-Instruct-2407-Q3_K_L/*" \
        "massive/mistral-large-123b" \
        "Mistral Large 123B (Q3_K_L) - ~60GB, high capability"

    # OpenAI gpt-oss-120b - OpenAI's open-weight reasoning model (MoE, 117B params, 5.1B active)
    # Uses harmony response format, supports reasoning levels (low/medium/high)
    # IMPORTANT: Use native MXFP4 format - model is natively trained in MXFP4, no additional quantization needed
    download_model_pattern "ggml-org/gpt-oss-120b-GGUF" \
        "*mxfp4*" \
        "massive/gpt-oss-120b" \
        "OpenAI gpt-oss-120b (MXFP4) - ~63GB, OpenAI's open reasoning model"
}

download_coding_models() {
    print_header "CODING MODELS - Optimized for Programming"
    
    # Qwen 2.5 Coder 7B - Fast coding assistant (bartowski - single file!)
    download_model "bartowski/Qwen2.5-Coder-7B-Instruct-GGUF" \
        "Qwen2.5-Coder-7B-Instruct-Q5_K_M.gguf" \
        "coding/qwen2.5-coder-7b" \
        "Qwen 2.5 Coder 7B (Q5_K_M) - ~5GB, fast code completion"
    
    # Qwen 2.5 Coder 32B - Best open coding model (bartowski)
    download_model "bartowski/Qwen2.5-Coder-32B-Instruct-GGUF" \
        "Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf" \
        "coding/qwen2.5-coder-32b" \
        "Qwen 2.5 Coder 32B (Q4_K_M) - ~20GB, excellent code quality"
    
    # DeepSeek Coder V2 Lite 16B (bartowski)
    download_model "bartowski/DeepSeek-Coder-V2-Lite-Instruct-GGUF" \
        "DeepSeek-Coder-V2-Lite-Instruct-Q5_K_M.gguf" \
        "coding/deepseek-coder-v2-16b" \
        "DeepSeek Coder V2 Lite 16B (Q5_K_M) - ~11GB, strong coder"

    # Qwen3 Coder 30B A3B (MoE) - Best tool calling support (unsloth)
    download_model "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF" \
        "Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf" \
        "coding/qwen3-coder-30b" \
        "Qwen3 Coder 30B-A3B MoE (Q4_K_M) - ~19GB, excellent tool calling"
    
    # CodeLlama 70B - Large code model (TheBloke)
    download_model_pattern "TheBloke/CodeLlama-70B-Instruct-GGUF" \
        "codellama-70b-instruct.Q4_K_M.gguf*" \
        "coding/codellama-70b" \
        "CodeLlama 70B Instruct (Q4_K_M) - ~42GB, comprehensive coding"
}

download_vision_models() {
    print_header "VISION MODELS - Multimodal Understanding"
    
    # LLaVA 1.6 Mistral 7B - Fast vision (cjpais)
    download_model "cjpais/llava-1.6-mistral-7b-gguf" \
        "llava-v1.6-mistral-7b.Q5_K_M.gguf" \
        "vision/llava-1.6-7b" \
        "LLaVA 1.6 Mistral 7B (Q5_K_M) - ~5GB, fast image understanding"
    
    # Qwen 2.5 VL 7B - Efficient multimodal (unsloth - single files!)
    download_model "unsloth/Qwen2.5-VL-7B-Instruct-GGUF" \
        "Qwen2.5-VL-7B-Instruct-Q5_K_M.gguf" \
        "vision/qwen2.5-vl-7b" \
        "Qwen 2.5 VL 7B (Q5_K_M) - ~5GB, good vision + language"
    
    # Pixtral 12B - Mistral's vision model (bartowski)
    download_model "bartowski/mistral-community_pixtral-12b-GGUF" \
        "mistral-community_pixtral-12b-Q4_K_M.gguf" \
        "vision/pixtral-12b" \
        "Pixtral 12B (Q4_K_M) - ~8GB, Mistral vision model"
}

download_specialized_models() {
    print_header "SPECIALIZED MODELS - Specific Use Cases"

    # Hermes 4 14B - NousResearch's fast tool-use model (bartowski - single file)
    # Specifically trained for function calling, JSON schema adherence, and structured outputs
    download_model "bartowski/NousResearch_Hermes-4-14B-GGUF" \
        "NousResearch_Hermes-4-14B-Q5_K_M.gguf" \
        "specialized/hermes-4-14b" \
        "Hermes 4 14B (Q5_K_M) - ~10GB, fast tool/function calling"

    # Hermes 4 70B - NousResearch's tool-use optimized model (bartowski - single file)
    # Specifically trained for function calling, JSON schema adherence, and structured outputs
    download_model "bartowski/NousResearch_Hermes-4-70B-GGUF" \
        "NousResearch_Hermes-4-70B-Q4_K_M.gguf" \
        "specialized/hermes-4-70b" \
        "Hermes 4 70B (Q4_K_M) - ~42GB, excellent tool/function calling"

    # Phi-4 14B - Microsoft's efficient model (bartowski)
    download_model "bartowski/phi-4-GGUF" \
        "phi-4-Q5_K_M.gguf" \
        "specialized/phi-4" \
        "Phi-4 14B (Q5_K_M) - ~10GB, efficient reasoning"
    
    # Command R+ 104B - RAG optimized (bartowski - split files)
    download_model_pattern "bartowski/c4ai-command-r-plus-08-2024-GGUF" \
        "c4ai-command-r-plus-08-2024-Q3_K_M/*" \
        "specialized/command-r-plus" \
        "Command R+ 104B (Q3_K_M) - ~50GB, RAG & tool use"
    
    # Mixtral 8x22B MoE - Efficient large model (bartowski - split files)
    download_model_pattern "MaziyarPanahi/Mixtral-8x22B-Instruct-v0.1-GGUF" \
        "Mixtral-8x22B-Instruct-v0.1-Q3_K_M/*" \
        "specialized/mixtral-8x22b" \
        "Mixtral 8x22B MoE (Q3_K_M) - ~56GB, efficient MoE"
    
    # SOLAR 10.7B - Upscaled efficient model (TheBloke)
    download_model "TheBloke/SOLAR-10.7B-Instruct-v1.0-GGUF" \
        "solar-10.7b-instruct-v1.0.Q5_K_M.gguf" \
        "specialized/solar-10.7b" \
        "SOLAR 10.7B (Q5_K_M) - ~8GB, depth upscaled"
}

#===============================================================================
# Menu System
#===============================================================================

show_menu() {
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}     ${YELLOW}Strix Halo 395+ Model Downloader${NC} (v3 Fixed)                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}     ${BLUE}128GB Unified Memory Edition${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}1)${NC} Download ALL models (requires ~600GB+ disk space)            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}2)${NC} Fast Models (3-9B) - Quick responses, ~25GB total             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}3)${NC} Balanced Models (14-32B) - Quality/speed, ~80GB total         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}4)${NC} Large Models (70B) - High capability, ~130GB total            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}5)${NC} Massive Models (100B+) - Frontier models, ~220GB total        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}6)${NC} Coding Models - Programming optimized, ~80GB total            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}7)${NC} Vision Models - Multimodal, ~20GB total                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}8)${NC} Specialized Models - RAG, MoE, etc., ~125GB total             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}9)${NC} Essential Pack - Best model per category, ~150GB              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}0)${NC} Exit                                                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}"
    echo -e "\nModels directory: ${BLUE}$MODELS_DIR${NC}"
    echo -e "Dry run mode: ${YELLOW}$DRY_RUN${NC} (set DRY_RUN=1 to preview)"
    echo -n -e "\nSelect option [0-9]: "
}

download_essential_pack() {
    print_header "ESSENTIAL PACK - Best Model Per Category"
    
    # Best fast model (bartowski - verified single file)
    download_model "bartowski/Qwen2.5-7B-Instruct-GGUF" \
        "Qwen2.5-7B-Instruct-Q5_K_M.gguf" \
        "essential/qwen2.5-7b" \
        "Qwen 2.5 7B - Best fast all-rounder"
    
    # Best balanced model (bartowski)
    download_model "bartowski/Qwen2.5-32B-Instruct-GGUF" \
        "Qwen2.5-32B-Instruct-Q4_K_M.gguf" \
        "essential/qwen2.5-32b" \
        "Qwen 2.5 32B - Best quality/speed balance"
    
    # Best large model (bartowski - split)
    download_model_pattern "bartowski/Llama-3.3-70B-Instruct-GGUF" \
        "Llama-3.3-70B-Instruct-Q4_K_M/*" \
        "essential/llama-3.3-70b" \
        "Llama 3.3 70B - Best open 70B model"
    
    # Best coding model (bartowski)
    download_model "bartowski/Qwen2.5-Coder-32B-Instruct-GGUF" \
        "Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf" \
        "essential/qwen2.5-coder-32b" \
        "Qwen 2.5 Coder 32B - Best open coding model"
    
    # Best reasoning model (bartowski)
    download_model "bartowski/DeepSeek-R1-Distill-Qwen-32B-GGUF" \
        "DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf" \
        "essential/deepseek-r1-32b" \
        "DeepSeek R1 Distill 32B - Best reasoning model"
}

#===============================================================================
# Main Execution
#===============================================================================

main() {
    echo -e "${CYAN}"
    echo "  ╔═══════════════════════════════════════════════════════════════╗"
    echo "  ║                                                               ║"
    echo "  ║   ███████╗████████╗██████╗ ██╗██╗  ██╗    ██╗  ██╗ █████╗    ║"
    echo "  ║   ██╔════╝╚══██╔══╝██╔══██╗██║╚██╗██╔╝    ██║  ██║██╔══██╗   ║"
    echo "  ║   ███████╗   ██║   ██████╔╝██║ ╚███╔╝     ███████║███████║   ║"
    echo "  ║   ╚════██║   ██║   ██╔══██╗██║ ██╔██╗     ██╔══██║██╔══██║   ║"
    echo "  ║   ███████║   ██║   ██║  ██║██║██╔╝ ██╗    ██║  ██║██║  ██║   ║"
    echo "  ║   ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝  ╚═╝   ║"
    echo "  ║                                                               ║"
    echo "  ║           Model Downloader for 128GB Systems                  ║"
    echo "  ║                      (v3 Fixed)                               ║"
    echo "  ╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    setup_environment
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                download_fast_models
                download_balanced_models
                download_large_models
                download_massive_models
                download_coding_models
                download_vision_models
                download_specialized_models
                ;;
            2)
                download_fast_models
                ;;
            3)
                download_balanced_models
                ;;
            4)
                download_large_models
                ;;
            5)
                download_massive_models
                ;;
            6)
                download_coding_models
                ;;
            7)
                download_vision_models
                ;;
            8)
                download_specialized_models
                ;;
            9)
                download_essential_pack
                ;;
            0)
                print_info "Exiting..."
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 0-9."
                ;;
        esac
        
        echo -e "\n${GREEN}Download batch complete!${NC}"
        echo -e "Press Enter to continue..."
        read -r
    done
}

#===============================================================================
# Script Entry Point
#===============================================================================

# Allow running specific categories directly
case "${1:-}" in
    --fast)
        setup_environment
        download_fast_models
        ;;
    --balanced)
        setup_environment
        download_balanced_models
        ;;
    --large)
        setup_environment
        download_large_models
        ;;
    --massive)
        setup_environment
        download_massive_models
        ;;
    --coding)
        setup_environment
        download_coding_models
        ;;
    --vision)
        setup_environment
        download_vision_models
        ;;
    --specialized)
        setup_environment
        download_specialized_models
        ;;
    --essential)
        setup_environment
        download_essential_pack
        ;;
    --all)
        setup_environment
        download_fast_models
        download_balanced_models
        download_large_models
        download_massive_models
        download_coding_models
        download_vision_models
        download_specialized_models
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --fast         Download fast models (3-9B)"
        echo "  --balanced     Download balanced models (14-32B)"
        echo "  --large        Download large models (70B)"
        echo "  --massive      Download massive models (100B+)"
        echo "  --coding       Download coding-optimized models"
        echo "  --vision       Download vision/multimodal models"
        echo "  --specialized  Download specialized models"
        echo "  --essential    Download essential pack (best per category)"
        echo "  --all          Download all models"
        echo "  --help, -h     Show this help"
        echo ""
        echo "Environment Variables:"
        echo "  MODELS_DIR     Directory to store models (default: ~/llm-models)"
        echo "  DRY_RUN=1      Preview downloads without actually downloading"
        echo "  ENABLE_HF_TRANSFER=1  Use fast HF transfer (default: enabled)"
        echo ""
        echo "Examples:"
        echo "  $0                           # Interactive menu"
        echo "  $0 --essential               # Download best models"
        echo "  MODELS_DIR=/data/models $0   # Custom directory"
        echo "  DRY_RUN=1 $0 --all           # Preview all downloads"
        ;;
    *)
        main
        ;;
esac
