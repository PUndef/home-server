#!/bin/bash
# Build llama.cpp from source on phoneserver (aarch64, 8 cores).
# Uses NEON, no GPU offload (Adreno 618 has no OpenCL drivers in pmOS mainline).

PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'set -e
    echo "=== install build deps ==="
    sudo apk add build-base git cmake openblas-dev curl 2>&1 | tail -5

    echo
    echo "=== clone llama.cpp ==="
    if [ ! -d ~/llama.cpp ]; then
        git clone --depth 1 https://github.com/ggml-org/llama.cpp.git ~/llama.cpp
    else
        cd ~/llama.cpp && git pull --depth 1
    fi

    echo
    echo "=== cmake build (CPU only, NEON, OpenBLAS) ==="
    cd ~/llama.cpp
    cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS \
        -DGGML_NATIVE=ON 2>&1 | tail -10
    cmake --build build --config Release -j 8 2>&1 | tail -10

    echo
    echo "=== built binaries ==="
    ls -la ~/llama.cpp/build/bin/ | head -20'
