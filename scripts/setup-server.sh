#!/usr/bin/env bash
#
# D2 服务器初始化脚本
# 在全新 Ubuntu LTS (x86_64) 上安装 guest-components 的编译依赖。
# 用法：bash scripts/setup-server.sh
#
set -euo pipefail

echo "==> 更新 apt 并安装基础编译依赖"
sudo apt-get update
sudo apt-get install -y \
  build-essential pkg-config libssl-dev protobuf-compiler \
  clang libclang-dev cmake git curl ca-certificates \
  musl-tools

echo "==> 安装 Rust 工具链（rust-toolchain.toml 会锁定 1.95.0）"
if ! command -v rustup >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
# 让本脚本内 cargo 立即可用（交互式 shell 由 rustup 写入 ~/.profile 自动加载）
source "$HOME/.cargo/env" 2>/dev/null || true

echo "==> 添加 musl 目标（静态构建用）"
rustup target add x86_64-unknown-linux-musl 2>/dev/null || true

echo "==> 验证版本"
cargo --version
rustc --version
protoc --version

echo "==> 完成。进入仓库根后执行 cargo build 即可。"
echo "    轻量服务器内存小（常见 2G）时建议加 swap 防编译 OOM："
echo "    sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile"
echo "    若要跑 CDH 完整集成测试，再装："
echo "    sudo apt-get install -y lvm2 zfsutils-linux cryptsetup libdevmapper-dev"
