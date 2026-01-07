#!/bin/bash

#===============================================================================
# llama.cpp Installation Script for AMD Strix Halo 395+
#===============================================================================
# Installs llama.cpp with ROCm (HIP) and Vulkan backends optimized for
# AMD Ryzen AI Max+ 395 APU with 128GB unified memory.
#
# Features:
#   - ROCm/HIP backend for GPU compute (primary)
#   - Vulkan backend as alternative
#   - Optimized for gfx1151 (RDNA 3.5) architecture
#   - Flash Attention support
#   - Configured for large unified memory systems
#
# Usage:
#   ./install-llama-cpp.sh              # Full installation
#   ./install-llama-cpp.sh --rocm-only  # Install ROCm dependencies only
#   ./install-llama-cpp.sh --build-only # Build llama.cpp only (skip deps)
#   ./install-llama-cpp.sh --vulkan     # Build with Vulkan backend
#   ./install-llama-cpp.sh --help       # Show help
#
# Requirements:
#   - Ubuntu 22.04/24.04 or compatible Linux distribution
#   - AMD Strix Halo APU (Ryzen AI Max+ 395 or similar)
#   - sudo privileges for system package installation
#===============================================================================

set -e

#===============================================================================
# Configuration
#===============================================================================

SCRIPT_VERSION="1.0.0"

# Installation directories
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/.local}"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$HOME/llama.cpp}"
BUILD_DIR="${BUILD_DIR:-$LLAMA_CPP_DIR/build}"

# ROCm configuration
ROCM_VERSION="${ROCM_VERSION:-6.3}"
ROCM_PATH="${ROCM_PATH:-/opt/rocm}"

# GPU architecture for Strix Halo (RDNA 3.5)
# gfx1151 is the target for Strix Halo / Ryzen AI Max+ 395
AMDGPU_TARGETS="${AMDGPU_TARGETS:-gfx1151}"

# Build options
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

# Feature flags
ENABLE_ROCM=true
ENABLE_VULKAN=false
SKIP_DEPS=false
ROCM_ONLY=false

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
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}$1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}▶${NC} ${BOLD}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    if command -v "$1" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

confirm() {
    local prompt="$1"
    local default="${2:-y}"

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -r -p "$prompt" response
    response=${response:-$default}

    [[ "$response" =~ ^[Yy]$ ]]
}

#===============================================================================
# System Detection
#===============================================================================

detect_system() {
    print_step "Detecting System Configuration"

    # Detect OS
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
        OS_ID="$ID"
    else
        print_error "Cannot detect OS. /etc/os-release not found."
        exit 1
    fi

    print_info "Operating System: $OS_NAME $OS_VERSION"

    # Detect CPU
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    print_info "CPU: $CPU_MODEL"

    # Detect GPU
    if check_command lspci; then
        GPU_INFO=$(lspci | grep -i "vga\|display" | head -1 | cut -d: -f3 | xargs)
        print_info "GPU: $GPU_INFO"
    fi

    # Detect memory
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))
    print_info "Total Memory: ${TOTAL_MEM_GB}GB"

    # Check for Strix Halo
    if [[ "$CPU_MODEL" == *"Ryzen AI"* ]] || [[ "$CPU_MODEL" == *"395"* ]]; then
        print_success "Detected AMD Strix Halo APU"
        IS_STRIX_HALO=true
    else
        print_warning "Could not confirm Strix Halo APU. Proceeding with gfx1151 target."
        IS_STRIX_HALO=false
    fi

    # Check existing ROCm installation
    if [[ -d "$ROCM_PATH" ]]; then
        if [[ -f "$ROCM_PATH/.info/version" ]]; then
            INSTALLED_ROCM=$(cat "$ROCM_PATH/.info/version" 2>/dev/null || echo "unknown")
        else
            INSTALLED_ROCM=$(ls -1 /opt/rocm-* 2>/dev/null | tail -1 | sed 's/.*rocm-//' || echo "unknown")
        fi
        print_info "Existing ROCm installation: $INSTALLED_ROCM"
    else
        print_info "No existing ROCm installation found"
    fi

    # Check GPU visibility
    if [[ -f /sys/class/drm/card0/device/vendor ]]; then
        VENDOR=$(cat /sys/class/drm/card0/device/vendor)
        if [[ "$VENDOR" == "0x1002" ]]; then
            print_success "AMD GPU detected in DRM subsystem"
        fi
    fi
}

