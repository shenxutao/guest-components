# 开发者指南（Agents Guide）— guest-components

本仓库是一个 Rust workspace，提供用于机密 guest TEE（可信执行环境，Trusted Execution Environments）的工具与组件。Guest Components 提供从 TEE 硬件生成证明证据（attestation evidence）以及初始化密钥获取流程（secret retrieval）的辅助能力，可供机密工作负载使用。它是 [Confidential Containers](https://github.com/confidential-containers) 项目的一部分，由 kata-containers 或 cloud-api-adaptor 消费。

## 构建

这是一个 Rust workspace（resolver v2），工具链固定为 **1.90.0**（见 `rust-toolchain.toml`）。

```bash
# 构建所有 workspace 成员（默认特性）
cargo build

# 通过 Makefile 针对特定 TEE 平台构建（默认交叉编译为 musl）
make build TEE_PLATFORM=none          # 非机密
make build TEE_PLATFORM=az-cvm-vtpm   # 基于 Azure vTPM 的证明（TDX 或 SEV-SNP）
make build TEE_PLATFORM=tdx           # Intel TDX
make build TEE_PLATFORM=snp           # AMD SEV-SNP
make build TEE_PLATFORM=all           # 所有平台

# 重新构建 ttrpc/gRPC 的 protobuf 代码（需要 protoc）
make build-protos
```

## 测试

workspace 根目录以及每个组件 crate 都提供了 `make test` 目标。本地检查优先使用这些目标——它们会跑与 `make lint` 以及组件构建相同的特性组合。

```bash
# 运行所有组件的测试（CDH 和 image-rs 需要 root 权限；见下方说明）
make test
sudo -E PATH=$PATH make test

# 运行单个组件的测试
make -C attestation-agent test
make -C confidential-data-hub test
make -C api-server-rest test
make -C image-rs test
make -C ocicrypt-rs test

# 证明代理：构建/lint/测试共用 ATTESTER 参数
make -C attestation-agent ATTESTER=all-attesters test
make -C attestation-agent ATTESTER=tdx-attester test
```

针对单个 crate 或单个测试的临时运行：

```bash
cargo test -p attestation-agent
cargo test -p confidential-data-hub
cargo test -p image-rs
cargo test -p ocicrypt-rs

# 按名称运行单个测试
cargo test -p image-rs -- test_name

# 许多测试需要特定特性才能编译
cargo test -p image-rs --no-default-features --features kata-cc,keywrap-jwe
cargo test -p confidential-data-hub --features kbs,aliyun,bin
cargo test -p attestation-agent --features all-attesters,kbs,coco_as

# 集成测试往往需要串行执行
cargo test --test signature_verification -- --test-threads=1
```

大多数集成测试需要 root 权限、需要运行 CDH/KBS 服务，以及预装的测试装置（fixtures，如 GPG 密钥、offline-fs-kbc 资源）。

## Lint

```bash
# 全 workspace 检查（推荐入口）
make fmt
make lint

# 按组件的 lint（与组件测试目标相同的特性矩阵）
make -C attestation-agent lint
make -C confidential-data-hub lint
make -C api-server-rest lint
make -C image-rs lint
make -C ocicrypt-rs lint
```

`attestation-agent`、`image-rs` 和 `ocicrypt-rs` 会 lint 多个特性组合（包括 `--no-default-features` 预设）。

针对一次性 cargo 运行：

```bash
cargo fmt --check
cargo clippy -- -D warnings
cargo clippy -p image-rs --all-targets --no-default-features \
    --features kata-cc,signature-simple-xrss -- -D warnings
```

Pre-commit 钩子会运行 gitleaks、shellcheck、trailing-whitespace 和 end-of-file-fixer。

## 架构

### 组件

| 组件 | Crate 路径 | 职责 |
|-----------|-----------|------|
| **证明代理（AA）** | `attestation-agent/attestation-agent` | 为 TEE 平台生成证明证据与 token |
| **机密数据中枢（CDH）** | `confidential-data-hub/hub` | 密钥、密封数据、KMS 与镜像资源的中心代理 |
| **image-rs** | `image-rs` | OCI 容器镜像的拉取、解密与签名验证 |
| **ocicrypt-rs** | `ocicrypt-rs` | OCI 镜像的加密/解密库 |
| **api-server-rest** | `api-server-rest` | 通过 ttrpc 转发给 AA 和 CDH 的 REST HTTP 网关 |
| **protos** | `protos` | ttrpc 和 gRPC 接口共享的 protobuf 定义 |

以上组件的集合被称为 "guest-components"，消费方负责以正确的顺序编排它们（先 AA，再 CDH，再 ASR），并提供必要的配置。

### 通信

组件间通过 **ttrpc**（基于 Unix 套接字的 protobuf，默认）或 **gRPC**（基于 HTTP/2 的 protobuf，备选）通信。每个服务（AA、CDH）会构建为 `ttrpc-aa`/`grpc-aa` 或 `ttrpc-cdh`/`grpc-cdh`。`api-server-rest` 暴露 REST API 并通过 ttrpc 转发给 AA+CDH。

数据流：`REST API → ttrpc → AA（证明）+ CDH（密钥/镜像）→ image-rs（用来自 CDH 的密钥进行解密）`

### 加密后端

OpenSSL 是项目选定的加密后端。HTTP 客户端使用 vendored 的 native-tls，ocicrypt-rs 使用 OpenSSL 获取密码学随机数。
这些后端不再可以通过 Cargo 特性进行选择。

### 特性开关（Feature flags）

特性开关被大量用于控制系统平台支持与协议选择。主要类别：

- **TEE attester**（AA）：`tdx-attester`、`snp-attester`、`sgx-attester`、`se-attester`、`cca-attester`、`az-snp-vtpm-attester`、`az-tdx-vtpm-attester`、`all-attesters`
- **Key wrapping**（image-rs/ocicrypt-rs）：`keywrap-ttrpc`、`keywrap-grpc`、`keywrap-jwe`、`keywrap-keyprovider-cmd`
- **KMS providers**（CDH）：`kbs`、`aliyun`、`aws`
- **RPC 协议**：`ttrpc`（默认）、`grpc`

CI 会验证大量特性组合——在新增特性或改动条件编译时，请用多个特性集进行测试。

## 安全考量

远程证明与密钥交付都是安全敏感的操作。对代码库的改动应当充分考虑安全影响，并且新代码应当被能够验证安全属性的全面测试所覆盖。我们鼓励用类型系统表达不变条件（invariant）的编码模式，例如使用类型状态模式（type state pattern）或 newtype 来防止 API 被误用。始终考虑新功能的攻击面并努力将其最小化。本代码库是机密工作负载可信计算基（TCB）的一部分，因此我们在代码质量与安全卫生上要格外谨慎和严谨。总的来说，我们希望避免在 TCB 中增加过多攻击面，并避免加入对核心用例并非严格必要的功能。

## API 稳定性

本项目被打包并分发到下游。Guest-Components 目前尚未对所有载荷与协议提供机器可强制执行的 schema，但我们努力在迭代时避免对消费者造成破坏。如果无法避免，我们会在提交信息中明确指出来，以便在发布说明中进行汇总和追踪。

## 与 Trustee 的关系

confidential-containers/trustee 是 guest-components 的对等服务端，在 TEE 之外、RATS 模型中作为依赖方（relying party）和验证方（verifier）运行。它消费硬件证据，并向机密 guest 提供证明 token 和密钥。这两个仓库同步开发与发布，但它们是解耦的，也可以独立使用。guest-components 的 kbs-protocol crate 被 Trustee 的 kbs-client 子项目所消费。

## 样例验证器（Sample Verifiers）

本地开发不太可能在能够产生真实证明证据的 TEE 中进行。因此提供了 “sample” 和 “sample-device” 这两组 attester/verifier 配对，可作为本地开发与测试端到端流程时的桩（dummy stubs）。我们应当意识到，这些虚拟实现及其证据存在被意外用于生产环境的风险。我们应当确保在存在真实 TEE 的情况下，不会默认或回退到 sample 证据。

## 规约（Conventions）

### 提交（Commits）

提交信息必须包含一个子系统（subsystem），由「前缀 + 冒号」标识，例如 "attester: fix hex encoding"。这不必严格匹配，但应当指出受影响的代码库大致区域，例如 "cdh:"、"asr:"、"ci:" 等。

提交应当各自可独立编译，并包含原子化的改动。

### PR

PR 名称必须包含一个子系统（由「前缀 + 冒号」标识），与提交信息类似。我们避免在 PR 描述中堆砌过多信息，尤其不鼓励滥用流行词和表情符号（emoji）。我们希望了解**为什么**要做这个改动、**如何**做的，以及（如适用）潜在的负面影响和曾经考虑过的备选方案。

### 杂项（Misc）

- **错误处理**：公开 API 使用基于 `thiserror` 的领域特定错误枚举；内部传播使用 `anyhow::Result`。两者在整个代码库中会同时使用。
- **异步运行时**：Tokio，配合 `#[tokio::main]`。异步 trait 方法使用 `async-trait` crate。
- **日志**：`tracing` crate（`info!`、`debug!`、`warn!`、`error!`）。不使用 `#[instrument]`。
- **序列化**：配置/API 用 JSON（`serde_json`），配置文件用 TOML，RPC 用 protobuf。
- **测试属性**：异步测试用 `#[tokio::test]`；使用 `#[serial_test::serial]` 防止并行测试相互干扰；参数化测试用 `rstest`。许多测试被 `#[cfg(feature = "...")]` 门控。
- **Workspace 依赖**：所有共享依赖版本都在根 `Cargo.toml` 的 `[workspace.dependencies]` 中声明。crate 级别的 `Cargo.toml` 通过 `dep.workspace = true` 引用它们。
