# D2 腾讯云 Ubuntu 连调 Runbook（详细版）

> **目标**：在 Linux x86_64（Ubuntu）上把 D2 涉及的 guest 组件跑起来，完成「自己的服务部署 + 依赖桩」的连调，验证集成管道。**本 runbook 双用途**：① 腾讯云普通 VM（开发/测试，无 TEE）② 真海光 CSV 机密服务器（生产/验明）；两者复用同一套步骤，差异只在少数几处（见步骤 8 迁移映射）。
> **能力边界（测试 VM）**：无 TEE → 无真硬件证据；用 `all`/`none` attester 桩；用 `offline_fs_kbc` 替代外部 KBS（**无需 Beeceptor**）。真 CSV 证明在真机环境用 `csv` attester + 真 Trustee/KBS 达成（见步骤 8）。
> **约定**：命令在 Ubuntu x86_64 上执行；`$` 后为一行命令；凡标注「（确认）」处，以你机器上 `cargo build` 实际产物为准。
> **实测状态**：步骤 0–6 已于 2026-10-22 在腾讯云 2 服务器（Ubuntu 24.04.4，无 TEE）完整跑通，6.1–6.4 验证全过；步骤 7（mock KBS / cc_kbc HTTP 路径）已于 2026-10-23 补测（确认 `POST /kbs/v0/auth` 报文形状、启动顺序须 AA→CDH）。每步命令与结果、问题与解法见 `custom-D2连调执行记录.md`。
> **本版新增**：文首「完整部署与测试流程（照着做）」为线性复现清单；步骤 2 扩为服务器编译详解；步骤 6 每项补「请求参数/返回参数」；附录 C 为接口参数速查。

## 目录