#===============================================================================
# Dependency Installation
#===============================================================================

install_base_dependencies() {
    print_step "Installing Base Dependencies"

    local packages=(
        build-essential
        cmake
        git
        wget
        curl
        pkg-config
        python3
        python3-pip
        libcurl4-openssl-dev
        libssl-dev
    )

    print_info "Updating package lists..."
    sudo apt-get update

    print_info "Installing base packages..."
    sudo apt-get install -y "${packages[@]}"

    print_success "Base dependencies installed"
}

install_vulkan_dependencies() {
    print_step "Installing Vulkan Dependencies"

    local packages=(
        libvulkan-dev
        vulkan-tools
        mesa-vulkan-drivers
        libshaderc-dev
        glslang-tools
        spirv-tools
    )

    # For AMD GPUs, also install AMDVLK or RADV
    if [[ "$OS_ID" == "ubuntu" ]]; then
        packages+=(mesa-vulkan-drivers)
    fi

    print_info "Installing Vulkan packages..."
    sudo apt-get install -y "${packages[@]}"

    # Verify Vulkan installation
    if check_command vulkaninfo; then
        print_info "Checking Vulkan support..."
        if vulkaninfo --summary 2>/dev/null | grep -q "GPU"; then
            print_success "Vulkan is working"
        else
            print_warning "Vulkan installed but GPU not detected. May need driver update."
        fi
    fi

    print_success "Vulkan dependencies installed"
}

install_rocm() {
    print_step "Installing ROCm ${ROCM_VERSION}"

    # Check if already installed
    if [[ -d "$ROCM_PATH" ]] && [[ -f "$ROCM_PATH/bin/rocminfo" ]]; then
        print_info "ROCm appears to be installed at $ROCM_PATH"
        if confirm "Reinstall/upgrade ROCm?" "n"; then
            print_info "Proceeding with ROCm installation..."
        else
            print_info "Skipping ROCm installation"
            return 0
        fi
    fi

    # Add AMD GPG key
    print_info "Adding AMD ROCm repository..."

    # For Ubuntu 22.04/24.04
    if [[ "$OS_ID" == "ubuntu" ]]; then
        # Install prerequisites
        sudo apt-get install -y wget gnupg2

        # Add the ROCm repository
        # Method varies by ROCm version - using amdgpu-install for latest

        print_info "Downloading amdgpu-install package..."

        local AMDGPU_INSTALL_URL=""
        case "$OS_VERSION" in
            "24.04")
                AMDGPU_INSTALL_URL="https://repo.radeon.com/amdgpu-install/6.3/ubuntu/noble/amdgpu-install_6.3.60300-1_all.deb"
                ;;
            "22.04")
                AMDGPU_INSTALL_URL="https://repo.radeon.com/amdgpu-install/6.3/ubuntu/jammy/amdgpu-install_6.3.60300-1_all.deb"
                ;;
            *)
                print_warning "Ubuntu $OS_VERSION may not be officially supported. Trying 22.04 package..."
                AMDGPU_INSTALL_URL="https://repo.radeon.com/amdgpu-install/6.3/ubuntu/jammy/amdgpu-install_6.3.60300-1_all.deb"
                ;;
        esac

        local TEMP_DEB="/tmp/amdgpu-install.deb"
        wget -O "$TEMP_DEB" "$AMDGPU_INSTALL_URL"
        sudo apt-get install -y "$TEMP_DEB"
        rm -f "$TEMP_DEB"

        # Install ROCm with HIP
        print_info "Installing ROCm (this may take a while)..."
        sudo amdgpu-install -y --usecase=rocm,hip --no-dkms

    else
        print_error "Unsupported distribution: $OS_ID"
        print_info "Please install ROCm manually from: https://rocm.docs.amd.com/"
        exit 1
    fi

    # Add user to required groups
    print_info "Adding user to render and video groups..."
    sudo usermod -aG render $USER 2>/dev/null || true
    sudo usermod -aG video $USER 2>/dev/null || true

    print_success "ROCm installation completed"
    print_warning "You may need to log out and back in for group changes to take effect"
}

