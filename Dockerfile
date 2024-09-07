FROM verilator/verilator:v5.022

RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    autoconf \
    automake \
    curl \
    bison \
    flex \
    libgmp-dev \
    libmpc-dev \
    libmpfr-dev \
    texinfo \
    wget \
    libfl2 \
    libfl-dev \
    zlib1g-dev \
    libexpat1-dev \
    ca-certificates \
    pkg-config \
    python3 \
    device-tree-compiler

ENV RISCV /opt/riscv
ENV PATH $RISCV/bin:$PATH

ENV RISCV_GCC_VERSION="2024.09.03"

RUN wget https://github.com/riscv-collab/riscv-gnu-toolchain/releases/download/2024.09.03/riscv32-glibc-ubuntu-22.04-gcc-nightly-2024.09.03-nightly.tar.gz -O riscv.tar.gz && \
    tar -xf riscv.tar.gz && \
    mv riscv /opt/


RUN riscv32-unknown-linux-gnu-gcc --version && verilator --version

WORKDIR /workspace

ENTRYPOINT ["/bin/bash"]
CMD ["-c", \
    "cd /workspace && \
    git config --global --add safe.directory \\* && \
    git submodule init && \
    git submodule update && \
    make setup && \
    make trace && \
    ./obj_dir/VTop test_programs/coremark.elf"]
