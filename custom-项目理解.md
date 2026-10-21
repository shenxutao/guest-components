# 项目理解（guest-components）

> 本文是个人 fork 仓库 `guest-components` 的中文理解笔记，非官方文档。
> 配套官方材料见 `custom-README.md`、`custom-AGENTS.md`、`custom-个人开发指南.md`。

## 一、这个项目是什么

`guest-components` 是 [Confidential Containers（机密容器）](https://github.com/confidential-containers) 项目的一部分，用 **Rust** 编写，为运行在 **机密虚拟机 / TEE（可信执行环境）** 里的 Guest 提供两类核心能力：

1. **远程证明（Remote Attestation）**：让 Guest 能向外部（验证方 / 依赖方）证明“我确实跑在真实的、未被篡改的可信硬件上”。
2. **密钥与机密获取（Secret Retrieval）**：在证明通过后，安全地从外部拉取解密密钥、密钥资源、密封数据等机密，交给机密工作负载使用。

它通常被上游消费方 **kata-containers** 或 **cloud-api-adaptor** 编排：先起证明代理（AA），再起数据中枢（CDH），最后起 REST 网关（ASR），再配合 `image-rs` 完成加密镜像的拉取与解密。

一句话定位：**它是机密工作负载的“信任根 + 密钥闸门”，属于可信计算基（TCB），代码质量要求高、攻击面要尽可能小。**

## 二、仓库性质（个人 fork 的约定）

这是 `confidential-containers/guest-components` 的**个人 fork**：

- `origin` = `https://github.com/shenxutao/guest-components.git`（可写，个人维护）
- `upstream` = 官方仓库（**只读，绝不 push**）
- 当前开发分支：`2026-10-21-dev`，已解除对 upstream 的跟踪，防止误推官方
- 个人主责（见 `custom-个人开发指南.md`）：
  - `attestation-agent`：重点是**海光 CSV attester**（M1 证据采集端）
  - `confidential-data-hub`：重点是 **sealed secret（密封卷）** 机制
- `kbs-types` 是跨项目共享类型，属于外部依赖，“只改不建”，改字段须与上游 D4 协调

## 三、组件架构

| 组件 | 路径 | 职责 |
|---|---|---|
| **Attestation Agent (AA)** | `attestation-agent/attestation-agent` | 各 TEE 平台生成证明证据 / 令牌 |
| **Confidential Data Hub (CDH)** | `confidential-data-hub/hub` | 密钥、密封数据、KMS、镜像资源的中心代理 |
| **image-rs** | `image-rs` | OCI 镜像拉取、解密、签名验证 |
| **ocicrypt-rs** | `ocicrypt-rs` | OCI 镜像加解密库（被 image-rs 依赖） |
| **api-server-rest (ASR)** | `api-server-rest` | REST 网关，经 ttrpc 转发给 AA + CDH |
| **protos** | `protos` | ttrpc / gRPC 共享 protobuf 定义 |

这些组件加起来叫 “guest-components”。消费方负责按正确顺序编排它们（AA 先、CDH 次、ASR 后）并提供配置。

### 证明器（attester）一览

证明器实现位于 `attestation-agent/attester/src/`：

- `csv/`：海光 **CSV**（China Secure Virtualization）——本次个人开发重点（M1）
- `tdx/`：Intel TDX
- `snp/`：AMD SEV-SNP
- `se/`：Intel SGX（legacy）
- `cca/`：Arm CCA
- `az_snp_vtpm/`、`az_tdx_vtpm/`：Azure vTPM 变体
- `sgx_dcap/`、`hygon_dcu/`、`tpm/` 等
- 还有 `sample` / `sample-device` 这类**占位 / 桩实现**，用于本地无真实 TEE 时跑端到端流程

⚠️ **重要安全约束**：真实 TEE 存在时，绝不能默认或回退到 sample 证据，否则会把假证据误用进生产。

## 四、通信与数据流

- 组件间通过 **ttrpc**（默认，protobuf over Unix socket）或 **gRPC**（protobuf over HTTP/2）通信。
- 每个服务（AA、CDH）编译时可选 `ttrpc-aa`/`grpc-aa` 或 `ttrpc-cdh`/`grpc-cdh`。
- `api-server-rest` 暴露 REST API，再经 ttrpc 转给 AA + CDH。

典型数据流：

```
REST API → ttrpc → AA（做证明）+ CDH（取密钥/资源）→ image-rs（用 CDH 给的密钥解密镜像层）
```

## 五、构建 / 测试 / Lint

工具链锁定 **1.90.0**（见 `rust-toolchain.toml`），Rust workspace（resolver v2）。

```bash
# 全量构建（默认特性）
cargo build

# 按 TEE 平台交叉编译（Makefile 默认编成 musl）
make build TEE_PLATFORM=none          # 非机密
make build TEE_PLATFORM=tdx           # Intel TDX
make build TEE_PLATFORM=snp           # AMD SEV-SNP
make build TEE_PLATFORM=az-cvm-vtpm   # Azure vTPM
make build TEE_PLATFORM=all           # 全部平台

# 重新生成 ttrpc/gRPC protobuf 代码（需要 protoc）
make build-protos
```

测试：

```bash
make test
sudo -E PATH=$PATH make test          # CDH / image-rs 的集成测试需要 root

make -C attestation-agent ATTESTER=all-attesters test
make -C image-rs test
cargo test -p image-rs --test signature_verification -- --test-threads=1   # 集成测试常需串行
```

Lint（CI 与本地都用）：

```bash
make fmt
make lint          # 实际跑 clippy -D warnings，覆盖多组特性矩阵
```

提交前钩子会跑 gitleaks、shellcheck、trailing-whitespace、end-of-file-fixer。

注意：本机 shell 里 `cargo`/`rustc` 可能不在 PATH，需要先 `source ~/.cargo/env` 或用绝对路径；且 Bash 沙箱代理可能挡 GitHub。

## 六、特性开关（feature flags）是核心机制

这个项目重度依赖 Cargo feature 来控制平台支持与协议选择，主要几类：

- **TEE attester**：`tdx-attester` / `snp-attester` / `sgx-attester` / `se-attester` / `cca-attester` / `az-snp-vtpm-attester` / `az-tdx-vtpm-attester` / `all-attesters`
- **密钥封装（keywrap）**：`keywrap-ttrpc` / `keywrap-grpc` / `keywrap-jwe` / `keywrap-keyprovider-cmd`
- **KMS provider（CDH）**：`kbs` / `aliyun` / `aws`
- **RPC 协议**：`ttrpc`（默认）/ `grpc`

CI 会校验大量特性组合。改动条件编译时，一定要用多组 feature 测试。

加密后端固定为 **OpenSSL**（HTTP 用 vendored native-tls，ocicrypt-rs 用 OpenSSL 做随机数与密码学运算），不再通过 feature 可选。

## 七、几个关键能力的理解

### 1. 远程证明（AA）
AA 负责调用对应 TEE 平台的 attester，采集硬件证据（evidence），必要时通过 `kbs_protocol` 把证据发给 KBS / Trustee，换回证明令牌（attestation token）。除了真实 attester，还有 sample 桩用于本地联调。

### 2. 密钥 / 资源获取（CDH）
CDH 是机密数据中枢，统一对外提供：
- 镜像解密密钥（LEK/KEK 体系，配合 ocicrypt）
- 密钥资源（KBS resource，按 `ResourceDescription` 寻址）
- KMS 接入（阿里云 / AWS 等）
- **sealed secret（密封卷）**：把机密“密封”到某个 TEE 实例，只有相同 TEE 才能解封——这是个人开发的重点之一

### 3. 镜像解密与签名（image-rs）
`image-rs` 拉取 OCI 镜像时：
- 通过 `ocicrypt-rs` 解密镜像层（密钥来自 CDH / KBS）
- 支持多种签名方案验证：`Simple Signing`（`src/signature/policy/simple`）与 `Cosign`（`src/signature/policy/cosign`）
- 支持 credential 获取（`src/auth`）

## 八、与 Trustee 的关系

`confidential-containers/trustee` 是 guest-components 的“外部 counterpart”：它作为 RATS 模型里的**依赖方 / 验证方**跑在 TEE 之外，消费硬件证据、给机密 Guest 发放证明令牌和机密。

- 两个仓库**配套开发、配套发布**，但**解耦、可独立使用**。
- guest-components 的 `kbs-protocol` crate 被 Trustee 的 `kbs-client` 子项目消费。

## 九、安全与代码风格约定（速记）

- 属于 TCB，**尽量缩小攻击面**，新代码要有验证安全属性的测试。
- 错误处理：`thiserror` 定义公共 API 的域错误枚举；内部传播用 `anyhow::Result`。
- 异步：Tokio + `#[tokio::main]`，异步 trait 用 `async-trait`。
- 日志：`tracing`（`info!`/`debug!`/`warn!`/`error!`），不用 `#[instrument]`。
- 序列化：JSON（配置/API）、TOML（配置文件）、protobuf（RPC）。
- 测试属性：`#[tokio::test]`、`#[serial_test::serial]`、`rstest`；很多测试用 `#[cfg(feature = "...")]` 门控。
- 依赖版本集中在根 `Cargo.toml` 的 `[workspace.dependencies]`，各 crate 用 `dep.workspace = true` 引用。

## 十、提交 / PR 约定

- commit 标题要带子系统前缀，如 `attester:`、`cdh:`、`asr:`、`ci:`（不强求严格一致，但要指出改动的代码领域）。
- 每个 commit 应能独立编译，改动原子化。
- PR 标题同样带前缀；描述讲清 **为什么改、怎么改**，必要时说明负面影响与替代方案；避免堆砌 buzzword 和 emoji。

## 十一、个人开发切入点（D2）

1. **海光 CSV attester（M1）**：在 `attestation-agent/attester/src/csv/` 完善证据采集，参考其它 attester（tdx/snp）的接口与 trait 实现风格；注意真实 TEE 与 sample 桩的边界。
2. **CDH sealed secret（密封卷）**：围绕 `confidential-data-hub/docs/SEALED_SECRET.md` 描述的机制扩展，依赖 S3 等；改动要兼顾密钥安全与生命周期。

> 涉及 `kbs-types` 字段变更时，务必先与上游 D4 协调，避免协议漂移。