setup_rocm_environment() {
    print_step "Configuring ROCm Environment"

    # Create environment setup script
    local ENV_SCRIPT="$HOME/.rocm-env.sh"

    cat > "$ENV_SCRIPT" << 'ENVEOF'
# ROCm Environment Configuration for Strix Halo

# ROCm base path
export ROCM_PATH=/opt/rocm
export HIP_PATH=$ROCM_PATH

# Add ROCm to PATH
export PATH=$ROCM_PATH/bin:$PATH

# Library paths
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$ROCM_PATH/lib64:$LD_LIBRARY_PATH

# GPU target for Strix Halo (RDNA 3.5)
export AMDGPU_TARGETS=gfx1151
export HIP_VISIBLE_DEVICES=0
export GPU_DEVICE_ORDINAL=0

# HSA configuration for integrated GPU with large memory
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export HSA_ENABLE_SDMA=0

# Memory configuration for 128GB unified memory
# Allow GPU to use most of system memory
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=95
export GPU_SINGLE_ALLOC_PERCENT=95

# Performance optimizations
export HIPBLASLT_FORCE_ALGO_INDEX=0
export HIP_FORCE_DEV_KERNARG=1

# Disable problematic features for APU
export HSA_ENABLE_INTERRUPT=0
ENVEOF

    print_info "Created ROCm environment script: $ENV_SCRIPT"

    # Add to shell RC if not already present
    local SHELL_RC=""
    if [[ -f "$HOME/.bashrc" ]]; then
        SHELL_RC="$HOME/.bashrc"
    elif [[ -f "$HOME/.zshrc" ]]; then
        SHELL_RC="$HOME/.zshrc"
    fi

    if [[ -n "$SHELL_RC" ]]; then
        if ! grep -q "rocm-env.sh" "$SHELL_RC" 2>/dev/null; then
            echo "" >> "$SHELL_RC"
            echo "# ROCm environment for Strix Halo" >> "$SHELL_RC"
            echo "[ -f ~/.rocm-env.sh ] && source ~/.rocm-env.sh" >> "$SHELL_RC"
            print_info "Added ROCm environment to $SHELL_RC"
        else
            print_info "ROCm environment already in $SHELL_RC"
        fi
    fi

    # Source it now
    source "$ENV_SCRIPT"

    print_success "ROCm environment configured"
}

verify_rocm() {
    print_step "Verifying ROCm Installation"

    # Source environment
    [[ -f "$HOME/.rocm-env.sh" ]] && source "$HOME/.rocm-env.sh"

    # Check rocminfo
    if check_command rocminfo; then
        print_info "Running rocminfo..."
        if rocminfo 2>/dev/null | grep -q "gfx"; then
            local GPU_ARCH=$(rocminfo 2>/dev/null | grep "Name:" | grep "gfx" | head -1 | awk '{print $2}')
            print_success "GPU detected: $GPU_ARCH"
        else
            print_warning "rocminfo ran but no GPU detected. This may be normal before reboot."
        fi
    else
        print_warning "rocminfo not found. ROCm may not be properly installed."
    fi

    # Check hipconfig
    if check_command hipconfig; then
        print_info "HIP Configuration:"
        hipconfig --full 2>/dev/null || hipconfig 2>/dev/null || true
    fi

    # Check clinfo (OpenCL)
    if check_command clinfo; then
        print_info "Checking OpenCL..."
        local OCL_DEVICES=$(clinfo 2>/dev/null | grep "Number of devices" | head -1)
        if [[ -n "$OCL_DEVICES" ]]; then
            print_success "OpenCL: $OCL_DEVICES"
        fi
    fi
}

#===============================================================================
# llama.cpp Build
#===============================================================================

clone_llama_cpp() {
    print_step "Cloning llama.cpp"

    if [[ -d "$LLAMA_CPP_DIR" ]]; then
        print_info "llama.cpp directory exists at $LLAMA_CPP_DIR"
        if confirm "Update existing installation?" "y"; then
            print_info "Updating llama.cpp..."
            cd "$LLAMA_CPP_DIR"
            git fetch --all
            git pull origin master
        else
            print_info "Using existing llama.cpp"
        fi
    else
        print_info "Cloning llama.cpp to $LLAMA_CPP_DIR..."
        git clone https://github.com/ggerganov/llama.cpp.git "$LLAMA_CPP_DIR"
    fi

    cd "$LLAMA_CPP_DIR"

    # Show current version
    local COMMIT=$(git rev-parse --short HEAD)
    local BRANCH=$(git branch --show-current)
    print_success "llama.cpp ready (branch: $BRANCH, commit: $COMMIT)"
}