- [完整部署与测试流程（照着做：0 → 验证通过）](#fullflow) ← **第一次照着这份做（全新机从这条开始，跑完 A–E 即通过）**
- ↓↓ 以下「步骤 0–6」是**上面主流程各阶段的详细展开版**（主流程已包含）：**照主流程跑即可，不要从头逐个执行**；只在某步卡住或想看细节时点进去。
- [步骤 0：准备 Ubuntu 环境（系统选型 + 服务器初始化 + 代码上服务器）](#step0)
- [步骤 1：进入仓库并切到开发分支](#step1)
- [步骤 2：构建三个组件（服务器编译详解）](#step2)
- [步骤 3：准备 offline_fs_kbc 资源文件（替代外部 KBS）](#step3)
- [步骤 4：配置 KBC 参数（让 AA/CDH 走 offline_fs_kbc）](#step4)
- [步骤 5：创建运行时目录并启动三个守护进程](#step5)
- [步骤 6：验证（连调检查表 + 请求/返回参数）](#step6)
  - [6.1 ASR REST 探活 + 取资源](#step61)
  - [6.2 image-rs 直连 CDH（验证 kbs:// → offline_fs_kbc 通路）](#step62)
  - [6.3 sealed secret（D2 重点）](#step63)
  - [6.4 AA evidence / token（桩）](#step64)
- [步骤 7（可选）：用 mock KBS 测 cc_kbc 真 HTTP 路径](#step7)
- [步骤 8：从测试 VM 迁移到真海光 CSV（复用本 runbook）](#step8)
- [附录 A：offline_fs_kbc 资源文件格式速查](#appendixa)
- [附录 B：最小 mock KBS（Python，可直接运行）](#appendixb)
- [附录 C：接口请求/返回参数速查](#appendixc)
- [参考文件](#refs)

---

<a id="fullflow"></a>
## 完整部署与测试流程（照着做：0 → 验证通过）

> 本流程是**从一台全新 Ubuntu x86_64 到验证通过**的线性清单，命令可直接复制。每步给出「期望输出 / 判定标准」；对不上就看括号里的详细步骤，或查 `custom-D2连调执行记录.md` 的「问题与解决」。
> 参考环境：腾讯云 2 服务器（3.6 GiB 内存 + 1.9 GiB swap，Ubuntu 24.04.4 x86_64）。参考耗时：环境初始化 5–10 min，首次全树编译 10–15 min，全流程约 30–40 min。

### 阶段 A：准备服务器（对应步骤 0）

> **作用**：准备一台能编译、能跑的服务器环境（系统 / 镜像 / 代码 / 工具链），是后面所有步骤的前提。

> ⚠️ **实操顺序（与下方编号顺序不同，照这个跑）**：
> **A1（配镜像）→ A4（先把代码上服务器）→ A2（setup，脚本在仓库里）→ A3（低内存机加 swap）→ A5（工具链确认）**。
> 原因：A2 的 `scripts/setup-server.sh` 位于仓库内，必须先有代码；按文档编号顺序 A1→A2 会因为脚本不存在而失败。
> 补充：A4 的 `git clone` 依赖 git，而 git 由 A2 的脚本安装——全新最小镜像若没预装 git，A4 会报 `git: command not found`。
> 开跑前先 `which git` 确认；没有就先执行 `sudo apt update && sudo apt install -y git`（重装后的干净机器常见）。

**A1. 系统与镜像**：Ubuntu 24.04 LTS **x86_64**（不要 CentOS / Rocky）。国内服务器**先配镜像**，否则下一步装 rustup 会卡在下载 0 字节：

```bash
# 目录：服务器（任意目录即可；以下为环境变量导出，无需 cd）

# ① 让 rustup 走腾讯云镜像源（DIST_SERVER=工具链下载源；UPDATE_ROOT=自更新源）
#    国内直连 static.rust-lang.org 会被墙，TUNA 镜像可能缺 1.95.0，故用腾讯云
export RUSTUP_DIST_SERVER=https://mirrors.cloud.tencent.com/rustup
export RUSTUP_UPDATE_ROOT=https://mirrors.cloud.tencent.com/rustup/rustup

# ② 让 cargo 从 rsproxy 稀疏索引拉 crates.io 依赖；[net] git-fetch-with-cli=true 让下面的 git 代理生效
mkdir -p ~/.cargo
printf '[source.crates-io]\nreplace-with = "rsproxy-sparse"\n\n[source.rsproxy-sparse]\nregistry = "sparse+https://rsproxy.cn/index/"\n\n[net]\ngit-fetch-with-cli = true\n' > ~/.cargo/config.toml

# ③ 让 git 把 github.com 依赖改为走 ghfast.top 代理拉取，并强制 HTTP/1.1（ghproxy.net 会截断大文件）
printf '[url "https://ghfast.top/https://github.com/"]\n\tinsteadOf = https://github.com/\n[http]\n\tversion = HTTP/1.1\n' > ~/.gitconfig
```

**A2. 装编译依赖 + Rust 工具链**：

```bash
# 目录：仓库根 ~/guest-components（本步需 A4 代码已上服务器后执行）
cd ~/guest-components
# scripts/setup-server.sh：一键安装编译依赖（build-essential/pkg-config/libssl-dev/protobuf-compiler/clang/cmake/musl-tools）
#   并安装 rustup 工具链（锁 1.95.0）+ x86_64-unknown-linux-musl 目标，最后打印 cargo/rustc/protoc 版本
bash scripts/setup-server.sh
```

脚本做的事（`scripts/setup-server.sh`）：
- apt 安装：`build-essential pkg-config libssl-dev protobuf-compiler clang libclang-dev cmake git curl ca-certificates musl-tools`
- 安装 rustup（`rust-toolchain.toml` 自动锁 1.95.0）+ 添加 `x86_64-unknown-linux-musl` 目标
- 期望输出末尾：`cargo --version` / `rustc --version` / `protoc --version` 正常打印

**A3. （低内存机，≤2G）加 swap 防编译 OOM**：

```bash
# 目录：服务器（任意目录即可）
# 低内存机（≤2G）加 2G swap 防编译 OOM：建文件→改权限→格式化 swap→启用→看内存
sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && free -h
```

**A4. 代码上服务器（本地 Mac 执行；当前分支有未推提交，用 bundle）**：

```bash
# Mac 本地
# cd 到仓库根
cd "/Users/shenxutao/MyWorkspace/Docs/机密计算/开发/guest-components"
# git bundle：把分支 2026-10-21-dev 打包成单个文件（当前分支有未推提交、不能用远端 clone 时，靠它把代码带上去）
git bundle create /tmp/gc-dev.bundle 2026-10-21-dev && ls -lh /tmp/gc-dev.bundle
# scp 把打包文件传到服务器家目录
scp /tmp/gc-dev.bundle ubuntu@111.229.159.237:~/

# 服务器
# 从 bundle 还原成仓库并切到开发分支
git clone ~/gc-dev.bundle guest-components && cd guest-components && git checkout 2026-10-21-dev
git log --oneline -3          # 确认分支与本地提交已还原（含 Makefile 的 csv→csv-attester 映射）
```

期望：`git log` 显示你本地最新提交（含 `Makefile` 的 `csv→csv-attester` 映射）。

**A5. 确认工具链**：

```bash
# 目录：服务器（任意目录即可；cargo 已在 PATH）
# 确认工具链版本正确（rust 1.95.0 / protoc 3.21.12），避免后面编译因版本不对踩坑
cargo --version && rustc --version && protoc --version
```

期望：`cargo 1.95.0` / `rustc 1.95.0`（被 `rust-toolchain.toml` 锁定）/ `protoc 3.21.12`。

### 阶段 B：编译（对应步骤 2）

> **作用**：把源码编成 5 个可执行二进制（CDH / AA / ASR / secret / ttrpc-cdh-tool），后面启动与验证都靠它们。

```bash
# 目录：~/guest-components（服务器）
cd ~/guest-components

# B1. 编译 CDH 与 ASR 两个组件（原生 glibc 目标即可，开发期无需静态 musl）
cargo build -p confidential-data-hub -p api-server-rest

# B2. 编译 AA：必须显式带 bin 特性，否则不产出 ttrpc-aa 二进制（--no-default-features 清掉默认、再按需开 kbs/coco_as/bin/ttrpc）
cargo build -p attestation-agent --no-default-features --features "kbs,coco_as,bin,ttrpc"

# B3. 列出 5 个产物，确认编译成功、二进制齐全
ls -lh target/debug/ttrpc-cdh target/debug/api-server-rest target/debug/ttrpc-aa target/debug/secret target/debug/ttrpc-cdh-tool
```

期望：5 个二进制齐全。参考耗时：B1 约 13 分钟，B2 约 50 秒（依赖已缓存）。
**全新机首次编译**需重新下载全部依赖（无 `~/.cargo` 缓存），B1 可能 20–30 分钟，取决于镜像速度，属正常，别中断。
常见失败：① 报 ``target `ttrpc-aa` requires the features `bin` `` → B2 漏了 `bin` 特性；② 编译 OOM → 先做 A3；③ 依赖拉取失败/卡住 → 检查 A1 镜像。

### 阶段 C：配置（对应步骤 3、4、5.0）

> **作用**：准备 offline_fs_kbc 的资源文件（步骤 3/4），并建好运行时目录（步骤 5.0，否则 CDH 启动即权限报错）。

```bash
# 目录：服务器（任意目录即可；文件路径用绝对路径）

# C1. 生成离线资源文件：offline_fs_kbc 要从这个 JSON 取资源，value 必须是 base64（即 my-dev-secret-key-001 / another-secret）
cat > /tmp/dev-resources.json <<'EOF'
{
  "default/key/1": "bXktZGV2LXNlY3JldC1rZXktMDAx",
  "default/key/2": "YW5vdGhlci1zZWNyZXQ="
}
EOF
cat /tmp/dev-resources.json          # 打印确认写对了

# C2. 建运行时目录（socket / 凭据路径）：非 root 运行必须 chown 给当前用户，否则 CDH 启动即 Permission denied
sudo mkdir -p /run/confidential-containers
sudo chown -R "$(id -un):$(id -gn)" /run/confidential-containers
```

### 阶段 D：启动（对应步骤 5，顺序 CDH → AA → ASR）

> **作用**：把 CDH / AA / ASR 三个守护进程按正确顺序拉起来，它们是机密数据分发与证明的核心服务。

```bash
# 目录：~/guest-components（服务器）
cd ~/guest-components

# 启动 CDH：AA_KBC_PARAMS 指定用离线 KBC（不连远端）；OFFLINE_FS_KBC_EXTRA_FILE_PATH 指向步骤 3 的资源文件
#   nohup ... & 后台运行；stdout/stderr 重定向到日志；CDH 起好会监听 cdh.sock
AA_KBC_PARAMS="offline_fs_kbc::null" OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json" \
  nohup ./target/debug/ttrpc-cdh > ~/cdh.log 2>&1 &
# 启动 AA（证明代理）：同样用离线 KBC
AA_KBC_PARAMS="offline_fs_kbc::null" nohup ./target/debug/ttrpc-aa  > ~/aa.log  2>&1 &
# 启动 ASR（REST 网关）：--features all 是 ASR 二进制 CLI 参数（开 resource+attestation），监听 127.0.0.1:8006
nohup ./target/debug/api-server-rest --features all > ~/asr.log 2>&1 &
# 等 1s 后看三个进程各自的启动日志尾巴，确认无报错
sleep 1; tail -n 5 ~/cdh.log ~/aa.log ~/asr.log
# 确认 ASR 确实在 8006 监听（仅 loopback）
ss -tlnp | grep 8006
```

期望：`/run/confidential-containers/cdh.sock` 生成；`ss` 显示 `LISTEN 127.0.0.1:8006`（仅 loopback）。

### 阶段 E：验证（对应步骤 6；请求/返回参数见附录 C）

> **作用**：端到端验证全链路——探活、取资源、sealed secret 信封机制、AA 证据接口，全部通过即代表部署与连调成功。

```bash
# 目录：~/guest-components（服务器）；本块命令在同一 shell 内顺序执行
cd ~/guest-components

# E1 探活：问 ASR 它自身的版本/tee/feature，确认服务活着、且是我们要的构建
curl -s http://127.0.0.1:8006/info
# 期望：{"version":"Guest Components Version: <HEAD>","tee":"sample","feature":"all"}

# E2 取资源：让 ASR→CDH→offline_fs_kbc 把 key/1、key/2 取回来，验证资源链路通
curl -s http://127.0.0.1:8006/cdh/resource/default/key/1   # 期望：my-dev-secret-key-001
curl -s http://127.0.0.1:8006/cdh/resource/default/key/2   # 期望：another-secret

# E3 直连 CDH：用纯 socket 客户端（不经 ASR）直接问 CDH 要资源，验证 CDH socket 通、资源可读（无需任何 env）
./target/debug/ttrpc-cdh-tool get-resource --resource-uri "kbs:///default/key/1"
# 期望：bXktZGV2LXNlY3JldC1rZXktMDAx

# E4 sealed secret 全链路：keygen 生成签名密钥 → seal 把资源封进信封 → unseal 解封，验证签名/信封机制
mkdir -p /tmp/secrets /run/confidential-containers/cdh/sealed-secret
./target/debug/secret keygen --kid my-key --output-dir /tmp/secrets
cp /tmp/secrets/my-key-public.json /run/confidential-containers/cdh/sealed-secret/my-key
./target/debug/secret seal --signing-kid my-key --signing-jwk-path /tmp/secrets/my-key-private.json \
  vault --resource-uri "kbs:///default/key/1" --provider kbs | tail -n +2 > /tmp/sealed-secret.txt
AA_KBC_PARAMS="offline_fs_kbc::null" OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json" \
  ./target/debug/secret unseal --file-path /tmp/sealed-secret.txt --aa-kbc-params "offline_fs_kbc::null"
cat /tmp/sealed-secret.txt.unsealed   # 期望：my-dev-secret-key-001

# E5 AA evidence：向 AA 要一份"证据"（桩），验证 AA 的 evidence 接口返回形状正确
curl -s "http://127.0.0.1:8006/aa/evidence?runtime_data=test"   # 期望：{"report_data":"dGVzdA==","svn":"1"}
```

**判定**：E1–E5 全部符合期望 → 部署与连调通过。

### 阶段 F（可选）：mock KBS 测 cc_kbc 真 HTTP 路径（对应步骤 7）

见「步骤 7 / 附录 B」。**注意启动顺序改为 AA → CDH**（cc_kbc 模式下 CDH 启动要连 AA 的 ttrpc socket）。

### 阶段 G：迁移真机（对应步骤 8）

把 `attester` 换成 `csv`、KBC 指向真 KBS、密钥由 Trustee 预置，其余流程不变；详见步骤 8 与 `custom-真机CSV部署.md`。

---

## 速查（TL;DR）

最小可跑通路径（测试 VM；命令在 Ubuntu x86_64 上执行）：

```bash
# ⚠️ 本速查把「Mac 打包」(步骤2 的 git bundle/scp) 与「服务器编译/运行」(步骤1、3–6) 混在一个块里：
#   · 步骤 1 的 bash scripts/setup-server.sh 与 步骤 3–6 都在【服务器、目录 ~/guest-components】执行
#   · 步骤 2 的 git bundle / scp 在【Mac 本地】执行（先 cd 到仓库根）
# 1) 装环境（服务器，目录 ~/guest-components；国内服务器必须先配镜像，见步骤 0.1）
cd ~/guest-components
bash scripts/setup-server.sh

# 2) 取代码（Mac 本地执行；先 cd 到仓库根）
cd "/Users/shenxutao/MyWorkspace/Docs/机密计算/开发/guest-components"
git bundle create /tmp/gc-dev.bundle 2026-10-21-dev && scp /tmp/gc-dev.bundle ubuntu@111.229.159.237:~/
#   服务器上：git clone ~/gc-dev.bundle guest-components && cd guest-components && git checkout 2026-10-21-dev

# 3) 构建（回到服务器、目录 ~/guest-components；AA 必须带 bin 特性才产出 ttrpc-aa；首编全树约 10–15 分钟）
cd ~/guest-components
cargo build -p confidential-data-hub -p api-server-rest
cargo build -p attestation-agent --no-default-features --features "kbs,coco_as,bin,ttrpc"

# 4) 准备 KBC 资源（生成 dev-resources.json 见步骤 3）+ 运行时目录
export AA_KBC_PARAMS="offline_fs_kbc::null"
export OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json"
sudo mkdir -p /run/confidential-containers && sudo chown -R "$(id -un):$(id -gn)" /run/confidential-containers

# 5) 启动（后台方式；完整说明与坑见步骤 5）
AA_KBC_PARAMS="offline_fs_kbc::null" OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json" \
  nohup ./target/debug/ttrpc-cdh > ~/cdh.log 2>&1 &
AA_KBC_PARAMS="offline_fs_kbc::null" nohup ./target/debug/ttrpc-aa > ~/aa.log 2>&1 &
nohup ./target/debug/api-server-rest --features all > ~/asr.log 2>&1 &

# 6) 验证
curl -s http://127.0.0.1:8006/info
curl -s http://127.0.0.1:8006/cdh/resource/default/key/1    # 期望：my-dev-secret-key-001
```

> 真海光 CSV 部署：把上表的 attester 换成 `csv`、KBC 指向真 KBS 即可。完整真机步骤见 `custom-真机CSV部署.md` 与下方步骤 8 迁移映射。

## 图例与约定

- 命令默认在 **Ubuntu x86_64** 上执行；行首 `$` 表示一条命令（实际粘贴时去掉 `$`）。
- 每个命令块开头用 `# 目录：…` 标注**当前工作目录**与**执行机**（如 `# 目录：~/guest-components（服务器）`、`# 目录：仓库根 …（Mac 本地）`）；凡含相对路径（`./target/debug/…`、`cargo …`、`bash scripts/…`）的块都已在其内部 `cd` 到对应目录，可整块直接复制执行。
- 代码块内 `#` 开头为注释，可忽略；较长的解释放在代码块后的「说明」里。
- 标注「（确认）」处：以你机器上 `cargo build` 实际产物 / 文件实际内容为准（本文为核实自源码的参考值）。
- 两个核心环境变量：
  - `AA_KBC_PARAMS`：格式 `KBC名::KBS_URI`，决定 AA/CDH 走哪个 KBC（本文 `offline_fs_kbc::null`，真机 `cc_kbc::https://<kbs>`）。
  - `OFFLINE_FS_KBC_EXTRA_FILE_PATH`：`offline_fs_kbc` 额外资源文件路径。

## 步骤一览

| 阶段 | 步骤 | 目的 |
|---|---|---|
| 准备 | 0 | 选系统、初始化服务器、把当前分支代码上服务器 |
| 构建 | 1–2 | 进分支、编译三个组件 |
| 配置 | 3–4 | 准备 offline_fs_kbc 资源、配置 KBC 参数 |
| 运行 | 5 | 起 CDH → AA → ASR 三个守护进程 |
| 验证 | 6 | 取资源 / 直连 CDH / sealed secret / evidence 桩 |
| 可选 | 7 | 用 mock KBS 测 cc_kbc 真 HTTP 路径 |
| 迁移 | 8 | 测试 VM → 真海光 CSV 的差异映射与检查表 |

<a id="step0"></a>
## 步骤 0：准备 Ubuntu 环境（系统选型 + 服务器初始化 + 代码上服务器）

> 📖 **本节是主流程「阶段 A：准备服务器」的详细展开**——照主流程跑无需重复执行；本节用于某步卡住时查细节。

**0.0 系统选型（重装系统时）**
- 发行版：Ubuntu LTS（**24.04 首选**；26.04 LTS 也可用但较新、生产验证少）；**不要选 CentOS / Rocky**（Makefile 的 `DebianOS` 检测不触发，依赖要手搓）
- 架构：**x86_64**（项目 TEE attester 均为 x86 平台，CSV 是海光 x86）；**避开 ARM / 鲲鹏**
- 镜像类型：基于操作系统镜像（干净系统）

**0.1 服务器初始化（一键脚本）**
```bash
# 目录：仓库根 ~/guest-components（服务器；需代码已上服务器，见 0.2）
cd ~/guest-components
# 在腾讯云 Ubuntu x86_64 上执行（装 rustup 1.95.0 + 编译依赖 + musl 目标）
bash scripts/setup-server.sh
```
脚本见 `scripts/setup-server.sh`：装 `build-essential`/`pkg-config`/`libssl-dev`/`protobuf-compiler`/`clang`/`libclang-dev`/`cmake`/`musl-tools`，装 rustup 并加 `x86_64-unknown-linux-musl` 目标。
> 轻量服务器内存小（常见 2G）时建议加 2G swap 防编译 OOM：`sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`

> **国内服务器必做（腾讯云等；2026-10-22 已在 2 服务器实测）**：`static.rust-lang.org` 与 `github.com` 在国内基本不可达——脚本会在「装 rustup」步卡死（下载 0 字节），后续 cargo 拉 git 依赖也会失败。先配好镜像再跑脚本（或脚本卡住后补配再重跑）：
> ```bash
> # ① rustup 工具链走腾讯云镜像（TUNA 同步滞后、可能缺 1.95.0，勿用；官方源被墙）
> export RUSTUP_DIST_SERVER=https://mirrors.cloud.tencent.com/rustup
> export RUSTUP_UPDATE_ROOT=https://mirrors.cloud.tencent.com/rustup/rustup
> # ② crates.io 走 rsproxy 稀疏索引 + cargo 改用 git CLI 拉依赖（③的 insteadOf 才生效）
> mkdir -p ~/.cargo
> printf '[source.crates-io]\nreplace-with = "rsproxy-sparse"\n\n[source.rsproxy-sparse]\nregistry = "sparse+https://rsproxy.cn/index/"\n\n[net]\ngit-fetch-with-cli = true\n' > ~/.cargo/config.toml
> # ③ GitHub git 依赖走 ghfast.top 代理，并强制 HTTP/1.1（ghproxy.net 会截断大文件，勿用）
> printf '[url "https://ghfast.top/https://github.com/"]\n\tinsteadOf = https://github.com/\n[http]\n\tversion = HTTP/1.1\n' > ~/.gitconfig
> ```
> 原因：本仓库有多个 GitHub git 依赖（`occlum/occlum`、`intel/…tee.dcap`、`NVIDIA/attestation-sdk`、`mdaffin/loopdev`），occlum 还带子模块（teaclave-sgx-sdk 等），**cargo 解析阶段就要拉全**，不配代理直接失败。rustup-init 可从镜像下载：`https://mirrors.cloud.tencent.com/rustup/rustup/dist/x86_64-unknown-linux-gnu/rustup-init`。

**0.2 把「当前分支」代码带到服务器（本地 Mac 执行）**
当前分支 `2026-10-21-dev` 有未推提交，不能用远端 clone；用 `git bundle`：
```bash
# Mac 上：打包分支（含全部本地提交）
cd "/Users/shenxutao/MyWorkspace/Docs/机密计算/开发/guest-components"
git bundle create /tmp/gc-dev.bundle 2026-10-21-dev
scp /tmp/gc-dev.bundle ubuntu@111.229.159.237:~/
```
```bash
# 服务器上：从 bundle 还原
git clone ~/gc-dev.bundle guest-components
cd guest-components
git checkout 2026-10-21-dev
git log --oneline -3          # 确认分支与本地提交已还原（含 Makefile 补 csv→csv-attester 那条）
```

**0.3 确认工具链版本**
```bash
# 目录：服务器（任意目录即可；cargo 已在 PATH）
cargo --version && rustc --version && protoc --version
# rustc 期望含 1.95.0（仓库 rust-toolchain.toml 自动锁定）
```

**说明**
- `rustup`：Rust 工具链管理器；本仓库 `rust-toolchain.toml` 已固定 1.95.0，`cd` 进仓库会自动切换。
- `build-essential`：提供 `gcc`/`make` 等原生编译工具。
- `pkg-config` + `libssl-dev`：OpenSSL 是本仓库加密后端的**固定依赖**（非可选项），编译期需要其头文件与链接库。
- `protobuf-compiler`：`protos` 仓库用它生成 ttrpc / gRPC 的 Rust 绑定代码。
- `clang`：部分 TEE 绑定在构建时需要（如 bindgen 生成的 C FFI 包装 / ioctl 包装）。
- 若改用能联网时推送再 clone：`git push origin 2026-10-21-dev` 后 `git clone -b 2026-10-21-dev <你的fork>`。
- 服务器是普通 VM、非海光 CSV 机密机：`TEE_PLATFORM=csv` 能**编译**但运行拿不到 `/dev/csv-guest` 出不了真证据；真 CSV 验明需海光硬件（见步骤 8）。

---

<a id="step1"></a>
## 步骤 1：进入仓库并切到开发分支

> 📖 **本节对应主流程「阶段 A」的 A4**（代码上服务器 + 切分支）——照主流程跑无需重复执行。

```bash
# 目录：服务器、仓库根 ~/guest-components 的父目录（已 clone 后）
cd guest-components                         # 进入你 clone 的仓库根
git checkout 2026-10-21-dev                # 你的个人 dev 分支
git status -sb                              # 确认领先/落后状态
```

**说明**：所有改动在个人 fork 的 `2026-10-21-dev` 分支进行（与远端 `origin` 同步策略见 `custom-项目理解.md`）。

<a id="step2"></a>
## 步骤 2：构建三个组件（服务器编译详解）

> 📖 **本节是主流程「阶段 B：编译」的详细展开**——照主流程跑无需重复执行；本节用于编译报错时排查。

> 目标产物集中在 `target/debug/`：`ttrpc-cdh`、`api-server-rest`、`ttrpc-aa`、`secret`、`ttrpc-cdh-tool`。

**2.0 前置检查**（首次编译前确认）：

```bash
cd ~/guest-components
cargo --version && rustc --version && protoc --version   # 期望 1.95.0 / 1.95.0 / 3.21.12
free -h                                                  # 内存 < 2G 建议先加 swap（见步骤 0.1）
df -h ~                                                  # 至少留 10G（target/ 较大）
```

**2.1 构建 CDH + ASR（原生 glibc，开发期免 musl）**：

```bash
# 目录：~/guest-components（服务器）
cd ~/guest-components
cargo build -p confidential-data-hub -p api-server-rest
```

**2.2 构建 AA（必须显式带 `bin` 特性，否则不产出 `ttrpc-aa`）**：

```bash
# 目录：~/guest-components（服务器）
cd ~/guest-components
cargo build -p attestation-agent --no-default-features --features "kbs,coco_as,bin,ttrpc"
```

**2.3 校验产物**：

```bash
# 目录：~/guest-components（服务器）
cd ~/guest-components
ls -lh target/debug/ttrpc-cdh target/debug/api-server-rest target/debug/ttrpc-aa \
       target/debug/secret target/debug/ttrpc-cdh-tool
file target/debug/ttrpc-cdh    # 期望：ELF 64-bit LSB executable, x86-64
```

**2.4 参考耗时**（2 服务器实测，3.6G 内存 + swap）：2.1 约 **13 分钟**（首次全树）；2.2 约 **50 秒**（依赖已缓存）。

**2.5 常见构建失败**：

| 现象 | 原因 | 处理 |
|---|---|---|
| ``target `ttrpc-aa` requires the features `bin` `` | AA 漏了 `bin` 特性 | 用 2.2 的完整特性集 |
| 进程被 `killed` / OOM | 内存不足 | 加 swap（步骤 0.1 A3） |
| 依赖拉取卡住 / `transfer closed` | 国内网络 | 配步骤 0.1 的三方镜像 |
| `tss2.pc not found` | 编入了 tpm-attester | 测试 VM 用最小特性集；真机再 `sudo apt install libtss2-dev` |
| `Blocking waiting for file lock` | 上次 cargo 进程残留 | `pkill -f 'bi[n]/cargo'` 后重试 |

**说明**
- `cargo build` 默认原生目标 `x86_64-unknown-linux-gnu`，**不需要 musl 交叉工具链**；musl 静态链接仅用于最终打包进 guest 镜像，开发期可跳过。
- 二进制命名两种口径：**cargo 口径** AA 为 `ttrpc-aa`/`grpc-aa`（`attestation-agent/attestation-agent/Cargo.toml:9-19`）、**CDH 为 `ttrpc-cdh`（不是包名）**、ASR 为 `api-server-rest`；**Makefile 口径**（`Makefile:53-55`）产物名为 `confidential-data-hub`/`attestation-agent`/`api-server-rest`。
- 想贴近 CI / 产出静态二进制：
  ```bash
  make build TEE_PLATFORM=all LIBC=gnu
  ```
  > `Makefile` 已补 `csv → csv-attester` 映射（`Makefile:36-37`），可直接 `TEE_PLATFORM=csv` 构建 CSV attester。
- 不带任何 attester 特性时，AA 运行期 `detect_tee_type()` 自动回退 sample attester（测试 VM 正合适）。

<a id="step3"></a>
## 步骤 3：准备 offline_fs_kbc 资源文件（替代外部 KBS）

> 📖 **本节对应主流程「阶段 C：配置」的 C1**（生成离线资源文件）——照主流程跑无需重复执行。

**背景**：AA/CDH 通过 KBC 取资源/密钥，**默认 KBC 就是 `offline_fs_kbc`**（`attestation-agent/attestation-agent/src/config/aa_kbc_params.rs:23`，取不到时回退 `offline_fs_kbc::null` `:63`）。它从**本地 JSON 文件**读取资源，因此本地连调**完全不需要 Beeceptor / 真 Trustee**。

资源文件格式（来自 `confidential-data-hub/kms/src/plugins/kbs/offline_fs.rs:71-87` 解析逻辑）：
```json
{ "<resource_path>": "<base64(value)>" }
```
测试样例见 `offline_fs.rs:147-151`，resource_path 形如 `default/key/1`（对应 `kbs:///default/key/1`）。

```bash
# 3.1 生成开发用资源文件：把明文值 base64 后写入
cat > /tmp/dev-resources.json <<'EOF'
{
  "default/key/1": "$(printf '%s' 'my-dev-secret-key-001' | base64)",
  "default/key/2": "$(printf '%s' 'another-secret'      | base64)"
}
EOF

# 3.2 确认内容（value 应为 base64 串）
cat /tmp/dev-resources.json
```

**说明**
- `resource_path` 与后续 `kbs:///default/key/1` 这类 URI 一一对应；`value` **必须是 base64**。
- 也可用仓库自带脚本安装到 `/etc`（会顺带写 `/etc/agent-config.toml` 设 `offline_fs_kbc::null`）：
  ```bash
  sudo bash image-rs/scripts/install_offline_fs_kbc_files.sh install
  ```

<a id="step4"></a>
## 步骤 4：配置 KBC 参数（让 AA/CDH 走 offline_fs_kbc）

> 📖 **本节对应主流程「阶段 C：配置」的 KBC 参数说明**——照主流程跑无需重复执行。

**背景**：KBC 由环境变量 `AA_KBC_PARAMS`（格式 `KBC_NAME::KBS_URI`）或 `/etc/agent-config.toml` 指定；也可经内核 cmdline `agent.aa_kbc_params=`。

```bash
export AA_KBC_PARAMS="offline_fs_kbc::null"
export OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json"
```

**说明**
- `offline_fs_kbc::null`：用离线 KBC，不连任何外部 KBS（`null` 表示无远端 URI）。这恰好是 `aa_kbc_params.rs:63` 的默认回退值。
- `OFFLINE_FS_KBC_EXTRA_FILE_PATH`：让 `offline_fs_kbc` 额外从指定文件加载资源（`offline_fs.rs:24` 定义该环境变量，`:53` 读取；多个文件用 `,` 分隔），免改 `/etc` 下的默认文件。
- **每个启动组件的终端都要先 `export` 这两个变量**（或写进同一 shell / systemd unit）。

---

<a id="step5"></a>
## 步骤 5：创建运行时目录并启动三个守护进程

> 📖 **本节是主流程「阶段 D：启动」的详细展开**（含 5.0 运行时目录）——照主流程跑无需重复执行。

**背景**
- CDH 监听 Unix socket `unix:///run/confidential-containers/cdh.sock`（image-rs 客户端约定，见 `image-rs/src/resource/kbs/ttrpc.rs:16`）。
- ASR 监听 `127.0.0.1:8006`（loopback，非 loopback 访问返回 403）。
- 启动顺序建议：**CDH → AA → ASR**（ASR 是 REST 网关，依赖后两者）。

```bash
# 目录：~/guest-components（服务器；cargo run 需在仓库根）
cd ~/guest-components
# 5.0 创建运行时目录（socket / 凭据路径）
sudo mkdir -p /run/confidential-containers
# 以非 root 用户运行时必须把属主交给该用户，否则 CDH/AA 启动即
# "failed to create /run/confidential-containers/cdh: Permission denied"：
sudo chown -R "$(id -un):$(id -gn)" /run/confidential-containers

# 5.1 启动 CDH（机密数据中枢）
AA_KBC_PARAMS="offline_fs_kbc::null" \
OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json" \
cargo run -p confidential-data-hub --bin ttrpc-cdh
# 说明：cargo 口径的 bin 名是 ttrpc-cdh（make build 产物才叫 confidential-data-hub，Makefile:53-55）
#      启动后监听 cdh.sock；若 socket 冲突，先 sudo rm -f /run/confidential-containers/cdh.sock

# 5.2 启动 AA（证明代理，ttrpc 服务）
AA_KBC_PARAMS="offline_fs_kbc::null" \
cargo run -p attestation-agent --no-default-features --features "kbs,coco_as,bin,ttrpc" --bin ttrpc-aa
# 说明：必须带 bin 特性（否则 cargo 报 "target `ttrpc-aa` requires the features `bin`"）
#      非 TEE 机器：启动日志提示回退 sample attester，evidence 返回桩数据，属预期

# 5.3 启动 ASR（REST 网关）
cargo run -p api-server-rest -- --features all
# 说明：--features all 是 ASR 二进制自己的 CLI 参数（resource+attestation 全开），必须经 `--` 传给二进制；
#      它不是 cargo 特性（ASR 的 Cargo.toml 无 [features] 段），放到 `--` 之前会报
#      "none of the selected packages contains these features: all"
#      监听 127.0.0.1:8006；仅 loopback，外部访问 403
```

**说明**
- 建议三个组件各开一个终端（或 `nohup ... &` / systemd unit 后台运行），便于看日志。
- 上述 **CDH → AA → ASR** 顺序适用于 `offline_fs_kbc`；若走 `cc_kbc`（连真/假 KBS，见步骤 7），必须改成 **AA → CDH**，否则 CDH 初始化时连不上 AA socket 会启动失败。实测后台做法（日志在 `~/cdh.log`、`~/aa.log`、`~/asr.log`）：`AA_KBC_PARAMS="offline_fs_kbc::null" OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json" nohup ./target/debug/ttrpc-cdh > ~/cdh.log 2>&1 &`（AA/ASR 同理，ASR 记得带 `--features all`）。
- 用 `make build` 产出的二进制时，把 `cargo run -p X --bin Y` 换成直接执行 `./target/x86_64-unknown-linux-gnu/release/<bin>` 并前置同样的环境变量。

---

<a id="step6"></a>
## 步骤 6：验证（连调检查表）

> 📖 **本节是主流程「阶段 E：验证」的详细展开**（含各接口请求/返回参数）——照主流程跑无需重复执行。

<a id="step61"></a>
### 6.1 ASR REST 探活 + 取资源
```bash
curl -s http://127.0.0.1:8006/info
curl -s http://127.0.0.1:8006/cdh/resource/default/key/1
```

**请求参数**

| 接口 | 方法 | 参数 | 必填 | 说明 |
|---|---|---|---|---|
| `/info` | GET | 无 | — | 返回版本与 TEE 信息 |
| `/cdh/resource/{repository}/{type}/{tag}` | GET | `repository` / `type` / `tag`（路径参数） | 是 | 拼成资源路径，如 `default/key/1` 对应 `kbs:///default/key/1` |

**返回参数**

| 接口 | 状态码 | 返回体 | 示例 |
|---|---|---|---|
| `/info` | 200 | JSON `VersionInfo`：`version`（含 HEAD）、`tee`、`feature`、`additional_tees` | `{"version":"Guest Components Version: 8d68afe8","tee":"sample","feature":"all"}` |
| `/cdh/resource/...` | 200 | `application/octet-stream`，资源明文 | `my-dev-secret-key-001` |
| `/cdh/resource/...` | 403 | 非 loopback 访问被拒 | — |
| `/cdh/resource/...` | 500 | 资源不存在（如 `default/key/99`）或空路径 | `ttrpc request error` |

<a id="step62"></a>
### 6.2 image-rs 直连 CDH（验证 kbs:// → offline_fs_kbc 通路）

```bash
# 目录：~/guest-components（服务器）
cd ~/guest-components
# 二选一：已编好二进制
./target/debug/ttrpc-cdh-tool get-resource --resource-uri "kbs:///default/key/1"
# 或走 cargo
cargo run -p confidential-data-hub --bin ttrpc-cdh-tool -- \
  get-resource --resource-uri "kbs:///default/key/1"
```

**请求参数**（`ttrpc-cdh-tool`，`confidential-data-hub/hub/src/bin/ttrpc-cdh-tool.rs`）

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `get-resource`（子命令） | 是 | — | kebab-case，不是 `GetResource` |
| `--resource-uri` | 是 | — | 资源 URI，如 `kbs:///default/key/1` |
| `--socket` | 否 | `unix:///run/confidential-containers/cdh.sock` | CDH 的 ttrpc socket |

**返回参数**

| 场景 | 输出 |
|---|---|
| 成功 | base64 串，如 `bXktZGV2LXNlY3JldC1rZXktMDAx`（= `my-dev-secret-key-001`） |
| 资源不存在 | 报错退出，非 0 |

> 该工具是**纯 socket 客户端**：资源由 CDH 侧的环境变量决定，故**不带 `AA_KBC_PARAMS` / `OFFLINE_FS_KBC_EXTRA_FILE_PATH` 也能取到值**。

<a id="step63"></a>
### 6.3 sealed secret（D2 重点）
**背景**：CDH 用「JWS(ES256) 签名 + 数字信封/Vault 引用」封装密钥（完整机制见 `custom-CDH-SealedSecret.md`）。**二进制名是 `secret`**（非 `secret_cli`），调用 `cargo run -p confidential-data-hub --bin secret -- <子命令>`。

**本地端到端（Vault + offline_fs_kbc，走真验签）**：
```bash
# 目录：~/guest-components（服务器；cargo run 需在仓库根）
cd ~/guest-components
# 0) keygen 不会自建目录，先建输出目录（漏这步会 panic: Failed to write .../my-key-private.json）
mkdir -p /tmp/secrets /run/confidential-containers/cdh/sealed-secret

# 1) 生成 P-256 签名密钥对（JWK；参数是 kebab-case）
cargo run -p confidential-data-hub --bin secret -- keygen --kid my-key --output-dir /tmp/secrets

# 2) 放验签公钥到 SIGNING_CREDENTIALS_PATH/<kid>
#    （= /run/confidential-containers/cdh/sealed-secret/my-key，hub/src/secret/mod.rs:29；
#      目录已按 5.0 chown 则不需要 sudo）
cp /tmp/secrets/my-key-public.json /run/confidential-containers/cdh/sealed-secret/my-key

# 3) 密封一个指向 KBS 资源的 Vault secret（vault 是 seal 的子命令，不是 --type 参数）
#    坑：vault 的 seal 会先往 stdout 打一行 "Warning: Secrets must be provisioned to provider separately."，
#        必须 tail -n +2 滤掉，否则解封报 ParseFailed("Failed to parse JWS")；
#        产物本身带 sealed. 前缀，解封端会自动 trim 掉，不用手动处理
cargo run -p confidential-data-hub --bin secret -- \
  seal --signing-kid my-key --signing-jwk-path /tmp/secrets/my-key-private.json \
  vault --resource-uri "kbs:///default/key/1" --provider kbs \
  | tail -n +2 > /tmp/sealed-secret.txt

# 4) 解封（--aa-kbc-params 让 kbs provider 走 offline_fs_kbc；验签公钥来自步骤 2 的文件；
#    --key-path 仅对 aliyun/aws provider 有意义，kbs 不用传）
AA_KBC_PARAMS="offline_fs_kbc::null" \
OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json" \
cargo run -p confidential-data-hub --bin secret -- \
  unseal --file-path /tmp/sealed-secret.txt --aa-kbc-params "offline_fs_kbc::null"

cat /tmp/sealed-secret.txt.unsealed   # 应等于 my-dev-secret-key-001
```
**子命令与参数**（`confidential-data-hub/hub/src/bin/secret_cli.rs`）

| 子命令 | 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|---|
| `keygen` | `--kid` | 否 | `sealed-signing` | 写进 JWK 的 kid |
| `keygen` | `--output-dir` | 否 | `.` | 输出目录（**不自建**，需先 `mkdir -p`） |
| `seal` | `--signing-kid` | 是 | — | 签名 key 的 kid（解封时按此找公钥） |
| `seal` | `--signing-jwk-path` | 是 | — | 含私钥的 JWK 文件 |
| `seal … vault` | `--resource-uri` | 是 | — | 指向的资源 URI，如 `kbs:///default/key/1` |
| `seal … vault` | `--provider` | 是 | — | 取资源的 provider，如 `kbs` |
| `seal … vault` | `--provider-settings` / `-a`（annotations） | 否 | — | JSON 字典，高级用法 |
| `unseal` | `--file-path` / `-f` | 是 | — | 待解封文件 |
| `unseal` | `--key-path` / `-k` | 否 | — | 仅 `aliyun`/`aws` provider 需要 |
| `unseal` | `--aa-kbc-params` / `-a` | 否 | — | `kbs` provider 用它指定 KBC，如 `offline_fs_kbc::null` |
| `unseal` | `--skip-verification` | 否 | false | 跳过验签（仅调试） |

**返回/产物**

| 子命令 | 产物 |
|---|---|
| `keygen` | `-private.json`（含 `d`）/ `-public.json`（`alg:ES256, use:sig`） |
| `seal … vault` | stdout 先打一行 `Warning: Secrets must be provisioned to provider separately.`，随后是 `sealed.` 前缀的 base64 JWS（**须 `tail -n +2`**） |
| `unseal` | 生成 `<file-path>.unsealed`，内容为资源明文 |

**说明**：信封格式、Envelope/Vault 区别、`kid` 寻址、`unseal --skip-verification`（跳过验签）等见 `custom-CDH-SealedSecret.md`；`/tmp/dev-resources.json` 来自步骤 3（含 `default/key/1`）。

<a id="step64"></a>
### 6.4 AA evidence / token（桩）

```bash
curl -s "http://127.0.0.1:8006/aa/evidence?runtime_data=test"
curl -s "http://127.0.0.1:8006/aa/evidence?runtime_data=dGVzdA&encoding=base64"
curl -s "http://127.0.0.1:8006/aa/token?token_type=kbs"
```

**请求参数**（`api-server-rest/openapi/api.json`）

| 接口 | 方法 | 参数 | 必填 | 说明 |
|---|---|---|---|---|
| `/aa/evidence` | GET | `runtime_data` | 是 | 挑战数据；不带则 `BAD REQUEST` |
| `/aa/evidence` | GET | `encoding` | 否 | 传 `base64` 表示 `runtime_data` 是 URL-safe base64（无 padding） |
| `/aa/token` | GET | `token_type` | 是 | 仅 `kbs` / `coco_as`（传 `default` 报 `Unsupported token type`） |

**返回参数**

| 接口 | 状态码 | 返回体 | 示例 |
|---|---|---|---|
| `/aa/evidence` | 200 | JSON：`report_data`（base64(runtime_data)）、`svn` | `{"report_data":"dGVzdA==","svn":"1"}` |
| `/aa/evidence` | 400 | 缺 `runtime_data` | `BAD REQUEST` |
| `/aa/token` | 200 | JSON：`token`、`tee_keypair`（真 KBS/真 TEE 才有合法 token） | `{"token":"eyJ...","tee_keypair":"-----BEGIN..."}` |
| `/aa/token` | 400 | 非法 token_type | `Unsupported token type` |

> `offline_fs_kbc` 下没有真 KBS 端点发 token，`/aa/token` 返回明确错误属预期；真机 + 真 KBS 才出合法 token。

<a id="step7"></a>
## 步骤 7（可选）：用 mock KBS 测 cc_kbc 真 HTTP 路径

**背景**：仅当你想验证 `cc_kbc::https://<mock>` 这条「AA → 真 KBS 形态」的客户端 HTTP 行为时才需要（替代 Beeceptor）。**只验证请求/响应形状，不做真证明**（无 RCAR challenge/response 握手）。

```bash
# 目录：~/guest-components（服务器）
cd ~/guest-components

# 7.0 先把 mock 脚本落盘（全新机上没有这个文件）：把「附录 B」的 Python 代码保存为 ~/mock-kbs.py
#     注意：脚本内 LOG 写死 /home/ubuntu/mock-kbs.log，若登录用户名不是 ubuntu 要改成你的家目录

# 7.1 起 mock KBS（监听 127.0.0.1:8080）
# 注意：仓库里没有 `mock-kbs` 这个 bin（旧写法 `cargo run --bin mock-kbs` 会报错）；
#      用附录 B 的 Python mock，落盘为 ~/mock-kbs.py；请求全量记入 ~/mock-kbs.log
python3 ~/mock-kbs.py &

# 7.2 自检桩本身可用（应返回 Challenge JSON）
curl -s -X POST http://127.0.0.1:8080/kbs/v0/auth -H "Content-Type: application/json" -d '{}'

# 7.3 让 AA/CDH 走这个桩 —— 顺序必须是 AA → CDH（见下方说明）
AA_KBC_PARAMS="cc_kbc::http://127.0.0.1:8080" nohup ./target/debug/ttrpc-aa  > ~/aa-cckbc.log  2>&1 &
sleep 2
AA_KBC_PARAMS="cc_kbc::http://127.0.0.1:8080" nohup ./target/debug/ttrpc-cdh > ~/cdh-cckbc.log 2>&1 &

# 7.4 触发一次取资源，然后看 mock 收到了什么
curl -s -m 25 -w "\n[HTTP %{http_code}]\n" http://127.0.0.1:8006/cdh/resource/default/key/1
cat ~/mock-kbs.log

# 7.5 测完恢复离线环境：按步骤 5 用 offline_fs_kbc 重启 AA / CDH
```

**实测结果（2026-10-23，腾讯云 2 服务器）**
- mock 收到**真实请求**：`POST /kbs/v0/auth`，body =
  `{"version":"0.4.0","tee":"sample","extra-params":{"supported-hash-algorithms":["sha256","sha384","sha512","sm3"]}}`
  （共 5 次重试、间隔 1s）→ **cc_kbc 的 HTTP 通路确实打通**，端点与报文形状与 `kbs_protocol` 的 RCAR 定义一致。
- 请求最终失败：ASR 返回 `ttrpc request error after reconnect` + HTTP 500；CDH 日志
  `GetTokenFailed("Attestation Agent token provider error: ... AA-KBC get token failed")`。
  完整 RCAR 需要**真 KBS 验明 + 真证据**，mock 不做验明、测试 VM 无 TEE，因此拿不到 token——
  **这正符合本节「只验证请求/响应形状，不做真证明」的定位**；真机 + 真 Trustee 才拿得到 token（见步骤 8）。

**说明（两个必踩的坑）**
- **启动顺序要反过来：AA → CDH**。`cc_kbc` 模式下 CDH 初始化 KBS 客户端时要连 AA 的 ttrpc socket 建 token provider；沿用步骤 5 的 CDH → AA，CDH 会直接启动失败：
  `init Hub failed: kbs client creation failed: ... AATokenProvider("ttrpc connect failed ... Connection refused (os error 111)")`。
  `offline_fs_kbc` 模式无此要求（原顺序可用）。
- **ASR 无需重启**：ASR 只是 REST 网关，KBC 指向由 CDH/AA 侧的环境变量决定。

---

<a id="step8"></a>
## 步骤 8：从测试 VM 迁移到真海光 CSV（复用本 runbook）

本 runbook 的每一步在真海光 CSV 服务器上**同样适用**——只是把少数几处「桩 / 离线」替换成「真 TEE / 真 Trustee」。下表给出逐步映射：**「不变」= 原样照搬；「改」= 只换那一项**。

| 步骤 | 测试 VM（本文现状） | 真海光 CSV 服务器 | 改动 |
|---|---|---|---|
| 0 系统/初始化 | Ubuntu x86_64 + `bash scripts/setup-server.sh` | 完全相同（同 OS、同脚本） | 不变 |
| 0.2 代码上服务器 | `git bundle`（因未推） | 联网后直接 `git clone` fork 即可 | 可选 |
| 1 切分支 | `2026-10-21-dev` | 同分支（或合入后的发布分支） | 不变 |
| 2 构建 | `cargo build` / `make build TEE_PLATFORM=all LIBC=gnu` | `make build TEE_PLATFORM=csv LIBC=musl`（静态、编入 csv-attester） | 改：attester + LIBC |
| 3 资源文件 | 本地 `dev-resources.json`（base64 明文） | 由**真 Trustee/KBS** 下发，不再手搓 JSON | 改：来源 |
| 4 KBC 参数 | `AA_KBC_PARAMS=offline_fs_kbc::null` | `AA_KBC_PARAMS=cc_kbc::https://<真KBS>`（或 `offline_fs_kbc::<kbs_uri>`） | 改：KBC 指向 |
| 5 启动 | 同组件、同 socket/端口、同顺序 | 完全相同（CDH/AA/ASR 架构不变，仅 attester 行为不同） | 不变 |
| 6.1–6.2 取资源 | 经 offline_fs_kbc 取回 | 经真 KBS 取回（接口/URI 不变） | 改：后端 |
| 6.3 sealed secret | 本地公钥文件验签（`SIGNING_CREDENTIALS_PATH/<kid>`） | 公钥**由机密 VM 启动时预置**；`kid` 可改为 **KBS URI** 由 Trustee 托管（跨仓 `kbs-types` 对齐） | 改：密钥预置 |
| 6.4 evidence | 桩数据/明确错误（无硬件） | **真 CSV 证据**：AA 走 `csv` attester 读 `/dev/csv-guest` 出度量，经 RCAR 挑战-应答由 Trustee 验明 | 改：证据链路 |
| 7 mock KBS | 本地 mock 验证 HTTP 形状 | 不需要（直接用真 KBS） | 跳过 |

**真机专属前提（测试 VM 没有）**
1. 海光 CSV 硬件（机密 VM，内核带 `csv-guest` 驱动，`/dev/csv-guest` 可读）。
2. 真 **Trustee / KBS** 部署并提供 `https://<kbs>` 端点（RCAR/Passport 验明）。
3. **kata-runtime** 接入（vsock + gRPC，非 HTTP），把 guest 内 AA/CDH 与宿主 Trustee 打通。
4. CSV attester 与 Trustee verifier 的协议字段对齐（跨仓 `kbs-types`），属 D2 收尾的协调项。

**迁移检查表（到真机时逐项核对）**

完整真机部署步骤（系统准备、构建口径、KBC 指向、密钥预置、证据链路、kata 接入、逐条验证）见 **`custom-真机CSV部署.md`**。其中与本 runbook 的差异已在上表逐条列出；复用到真机的部分即步骤 0–7 的全部逻辑。

> 说明：本 runbook 在你腾讯云普通 VM 上得到的**所有产出（编译出的二进制、`offline_fs_kbc` 配置、sealed secret 信封格式与验签逻辑、ASR/CDH/AA 启动方式）都直接复用到真机**；真机只是把 `attester=csv`、KBC 指向真 KBS、密钥预置方式、证据链路这几处替换掉，无需重写流程。

---

<a id="appendixa"></a>
## 附录 A：offline_fs_kbc 资源文件格式速查

- 默认读取文件：`/etc/aa-offline_fs_kbc-keys.json`、`/etc/aa-offline_fs_kbc-resources.json`（`offline_fs.rs:19-20`）。
- 额外文件：`OFFLINE_FS_KBC_EXTRA_FILE_PATH`（`:24`，`,` 分隔多个）。
- JSON 结构：`{ "resource_path": "base64(value)" }`，解析见 `:71-87`。
- 资源寻址：URI `kbs:///<resource_path>`（如 `kbs:///default/key/1`）→ 查表取 base64 解码后的值。

---

<a id="appendixb"></a>
## 附录 B：最小 mock KBS（Python，**步骤 7 实测在用**，可直接复制为 `~/mock-kbs.py`）

> 说明：早先版本这里给的是 Rust 示意代码，并写了 `cargo run --bin mock-kbs`——**仓库里并不存在该 bin**。
> 下面这份 Python 桩已在 2 服务器上实测跑通步骤 7：全量记录请求到 `~/mock-kbs.log`，并按 RCAR 协议形状应答
> `/kbs/v0/auth`（Challenge）→ `/kbs/v0/attest`（token）→ `/kbs/v0/resource/<path>`（Response）。
>
> 落盘为 `~/mock-kbs.py` 后，若登录用户名**不是** `ubuntu`，把脚本第 4 行 `LOG = "/home/ubuntu/mock-kbs.log"` 改成你的家目录（如 `/root/mock-kbs.log`），否则会报路径不存在。

```python
#!/usr/bin/env python3
import json, datetime, base64
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = "/home/ubuntu/mock-kbs.log"

def b64url(s):
    if isinstance(s, str):
        s = s.encode()
    return base64.urlsafe_b64encode(s).decode().rstrip("=")

FAKE_JWT = (b64url(json.dumps({"alg": "ES256", "typ": "JWT"})) + "."
            + b64url(json.dumps({"iss": "mock-kbs", "exp": 9999999999})) + "."
            + b64url("mock-signature"))

class Handler(BaseHTTPRequestHandler):
    def _log(self, body=b""):
        with open(LOG, "a") as f:
            f.write("%s %s %s\n" % (datetime.datetime.now().isoformat(), self.command, self.path))
            hdrs = {k: v for k, v in self.headers.items()
                    if k.lower() in ("content-type", "authorization", "accept", "content-length")}
            f.write("  headers: %s\n" % json.dumps(hdrs))
            if body:
                f.write("  body: %s\n" % body.decode("utf-8", "replace"))

    def _send(self, obj, code=200):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n) if n else b""
        self._log(body)
        if self.path.endswith("/auth"):
            self._send({"nonce": b64url("mock-nonce"), "extra_params": {"algorithm": "sha256"}})
        elif self.path.endswith("/attest"):
            self._send({"token": FAKE_JWT})
        else:
            self._send({"code": 404, "message": "mock: unknown POST path"}, 404)

    def do_GET(self):
        self._log()
        if "/resource/" in self.path:
            self._send({"code": 200,
                        "message": "mock resource (real KBS returns encrypted payload)",
                        "data": b64url("mock-resource-plaintext")})
        else:
            self._send({"code": 404, "message": "mock: unknown GET path"}, 404)

    def log_message(self, *args):
        pass

if __name__ == "__main__":
    open(LOG, "w").close()
    print("mock KBS listening on 127.0.0.1:8080, log: %s" % LOG, flush=True)
    HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
```

<a id="appendixc"></a>
## 附录 C：接口请求/返回参数速查

### C.1 ASR REST 接口（监听 `127.0.0.1:8006`，仅 loopback，外部访问 403）

| 接口 | 方法 | 请求参数 | 成功返回 | 错误 |
|---|---|---|---|---|
| `/info` | GET | 无 | 200 JSON `{version, tee, feature, additional_tees}` | 403 非 loopback |
| `/cdh/resource/{repository}/{type}/{tag}` | GET | 路径参数 3 段（拼成 `kbs:///<repository>/<type>/<tag>`） | 200 `application/octet-stream` 明文 | 403 / 404 / 405 / 500（`ttrpc request error`） |
| `/aa/evidence` | GET | `runtime_data`（必填）；`encoding`（可选，传 `base64` 表示已 base64 编码） | 200 JSON `{report_data, svn}` | 400 `BAD REQUEST` |
| `/aa/token` | GET | `token_type`（`kbs` / `coco_as`） | 200 JSON `{token, tee_keypair}`（真 KBS/真 TEE） | 400 `Unsupported token type` |
| `/aa/additional-evidence` | GET | `runtime_data`；`encoding` | 200 JSON | 400 |

启动参数：`api-server-rest --features all`（`all` 是**二进制 CLI 参数**，不是 cargo 特性）。

### C.2 ttrpc-cdh-tool（直连 CDH socket）

| 参数 | 必填 | 说明 |
|---|---|---|
| `get-resource --resource-uri <URI>` | 是 | 取资源；URI 形如 `kbs:///default/key/1` |
| `--socket <path>` | 否 | 默认 `unix:///run/confidential-containers/cdh.sock` |
| 返回 | — | base64 串（明文经 base64） |

### C.3 `secret` CLI 子命令

| 子命令 | 关键参数 | 产物 |
|---|---|---|
| `keygen` | `--kid`、`--output-dir` | `<kid>-private.json` / `<kid>-public.json` |
| `seal … vault` | `--signing-kid`、`--signing-jwk-path`、`--resource-uri`、`--provider` | `sealed.` 前缀 base64 JWS（stdout 首行为 Warning） |
| `seal … envelope` | `--key-id`、`--file-path` + `ali`/`aws` | 信封密文 |
| `unseal` | `--file-path`；`--aa-kbc-params`（kbs）/ `--key-path`（aliyun/aws） | `<file-path>.unsealed` |

### C.4 关键环境变量

| 变量 | 作用 | 测试 VM | 真机 |
|---|---|---|---|
| `AA_KBC_PARAMS` | 选 KBC 与远端 URI（`KBC名::KBS_URI`） | `offline_fs_kbc::null` | `cc_kbc::https://<kbs>` |
| `OFFLINE_FS_KBC_EXTRA_FILE_PATH` | offline_fs_kbc 额外资源文件（`,` 分隔可多个） | `/tmp/dev-resources.json` | 一般不用 |
| `RUSTUP_DIST_SERVER` / `RUSTUP_UPDATE_ROOT` | rustup 工具链镜像（国内必配） | 腾讯云镜像 | 同 |

---

<a id="refs"></a>
## 参考文件

- `Makefile`（TEE_PLATFORM→ATTESTER 映射 `:18-37`，`csv→csv-attester` 已完成；产物名 `:52-60`）
- `attestation-agent/attestation-agent/Cargo.toml`（bin 名 `ttrpc-aa`/`grpc-aa` `:9-19`；csv-attester 特性 `:105`）
- `attestation-agent/attestation-agent/src/config/aa_kbc_params.rs`（AA_KBC_PARAMS 解析 `:23`/`:63`）
- `confidential-data-hub/kms/src/plugins/kbs/offline_fs.rs`（offline_fs_kbc 资源文件 `:19-24`/`:71-87`）
- `image-rs/src/resource/kbs/ttrpc.rs`（cdh.sock 约定 `:16`）
- `image-rs/scripts/install_offline_fs_kbc_files.sh`（生成/安装 resources JSON）
- `confidential-data-hub/hub/src/bin/secret_cli.rs`（sealed secret 样例；**二进制名是 `secret`**）
- `confidential-data-hub/hub/src/secret/mod.rs`（SIGNING_CREDENTIALS_PATH `:29`、`sealed.` 前缀解析 `:77`）
- 本 runbook 的实测执行记录（2026-10-22，腾讯云 2 服务器，含国内镜像适配、问题与解法）：`custom-D2连调执行记录.md`
- 仓库已翻译文档：`confidential-data-hub/custom-README.md`、`attestation-agent/docs/custom-IMPLEMENTATION.md`
