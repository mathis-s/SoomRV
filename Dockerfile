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
    python3-colorama \
    device-tree-compiler \
    gawk

ENV RISCV=/opt/riscv
ENV PATH=$RISCV/bin:$PATH

RUN git clone --recursive https://github.com/riscv-collab/riscv-gnu-toolchain.git && \
    cd riscv-gnu-toolchain && \
    ./configure --prefix=/opt/riscv --with-arch=rv32imac_zba_zbb --with-abi=ilp32 && \
    make -j $(nproc) && \
    make install && \
    cd .. && rm -r riscv-gnu-toolchain

RUN cd /opt && \
    git clone https://github.com/mathis-s/riscv-isa-sim-SoomRV.git riscv-isa-sim && \
    cd riscv-isa-sim &&\
    git checkout 994579ca5898dc7438beb3f47143c1ecb6be1a21 && \
    rm -rf .git && \
    ./configure CFLAGS="-Os -g0" CXXFLAGS="-Os -g0" --with-boost=no --with-boost-asio=no --with-boost-regex=no && \
    make -j $(nproc)

RUN cd /opt && \
    git clone --recursive https://github.com/riscv-software-src/riscv-tests.git && \
    cd riscv-tests && \
    git checkout 51de00886cd28a3cf9b85ee306fb2b5ee5ab550e && \
    rm -rf .git && \
    ./configure --with-xlen=32 --prefix=/opt/riscv/ && \
    make isa

RUN riscv32-unknown-elf-gcc --version && verilator --version

WORKDIR /workspace

ENTRYPOINT ["/bin/bash"]
CMD ["-c", \
    "cd /workspace && \
    git config --global --add safe.directory \\* && \
    rm -rf riscv-isa-sim && \
    mv /opt/riscv-isa-sim . && \
    make && \
    mkdir logs && \
    python3 scripts/test_suite.py /opt/riscv-tests/isa | tee logs/test_suite.out && \
    ./obj_dir/VTop test_programs/coremark.elf 1> >(tee logs/coremark.out) 2> >(tee logs/coremark.err) && \
    ./obj_dir/VTop test_programs/dhry_1_O3_no_inline.s 1> >(tee logs/dhry_1_O3_no_inline.out) 2> >(tee logs/dhry_1_O3_no_inline.err) && \
    ./obj_dir/VTop test_programs/dhry_1_O3.s 1> >(tee logs/dhry_1_O3.out) 2> >(tee logs/dhry_1_O3.err) && \
    ./obj_dir/VTop test_programs/dhry_1_O3_inline.s 1> >(tee logs/dhry_1_O3_inline.out) 2> >(tee logs/dhry_1_O3_inline.err) && \
    (timeout 3600 ./obj_dir/VTop test_programs/linux/linux_image.elf --device-tree=test_programs/linux/device_tree.dtb --perfc 1> >(tee logs/linux.out) 2> >(tee logs/linux.err) || { [ $? -eq 124 ] && exit 0; exit $?; }) && \
    tar -czf logs.tar.gz logs \
    " ]