build_llama_cpp_rocm() {
    print_step "Building llama.cpp with ROCm/HIP Backend"

    cd "$LLAMA_CPP_DIR"

    # Source ROCm environment
    [[ -f "$HOME/.rocm-env.sh" ]] && source "$HOME/.rocm-env.sh"

    # Clean previous build
    if [[ -d "$BUILD_DIR" ]]; then
        print_info "Cleaning previous build..."
        rm -rf "$BUILD_DIR"
    fi

    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    print_info "Configuring CMake for ROCm build..."
    print_info "  Target GPU: $AMDGPU_TARGETS"
    print_info "  Build type: $BUILD_TYPE"
    print_info "  Install prefix: $INSTALL_PREFIX"

    # CMake configuration for ROCm
    cmake .. \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DGGML_HIP=ON \
        -DAMDGPU_TARGETS="$AMDGPU_TARGETS" \
        -DCMAKE_HIP_ARCHITECTURES="$AMDGPU_TARGETS" \
        -DGGML_HIPBLAS=ON \
        -DGGML_NATIVE=ON \
        -DGGML_AVX=ON \
        -DGGML_AVX2=ON \
        -DGGML_FMA=ON \
        -DGGML_F16C=ON \
        -DLLAMA_CURL=ON \
        -DLLAMA_BUILD_SERVER=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=ON

    print_info "Building llama.cpp (using $BUILD_JOBS parallel jobs)..."
    cmake --build . --config "$BUILD_TYPE" -j "$BUILD_JOBS"

    print_success "ROCm build completed"
}

build_llama_cpp_vulkan() {
    print_step "Building llama.cpp with Vulkan Backend"

    cd "$LLAMA_CPP_DIR"

    # Use different build directory for Vulkan
    local VULKAN_BUILD_DIR="${BUILD_DIR}-vulkan"

    # Clean previous build
    if [[ -d "$VULKAN_BUILD_DIR" ]]; then
        print_info "Cleaning previous Vulkan build..."
        rm -rf "$VULKAN_BUILD_DIR"
    fi

    mkdir -p "$VULKAN_BUILD_DIR"
    cd "$VULKAN_BUILD_DIR"

    print_info "Configuring CMake for Vulkan build..."

    cmake .. \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DGGML_VULKAN=ON \
        -DGGML_NATIVE=ON \
        -DGGML_AVX=ON \
        -DGGML_AVX2=ON \
        -DGGML_FMA=ON \
        -DGGML_F16C=ON \
        -DLLAMA_CURL=ON \
        -DLLAMA_BUILD_SERVER=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=ON

    print_info "Building llama.cpp (using $BUILD_JOBS parallel jobs)..."
    cmake --build . --config "$BUILD_TYPE" -j "$BUILD_JOBS"

    print_success "Vulkan build completed"
}

install_llama_cpp() {
    print_step "Installing llama.cpp"

    cd "$BUILD_DIR"

    print_info "Installing to $INSTALL_PREFIX..."
    cmake --install . --prefix "$INSTALL_PREFIX"

    # Ensure bin directory is in PATH
    if [[ ":$PATH:" != *":$INSTALL_PREFIX/bin:"* ]]; then
        local SHELL_RC=""
        if [[ -f "$HOME/.bashrc" ]]; then
            SHELL_RC="$HOME/.bashrc"
        elif [[ -f "$HOME/.zshrc" ]]; then
            SHELL_RC="$HOME/.zshrc"
        fi

        if [[ -n "$SHELL_RC" ]]; then
            if ! grep -q "$INSTALL_PREFIX/bin" "$SHELL_RC" 2>/dev/null; then
                echo "" >> "$SHELL_RC"
                echo "# llama.cpp binaries" >> "$SHELL_RC"
                echo "export PATH=\"$INSTALL_PREFIX/bin:\$PATH\"" >> "$SHELL_RC"
                print_info "Added $INSTALL_PREFIX/bin to PATH in $SHELL_RC"
            fi
        fi
    fi

    print_success "llama.cpp installed to $INSTALL_PREFIX"
}

#===============================================================================
# Post-Installation
#===============================================================================

