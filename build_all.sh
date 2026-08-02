#!/bin/sh
# Peutiy-Pi 一键构建 + SD 镜像制作
# 用法: sh build_all.sh [OUTDIR]
# 默认 OUTDIR=/mnt/nvme0n1-4/out

set -e

OUTDIR="${1:-/mnt/nvme0n1-4/out}"
SIZE_MB="${2:-512}"

echo "============================================"
echo "  Peutiy-Pi Build & SD Image Maker"
echo "============================================"

# Step 1: Docker build (编译)
echo ""
echo "=== Step 1/3: docker build ==="
docker build --network=host -t h616_core_build . 2>&1 | tee build.log
echo "=== Build DONE ==="

# Step 2: 提取产物到宿主机
echo ""
echo "=== Step 2/3: Extract artifacts to ${OUTDIR} ==="
mkdir -p "$OUTDIR"
CID=$(docker create h616_core_build)
docker cp "$CID:/out/." "$OUTDIR/"
docker rm "$CID"
echo "=== Artifacts extracted ==="

# Step 3: 用容器制作 SD 镜像 (需要 --privileged 和 /dev)
echo ""
echo "=== Step 3/3: Create SD images ==="
cp sdcard_make/mksdimg.sh "$OUTDIR/"
chmod +x "$OUTDIR/mksdimg.sh"
docker run --rm --privileged \
    -v /dev:/dev \
    -v "$OUTDIR:/out" \
    h616_core_build bash /out/mksdimg.sh "/out" "$SIZE_MB"

echo ""
echo "============================================"
echo "  ALL DONE"
echo "  ${OUTDIR}/sdcard_buildroot.img"
echo "  ${OUTDIR}/sdcard_debian.img"
echo "============================================"
ls -lh "$OUTDIR"/sdcard_*.img
