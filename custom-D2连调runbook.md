# D2 腾讯云 Ubuntu 连调 Runbook（详细版）

> **目标**：在 Linux x86_64（Ubuntu）上把 D2 涉及的 guest 组件跑起来，完成「自己的服务部署 + 依赖桩」的连调，验证集成管道。**本 runbook 双用途**：① 腾讯云普通 VM（开发/测试，无 TEE）② 真海光 CSV 机密服务器（生产/验明）；两者复用同一套步骤，差异只在少数几处（见步骤 8 迁移映射）。
> **能力边界（测试 VM）**：无 TEE → 无真硬件证据；用 `all`/`none` attester 桩；用 `offline_fs_kbc` 替代外部 KBS（**无需 Beeceptor**）。真 CSV 证明在真机环境用 `csv` attester + 真 Trustee/KBS 达成（见步骤 8）。
> **约定**：命令在 Ubuntu x86_64 上执行；`$` 后为一行命令；凡标注「（确认）」处，以你机器上 `cargo build` 实际产物为准。

## 目录

- [步骤 0：准备 Ubuntu 环境（系统选型 + 服务器初始化 + 代码上服务器）](#step0)
- [步骤 1：进入仓库并切到开发分支](#step1)
- [步骤 2：构建三个组件（开发用原生 glibc，免 musl 交叉）](#step2)
- [步骤 3：准备 offline_fs_kbc 资源文件（替代外部 KBS）](#step3)
- [步骤 4：配置 KBC 参数（让 AA/CDH 走 offline_fs_kbc）](#step4)
- [步骤 5：创建运行时目录并启动三个守护进程](#step5)
- [步骤 6：验证（连调检查表）](#step6)
  - [6.1 ASR REST 探活 + 取资源](#step61)
  - [6.2 image-rs 直连 CDH（验证 kbs:// → offline_fs_kbc 通路）](#step62)
  - [6.3 sealed secret（D2 重点）](#step63)
  - [6.4 AA evidence / token（桩）](#step64)
- [步骤 7（可选）：用 mock KBS 测 cc_kbc 真 HTTP 路径](#step7)
- [步骤 8：从测试 VM 迁移到真海光 CSV（复用本 runbook）](#step8)
- [附录 A：offline_fs_kbc 资源文件格式速查](#appendixa)
- [附录 B：最小 mock KBS（Rust，hyper，仅示意）](#appendixb)
- [参考文件](#refs)

---

## 速查（TL;DR）

最小可跑通路径（测试 VM；命令在 Ubuntu x86_64 上执行）：

```bash
# 1) 装环境（一次）
bash scripts/setup-server.sh

# 2) 取代码（Mac 上打包，服务器上还原）
git bundle create /tmp/gc-dev.bundle 2026-10-21-dev && scp /tmp/gc-dev.bundle ubuntu@<IP>:~/
#   服务器上：git clone ~/gc-dev.bundle guest-components && cd guest-components && git checkout 2026-10-21-dev

# 3) 构建
cargo build -p confidential-data-hub -p attestation-agent -p api-server-rest

# 4) 准备 KBC 资源并启动（生成 dev-resources.json 见步骤 3；起服务见步骤 5）
export AA_KBC_PARAMS="offline_fs_kbc::null"
export OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json"

# 5) 验证
curl -s http://127.0.0.1:8006/info | head
```

> 真海光 CSV 部署：把上表的 attester 换成 `csv`、KBC 指向真 KBS 即可。完整真机步骤见 `custom-真机CSV部署.md` 与下方步骤 8 迁移映射。

## 图例与约定

- 命令默认在 **Ubuntu x86_64** 上执行；行首 `$` 表示一条命令（实际粘贴时去掉 `$`）。
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

**0.0 系统选型（重装系统时）**
- 发行版：Ubuntu LTS（**24.04 首选**；26.04 LTS 也可用但较新、生产验证少）；**不要选 CentOS / Rocky**（Makefile 的 `DebianOS` 检测不触发，依赖要手搓）
- 架构：**x86_64**（项目 TEE attester 均为 x86 平台，CSV 是海光 x86）；**避开 ARM / 鲲鹏**
- 镜像类型：基于操作系统镜像（干净系统）

**0.1 服务器初始化（一键脚本）**
```bash
# 在腾讯云 Ubuntu x86_64 上执行（装 rustup 1.95.0 + 编译依赖 + musl 目标）
bash scripts/setup-server.sh
```
脚本见 `scripts/setup-server.sh`：装 `build-essential`/`pkg-config`/`libssl-dev`/`protobuf-compiler`/`clang`/`libclang-dev`/`cmake`/`musl-tools`，装 rustup 并加 `x86_64-unknown-linux-musl` 目标。
> 轻量服务器内存小（常见 2G）时建议加 2G swap 防编译 OOM：`sudo fallocate -l 2G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`

**0.2 把「当前分支」代码带到服务器（本地 Mac 执行）**
当前分支 `2026-10-21-dev` 有未推提交，不能用远端 clone；用 `git bundle`：
```bash
# Mac 上：打包分支（含全部本地提交）
cd "/Users/shenxutao/MyWorkspace/Docs/机密计算/开发/guest-components"
git bundle create /tmp/gc-dev.bundle 2026-10-21-dev
scp /tmp/gc-dev.bundle ubuntu@<服务器IP>:~/
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

```bash
cd guest-components                         # 进入你 clone 的仓库根
git checkout 2026-10-21-dev                # 你的个人 dev 分支
git status -sb                              # 确认领先/落后状态
```

**说明**：所有改动在个人 fork 的 `2026-10-21-dev` 分支进行（与远端 `origin` 同步策略见 `custom-项目理解.md`）。

<a id="step2"></a>
## 步骤 2：构建三个组件（开发用原生 glibc，免 musl 交叉）

```bash
# 方式 A（推荐，迭代快）：直接用 cargo 编 D2 相关包，原生目标无需 musl
cargo build -p confidential-data-hub -p attestation-agent -p api-server-rest
# 产物在 target/debug/ 下
```

**说明**
- `cargo build` 默认用本机原生目标（x86_64-unknown-linux-gnu），**不需要 musl 交叉工具链**。musl 静态链接仅用于最终打包进 guest 镜像，开发期可跳过。
- 二进制命名有两条口径，二选一即可：
  - **cargo 口径**：AA 的 bin 名是 `ttrpc-aa` / `grpc-aa`（见 `attestation-agent/attestation-agent/Cargo.toml:9-19`）；CDH、ASR 的包名即 bin 名（`confidential-data-hub`、`api-server-rest`）。
  - **Makefile 口径**：顶层 `Makefile:53-55` 规定产物名就是 `confidential-data-hub` / `attestation-agent` / `api-server-rest`（见步骤 5 用 `make build` 时）。
- 若想贴近 CI / 产出与最终镜像一致的静态二进制：
  ```bash
  # 方式 B：TEE_PLATFORM=all 编入全部 attester（含 csv-attester，Cargo.toml:79），
  #         避免 none 特性歧义；开发期用 LIBC=gnu 免去 musl 工具链
  make build TEE_PLATFORM=all LIBC=gnu
  ```
  > 注意：`Makefile` 已补 `csv → csv-attester` 映射（D2-M1 已完成，见 `Makefile:36-37`），现在可直接 `TEE_PLATFORM=csv` 构建 CSV attester。

<a id="step3"></a>
## 步骤 3：准备 offline_fs_kbc 资源文件（替代外部 KBS）

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

**背景**
- CDH 监听 Unix socket `unix:///run/confidential-containers/cdh.sock`（image-rs 客户端约定，见 `image-rs/src/resource/kbs/ttrpc.rs:16`）。
- ASR 监听 `127.0.0.1:8006`（loopback，非 loopback 访问返回 403）。
- 启动顺序建议：**CDH → AA → ASR**（ASR 是 REST 网关，依赖后两者）。

```bash
# 5.0 创建运行时目录（socket / 凭据路径）
sudo mkdir -p /run/confidential-containers

# 5.1 启动 CDH（机密数据中枢）
AA_KBC_PARAMS="offline_fs_kbc::null" \
OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json" \
cargo run -p confidential-data-hub --bin confidential-data-hub
# 说明：bin 名 confidential-data-hub（Makefile:52）；启动后应监听 cdh.sock
#      若端口/socket 冲突，先 sudo rm -f /run/confidential-containers/cdh.sock

# 5.2 启动 AA（证明代理，ttrpc 服务）
AA_KBC_PARAMS="offline_fs_kbc::null" \
cargo run -p attestation-agent --bin ttrpc-aa
# 说明：AA 的 cargo bin 是 ttrpc-aa / grpc-aa（Cargo.toml:9-19）；若用 make build 则产物名 attestation-agent
#      非 TEE 机器调用 evidence 接口会返回桩数据或明确错误，属预期（无硬件证据）

# 5.3 启动 ASR（REST 网关）
cargo run -p api-server-rest --bin api-server-rest
# 说明：监听 127.0.0.1:8006；仅 loopback，外部访问 403
```

**说明**
- 建议三个组件各开一个终端（或 `nohup ... &` / systemd unit 后台运行），便于看日志。
- 用 `make build` 产出的二进制时，把 `cargo run -p X --bin Y` 换成直接执行 `./target/x86_64-unknown-linux-gnu/release/<bin>` 并前置同样的环境变量。

---

<a id="step6"></a>
## 步骤 6：验证（连调检查表）

<a id="step61"></a>
### 6.1 ASR REST 探活 + 取资源
```bash
curl -s http://127.0.0.1:8006/info | head
# 期望：返回 VersionInfo（含 tee / version / feature 字段）

curl -s http://127.0.0.1:8006/cdh/resource/default/key/1
# 期望：返回你在 /tmp/dev-resources.json 里放的 default/key/1 资源
#       （请求经 ASR → CDH → offline_fs_kbc 取回）
```

<a id="step62"></a>
### 6.2 image-rs 直连 CDH（验证 kbs:// → offline_fs_kbc 通路）
```bash
cargo run -p confidential-data-hub --bin ttrpc-cdh-tool -- \
  --socket /run/confidential-containers/cdh.sock \
  GetResource --resource-uri "kbs:///default/key/1"
# 说明：ttrpc-cdh-tool 是仓库自带 ttrpc 客户端（confidential-data-hub/hub/src/bin/ttrpc-cdh-tool.rs）
#      若 CLI 参数不符，以该文件实际定义为准
```

<a id="step63"></a>
### 6.3 sealed secret（D2 重点）
**背景**：CDH 用「JWS(ES256) 签名 + 数字信封/Vault 引用」封装密钥（完整机制见 `custom-CDH-SealedSecret.md`）。**二进制名是 `secret`**（非 `secret_cli`），调用 `cargo run -p confidential-data-hub --bin secret -- <子命令>`。

**本地端到端（Vault + offline_fs_kbc，走真验签）**：
```bash
# 生成 P-256 签名密钥对
cargo run -p confidential-data-hub --bin secret -- keygen --kid my-key --output_dir /tmp/secrets

# 放验签公钥到 SIGNING_CREDENTIALS_PATH（需 root，因在 /run 下）
sudo mkdir -p /run/confidential-containers/cdh/sealed-secret
sudo cp /tmp/secrets/my-key-public.json /run/confidential-containers/cdh/sealed-secret/my-key

# 密封一个指向 KBS 资源的 Vault secret
cargo run -p confidential-data-hub --bin secret -- seal --type vault \
  --resource_uri "kbs:///default/key/1" --provider kbs \
  --signing_kid my-key --signing_jwk_path /tmp/secrets/my-key-private.json \
  | tee /tmp/sealed-secret.txt

# 解封（AA_KBC_PARAMS 让 kbs provider 走 offline_fs_kbc）
AA_KBC_PARAMS="offline_fs_kbc::null" \
OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json" \
cargo run -p confidential-data-hub --bin secret -- unseal \
  --file_path /tmp/sealed-secret.txt --aa_kbc_params "offline_fs_kbc::null"

cat /tmp/sealed-secret.txt.unsealed   # 应等于 my-dev-secret-key-001
```
**说明**：信封格式、Envelope/Vault 区别、`kid` 寻址、`SKIP_SEALED_SECRET_VERIFICATION` 等见 `custom-CDH-SealedSecret.md`；`/tmp/dev-resources.json` 来自步骤 3（含 `default/key/1`）。

<a id="step64"></a>
### 6.4 AA evidence / token（桩）
```bash
curl -s "http://127.0.0.1:8006/aa/evidence?runtime_data=test"
curl -s "http://127.0.0.1:8006/aa/token?token_type=default"
# 期望：none / all-attester 下返回桩数据或明确错误（非 TEE 无真证据，属预期）
```

<a id="step7"></a>
## 步骤 7（可选）：用 mock KBS 测 cc_kbc 真 HTTP 路径

**背景**：仅当你想验证 `cc_kbc::https://<mock>` 这条「AA → 真 KBS 形态」的客户端 HTTP 行为时才需要（替代 Beeceptor）。**只验证请求/响应形状，不做真证明**（无 RCAR challenge/response 握手）。

```bash
# 7.1 起一个最小 mock KBS（监听 :8080，见附录 B），对资源请求返回固定 base64 值
cargo run --bin mock-kbs

# 7.2 让 AA/CDH 走这个桩
export AA_KBC_PARAMS="cc_kbc::http://127.0.0.1:8080"
# 然后按步骤 5 重启 CDH / AA
```

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
## 附录 B：最小 mock KBS（Rust，hyper，仅示意）

```rust
use hyper::{Body, Request, Response, Server, service::{make_service_fn, service_fn}};

async fn handle(_req: Request<Body>) -> Result<Response<Body>, hyper::Error> {
    // 真实 KBS: GET /kbs/v0/resource/<path> 返回 base64 资源；此处返回固定桩
    Ok(Response::new(Body::from("base64-encoded-secret")))
}

#[tokio::main]
async fn main() {
    let addr = ([0, 0, 0, 0], 8080).into();
    Server::bind(&addr)
        .serve(make_service_fn(|_| async {
            Ok::<_, hyper::Error>(service_fn(handle))
        }))
        .await
        .unwrap();
}
```

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
- 仓库已翻译文档：`confidential-data-hub/custom-README.md`、`attestation-agent/docs/custom-IMPLEMENTATION.md`