create_wrapper_scripts() {
    print_step "Creating Wrapper Scripts"

    local BIN_DIR="$INSTALL_PREFIX/bin"
    mkdir -p "$BIN_DIR"

    # Create llama-cli wrapper with Strix Halo optimizations
    cat > "$BIN_DIR/llama-strix" << 'WRAPEOF'
#!/bin/bash
# Wrapper script for llama-cli optimized for Strix Halo

# Source ROCm environment
[ -f ~/.rocm-env.sh ] && source ~/.rocm-env.sh

# Add local lib to library path
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

# Default settings optimized for Strix Halo with 128GB RAM
DEFAULT_GPU_LAYERS=999
DEFAULT_CONTEXT=8192
DEFAULT_BATCH=2048
DEFAULT_UBATCH=512
DEFAULT_THREADS=$(nproc)

# Parse model size from filename to set optimal context
get_optimal_context() {
    local model="$1"
    case "$model" in
        *70[bB]*|*72[bB]*)  echo 4096 ;;
        *32[bB]*|*34[bB]*)  echo 8192 ;;
        *14[bB]*|*13[bB]*)  echo 16384 ;;
        *7[bB]*|*8[bB]*)    echo 32768 ;;
        *3[bB]*|*1[bB]*)    echo 65536 ;;
        *)                   echo "$DEFAULT_CONTEXT" ;;
    esac
}

# Find the actual binary
LLAMA_CLI="${LLAMA_CLI:-llama-cli}"

# Build command with defaults (user args override)
exec "$LLAMA_CLI" \
    --n-gpu-layers "$DEFAULT_GPU_LAYERS" \
    --threads "$DEFAULT_THREADS" \
    --batch-size "$DEFAULT_BATCH" \
    --ubatch-size "$DEFAULT_UBATCH" \
    --flash-attn \
    "$@"
WRAPEOF
    chmod +x "$BIN_DIR/llama-strix"

    # Create llama-server wrapper with Strix Halo optimizations
    cat > "$BIN_DIR/llama-server-strix" << 'WRAPEOF'
#!/bin/bash
# Wrapper script for llama-server optimized for Strix Halo

# Source ROCm environment
[ -f ~/.rocm-env.sh ] && source ~/.rocm-env.sh

# Add local lib to library path
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

# Default settings optimized for Strix Halo with 128GB RAM
DEFAULT_GPU_LAYERS=999
DEFAULT_CONTEXT=8192
DEFAULT_BATCH=2048
DEFAULT_UBATCH=512
DEFAULT_THREADS=$(nproc)
DEFAULT_PARALLEL=4
DEFAULT_HOST="0.0.0.0"
DEFAULT_PORT="8080"

# Find the actual binary
LLAMA_SERVER="${LLAMA_SERVER:-llama-server}"

# Build command with defaults (user args override)
exec "$LLAMA_SERVER" \
    --host "$DEFAULT_HOST" \
    --port "$DEFAULT_PORT" \
    --n-gpu-layers "$DEFAULT_GPU_LAYERS" \
    --threads "$DEFAULT_THREADS" \
    --batch-size "$DEFAULT_BATCH" \
    --ubatch-size "$DEFAULT_UBATCH" \
    --parallel "$DEFAULT_PARALLEL" \
    --flash-attn \
    --metrics \
    "$@"
WRAPEOF
    chmod +x "$BIN_DIR/llama-server-strix"

    # Create benchmark script
    cat > "$BIN_DIR/llama-bench-strix" << 'WRAPEOF'
#!/bin/bash
# Quick benchmark script for Strix Halo

[ -f ~/.rocm-env.sh ] && source ~/.rocm-env.sh

# Add local lib to library path
export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

LLAMA_BENCH="${LLAMA_BENCH:-llama-bench}"

if [[ -z "$1" ]]; then
    echo "Usage: llama-bench-strix <model.gguf> [additional args]"
    exit 1
fi

exec "$LLAMA_BENCH" \
    -m "$1" \
    -ngl 999 \
    -t $(nproc) \
    -fa 1 \
    "${@:2}"
WRAPEOF
    chmod +x "$BIN_DIR/llama-bench-strix"

    print_success "Created wrapper scripts:"
    print_info "  llama-strix        - Optimized llama-cli wrapper"
    print_info "  llama-server-strix - Optimized llama-server wrapper"
    print_info "  llama-bench-strix  - Quick benchmark tool"
}

create_systemd_service() {
    print_step "Creating Systemd Service (Optional)"

    local SERVICE_FILE="$HOME/.config/systemd/user/llama-server.service"
    mkdir -p "$(dirname "$SERVICE_FILE")"

    cat > "$SERVICE_FILE" << SERVICEEOF
[Unit]
Description=llama.cpp Server for Strix Halo
After=network.target

[Service]
Type=simple
Environment="PATH=$INSTALL_PREFIX/bin:/opt/rocm/bin:/usr/local/bin:/usr/bin"
EnvironmentFile=$HOME/.rocm-env.sh
ExecStart=$INSTALL_PREFIX/bin/llama-server-strix --model %h/llm-models/default.gguf
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
SERVICEEOF

    print_info "Created systemd user service: $SERVICE_FILE"
    print_info "To use:"
    print_info "  1. Create symlink: ln -s /path/to/your/model.gguf ~/llm-models/default.gguf"
    print_info "  2. Enable: systemctl --user enable llama-server"
    print_info "  3. Start: systemctl --user start llama-server"
}

verify_installation() {
    print_step "Verifying Installation"

    # Source environment
    [[ -f "$HOME/.rocm-env.sh" ]] && source "$HOME/.rocm-env.sh"
    export PATH="$INSTALL_PREFIX/bin:$PATH"

    local all_good=true

    # Check llama-cli
    if check_command llama-cli; then
        print_success "llama-cli found: $(which llama-cli)"
    else
        print_warning "llama-cli not found in PATH"
        all_good=false
    fi

    # Check llama-server
    if check_command llama-server; then
        print_success "llama-server found: $(which llama-server)"
    else
        print_warning "llama-server not found in PATH"
        all_good=false
    fi

    # Check wrapper scripts
    if check_command llama-strix; then
        print_success "llama-strix wrapper found"
    fi

    # Quick GPU test if we have a model
    local TEST_MODEL=$(find "$HOME" -name "*.gguf" -type f 2>/dev/null | head -1)
    if [[ -n "$TEST_MODEL" ]]; then
        print_info "Found test model: $(basename "$TEST_MODEL")"
        print_info "Running quick GPU test..."

        if timeout 30 llama-cli -m "$TEST_MODEL" -ngl 999 -n 1 -p "test" 2>&1 | grep -q "loaded"; then
            print_success "GPU inference test passed"
        else
            print_warning "GPU test inconclusive - may need to reboot for ROCm to initialize"
        fi
    else
        print_info "No .gguf model found for testing. Download one to verify GPU support."
    fi

    if $all_good; then
        print_success "Installation verified successfully"
    else
        print_warning "Some components may need attention"
    fi
}

print_summary() {
    print_header "Installation Complete!"

    echo -e "${BOLD}Installed Components:${NC}"
    echo "  llama.cpp directory: $LLAMA_CPP_DIR"
    echo "  Binaries: $INSTALL_PREFIX/bin/"
    echo "  ROCm environment: ~/.rocm-env.sh"
    echo ""

    echo -e "${BOLD}Available Commands:${NC}"
    echo "  llama-cli          - Main inference binary"
    echo "  llama-server       - OpenAI-compatible API server"
    echo "  llama-strix        - Optimized CLI wrapper for Strix Halo"
    echo "  llama-server-strix - Optimized server wrapper for Strix Halo"
    echo "  llama-bench        - Benchmarking tool"
    echo "  llama-bench-strix  - Quick benchmark wrapper"
    echo ""

    echo -e "${BOLD}Quick Start:${NC}"
    echo "  # Reload shell environment"
    echo "  source ~/.bashrc  # or ~/.zshrc"
    echo ""
    echo "  # Run inference"
    echo "  llama-strix -m /path/to/model.gguf -p \"Hello, world!\""
    echo ""
    echo "  # Start API server"
    echo "  llama-server-strix -m /path/to/model.gguf"
    echo ""
    echo "  # Run benchmark"
    echo "  llama-bench-strix /path/to/model.gguf"
    echo ""

    echo -e "${BOLD}Optimization Tips for Strix Halo:${NC}"
    echo "  - Use -ngl 999 to offload all layers to GPU"
    echo "  - Use -fa (flash attention) for better memory efficiency"
    echo "  - For large models (70B+), use Q4_K_M quantization"
    echo "  - Context size can be increased significantly with 128GB RAM"
    echo "  - Use --mlock to keep model in memory"
    echo ""

    echo -e "${YELLOW}Note: You may need to log out and back in (or reboot) for all${NC}"
    echo -e "${YELLOW}changes to take effect, especially ROCm group membership.${NC}"
}

#===============================================================================
# Main
#===============================================================================

show_help() {
    echo "llama.cpp Installation Script for Strix Halo"
    echo "Version: $SCRIPT_VERSION"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --help, -h        Show this help message"
    echo "  --rocm-only       Only install ROCm dependencies"
    echo "  --build-only      Skip dependency installation, only build llama.cpp"
    echo "  --vulkan          Build with Vulkan backend instead of ROCm"
    echo "  --both            Build both ROCm and Vulkan backends"
    echo "  --prefix PATH     Installation prefix (default: ~/.local)"
    echo "  --llama-dir PATH  llama.cpp source directory (default: ~/llama.cpp)"
    echo "  --rocm-version V  ROCm version to install (default: 6.3)"
    echo "  --gpu-target T    GPU architecture target (default: gfx1151)"
    echo "  --jobs N          Number of parallel build jobs (default: nproc)"
    echo ""
    echo "Environment Variables:"
    echo "  INSTALL_PREFIX    Same as --prefix"
    echo "  LLAMA_CPP_DIR     Same as --llama-dir"
    echo "  ROCM_VERSION      Same as --rocm-version"
    echo "  AMDGPU_TARGETS    Same as --gpu-target"
    echo "  BUILD_JOBS        Same as --jobs"
    echo ""
    echo "Examples:"
    echo "  $0                          # Full installation with ROCm"
    echo "  $0 --vulkan                 # Install with Vulkan backend"
    echo "  $0 --both                   # Install both backends"
    echo "  $0 --build-only             # Rebuild only (deps already installed)"
    echo "  $0 --prefix /opt/llama.cpp  # Custom install location"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --rocm-only)
                ROCM_ONLY=true
                shift
                ;;
            --build-only)
                SKIP_DEPS=true
                shift
                ;;
            --vulkan)
                ENABLE_VULKAN=true
                ENABLE_ROCM=false
                shift
                ;;
            --both)
                ENABLE_VULKAN=true
                ENABLE_ROCM=true
                shift
                ;;
            --prefix)
                INSTALL_PREFIX="$2"
                shift 2
                ;;
            --llama-dir)
                LLAMA_CPP_DIR="$2"
                BUILD_DIR="$LLAMA_CPP_DIR/build"
                shift 2
                ;;
            --rocm-version)
                ROCM_VERSION="$2"
                shift 2
                ;;
            --gpu-target)
                AMDGPU_TARGETS="$2"
                shift 2
                ;;
            --jobs)
                BUILD_JOBS="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"

    print_header "llama.cpp Installer for AMD Strix Halo"
    echo "Version: $SCRIPT_VERSION"
    echo "Target GPU: $AMDGPU_TARGETS (RDNA 3.5)"
    echo ""

    # Detect system
    detect_system

    # ROCm only mode
    if $ROCM_ONLY; then
        install_base_dependencies
        install_rocm
        setup_rocm_environment
        verify_rocm
        echo ""
        print_success "ROCm installation complete. Run script again without --rocm-only to build llama.cpp"
        exit 0
    fi

    # Install dependencies
    if ! $SKIP_DEPS; then
        install_base_dependencies

        if $ENABLE_ROCM; then
            install_rocm
            setup_rocm_environment
            verify_rocm
        fi

        if $ENABLE_VULKAN; then
            install_vulkan_dependencies
        fi
    fi

    # Clone/update llama.cpp
    clone_llama_cpp

    # Build
    if $ENABLE_ROCM; then
        build_llama_cpp_rocm
        install_llama_cpp
    fi

    if $ENABLE_VULKAN; then
        build_llama_cpp_vulkan
        # Install Vulkan build to different location to avoid overwriting
        if $ENABLE_ROCM; then
            print_info "Vulkan build available at: ${BUILD_DIR}-vulkan/bin/"
        else
            cd "${BUILD_DIR}-vulkan"
            cmake --install . --prefix "$INSTALL_PREFIX"
        fi
    fi

    # Post-installation
    create_wrapper_scripts
    create_systemd_service
    verify_installation
    print_summary
}

main "$@"
