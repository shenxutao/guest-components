# 项目理解（guest-components · 详细版）

> 本文是个人 fork 仓库 `guest-components` 的中文理解笔记，**基于源码逐文件核实**，非官方文档。
> 配套官方材料见 `custom-README.md`、`custom-AGENTS.md`、`custom-个人开发指南.md`。
> 文中标注 `路径:行号` 便于回查源码；结论以源码为准，发现偏差以源码优先。

---

## 一、这个项目是什么

`guest-components` 是 [Confidential Containers（机密容器）](https://github.com/confidential-containers) 项目的一部分，用 **Rust** 编写，为运行在 **机密虚拟机 / TEE（可信执行环境）** 里的 Guest 提供两类核心能力：

1. **远程证明（Remote Attestation）**：让 Guest 向外部（验证方 / 依赖方）证明“我确实跑在真实的、未被篡改的可信硬件上”。
2. **密钥与机密获取（Secret Retrieval）**：在证明通过后，安全地从 KBS（Key Broker Service）/ Trustee 拉取解密密钥、密钥资源、密封数据等机密，交给机密工作负载使用。

它通常被上游消费方 **kata-containers** 或 **cloud-api-adaptor** 编排：先起证明代理（AA），再起数据中枢（CDH），最后起 REST 网关（ASR），再配合 `image-rs` 完成加密镜像的拉取与解密。

一句话定位：**它是机密工作负载的“信任根 + 密钥闸门”，属于可信计算基（TCB），代码质量要求高、攻击面要尽可能小。**

---

## 二、仓库性质（个人 fork 的约定）

这是 `confidential-containers/guest-components` 的**个人 fork**：

- `origin` = `https://github.com/shenxutao/guest-components.git`（可写，个人维护）
- `upstream` = 官方仓库（**只读，绝不 push**）
- 当前开发分支：`2026-10-21-dev`，已解除对 upstream 的跟踪，防止误推官方
- 个人主责（见 `custom-个人开发指南.md`）：
  - `attestation-agent`：重点是**海光 CSV attester**（M1 证据采集端）
  - `confidential-data-hub`：重点是 **sealed secret（密封卷）** 机制
- `kbs-types`（`kbs-types = "0.18.0"`）是跨项目共享类型，属于外部依赖，“只改不建”，改字段须与上游 D4 协调

---

## 三、Workspace 结构

### 3.1 成员与工具链

根 `Cargo.toml`（`/Users/.../Cargo.toml`）：

- `[workspace]`（`:1-16`）`members` 共 **12 个** member crate：
  - `api-server-rest`
  - `attestation-agent/attestation-agent`（AA 本体）
  - `attestation-agent/kbs_protocol`（KBS 客户端库）
  - `attestation-agent/attester`（各 TEE attester 实现库）
  - `attestation-agent/deps/resource_uri`（资源 URI 解析）
  - `attestation-agent/deps/crypto`（密码学辅助）
  - `attestation-agent/coco_keyprovider`（CoCo gRPC keyprovider）
  - `confidential-data-hub/hub`（CDH 本体）
  - `confidential-data-hub/kms`（KMS/Vault 插件库）
  - `image-rs`
  - `ocicrypt-rs`
  - `protos`（protoc 生成 ttrpc/gRPC 绑定）
  - 注意：`image-rs/libs/test-utils` **不是** workspace member，仅作 image-rs 的 dev 依赖（path dep）。
- `[workspace.dependencies]`（`:18-84`）关键共享依赖：`kbs-types = "0.18.0"`、`ttrpc = "0.9.0"`、`tonic = "0.14"`、`jwt-simple`（pure-rust）、`reqwest`（native-tls-vendored，固定 vendored native-tls）、`aws-sdk-kms`/`aws-sdk-secretsmanager`、`openssl`、`ring`、`rsa`、`sha2`、`zeroize`、`async-trait`、`serial_test`、`rstest`、`tracing` 系列等。
- **`rust-toolchain.toml`**：`channel = "1.95.0"`（注意：AGENTS.md 历史写 1.90.0 已过时，实际为 1.95.0）。部分 crate（attester/AA/kms）用 `edition = "2024"`，其余（CDH hub、ocicrypt-rs）用 `2021`。

### 3.2 组件包名与形态

| 包名 | 路径 | 类型 / 产物 |
|---|---|---|
| `attestation-agent` | `attestation-agent/attestation-agent` | lib + 3 个 bin（`ttrpc-aa`、`grpc-aa`、`ttrpc-aa-client`） |
| `attester` | `attestation-agent/attester` | lib + `evidence_getter` bin |
| `kbs_protocol` | `attestation-agent/kbs_protocol` | lib + `trustee-attester` bin |
| `coco_keyprovider` | `attestation-agent/coco_keyprovider` | bin（gRPC keyprovider） |
| `confidential-data-hub` | `confidential-data-hub/hub` | lib + 多 bin（`ttrpc-cdh`、`grpc-cdh`、`ttrpc-cdh-tool`、`cdh-oneshot`、`secret` CLI 等） |
| `kms` | `confidential-data-hub/kms` | lib（CDH 的 KMS/Vault 插件库） |
| `image-rs` | `image-rs` | lib |
| `ocicrypt-rs` | `ocicrypt-rs` | lib |
| `protos` | `protos` | lib（protoc 生成绑定） |
| `api-server-rest` | `api-server-rest` | bin（REST 网关） |

---

## 四、attestation-agent（证明代理）

### 4.1 crate 入口与模块树（`attestation-agent/attestation-agent/`）

- `Cargo.toml`：包名 `attestation-agent`；bin 为 `grpc-aa`（req `bin,grpc`）、`ttrpc-aa`（req `bin,ttrpc`）、`ttrpc-aa-client`（req `bin,ttrpc`）。默认 `default = ["ttrpc","grpc"]`。
- **lib 入口** `src/lib.rs`：
  - 核心结构 `struct AttestationAgent`（`:101`）
  - 核心 trait `trait AttestationAPIs`（`:71`）：`get_token` / `get_evidence` / `get_additional_evidence` / `extend_runtime_measurement` / `bind_init_data` / `get_tee_type` / `get_additional_tees`
  - 模块：`config`、`eventlog`、`initdata`、`token`
- 模块树：
  - `token/mod.rs`：`TokenType` 枚举 `{Kbs, CoCoAS}`；`token/kbs.rs`（`KbsTokenGetter`）；`token/coco_as.rs`（`CoCoASTokenGetter`）
  - `eventlog/mod.rs`（`EventLog`，WAL/AAEL 逻辑）、`eventlog/tcg2.rs`
  - `config/{mod.rs, aa_kbc_params.rs（AaKbcParams）, kbs.rs（KbsConfig）, coco_as.rs（CoCoASConfig）}`
  - `bin/ttrpc-aa.rs`、`bin/grpc-aa/{main.rs,server.rs}`、`bin/ttrpc-aa-client.rs`

### 4.2 Attester trait（统一证明接口）

- **定义位置**：`attestation-agent/attester/src/lib.rs:212-264`
- **方法签名**（async-trait）：
  - `async fn get_evidence(&self, report_data: Vec<u8>) -> Result<TeeEvidence>`（`:217`）——核心，采集证据
  - `fn supports_runtime_measurement(&self) -> bool`（`:220`，默认 `false`）
  - `async fn extend_runtime_measurement(&self, event_digest: Vec<u8>, register_index: u64) -> Result<()>`（`:228`）
  - `async fn bind_init_data(&self, init_data_digest: &[u8]) -> Result<InitDataResult>`（`:236`）
  - `async fn get_runtime_measurement(&self, pcr_index: u64) -> Result<Vec<u8>>`（`:243`）
  - `fn pcr_to_ccmr(&self, pcr_index: u64) -> u64`（`:252`，默认 `panic`）
  - `fn ccel_hash_algorithm(&self) -> HashAlgorithm`（`:261`，默认 `panic`）
- 关键别名：`TeeEvidence = serde_json::Value`（`:210`）、`BoxedAttester = Box<dyn Attester + Send + Sync>`（`:54`）
- `TryFrom<Tee> for BoxedAttester`（`:56-199`）：把 `kbs_types::Tee` 映射到具体 attester 实例
- 平台自检：`detect_tee_type()`（`:267`）、`detect_attestable_devices()`（`:334`）

### 4.3 kbs_protocol crate（与 KBS 通信）

- 包名 `kbs_protocol`（`attestation-agent/kbs_protocol/`），含 `build.rs`，bin `trustee-attester`。
- 模块（`src/lib.rs`）：`api`、`builder`、`client`、`error`、`evidence_provider`、`keypair`、`token_provider`，及实验性 `akp`（pqc）。
- **客户端结构**：`client/mod.rs` 的 `struct KbsClient<T>`（`:32`），泛型 `T` 是 evidence/token provider。
  - 常量：`KBS_PROTOCOL_VERSION = "0.4.0"`（`:58`）、`KBS_PREFIX = "kbs/v0"`（`:62`，注意不是 `kbs/v1`）、`KBS_GET_RESOURCE_MAX_ATTEMPT = 3`（`:60`）
- **两种 RATS 交互模型**：
  - **Background-Check（RCAR）**：`client/rcar_client.rs`，`impl KbsClient<Box<dyn EvidenceProvider>>`。`get_token()`（`:115`）执行 RCAR 握手（`rcar_handshake` `:231`）：POST `{prefix}/auth` 拿 `Challenge` → 算 composite evidence → POST `{prefix}/attest` 拿 JWT `token`。`get_resource()`（`:337`）GET `{host}/{prefix}/{plugin}/{path}`，对响应用 TEE key 解密（`tee_key.decrypt_response`）。用 `kbs_types::{Request, Challenge, Response, Attestation, CompositeEvidence, InitData, RuntimeData}`。
  - **Passport**：`client/token_client.rs`，`impl KbsClient<Box<dyn TokenProvider>>`，用 token 直接鉴权取资源。
- **provider**：
  - `evidence_provider/{native.rs, aa_ttrpc.rs, mock.rs}`：`NativeEvidenceProvider`（本进程直接调 attester）、`AATokenProvider`（经 ttrpc 连 AA 取 evidence/token）、`MockEvidenceProvider`
  - `token_provider/{mod.rs, aa/mod.rs, test.rs}`：`Token`、`AATokenProvider`
  - `builder.rs`：`KbsClientBuilder`；`keypair.rs`：`TeeKeyPair`/`TeeKeyAlgorithm`；`api.rs`：`KbsClientCapabilities` trait
- **关于“AttestationHub”**：仓库内检索 `AttestationHub` **0 命中**。KBS 客户端就是 `kbs_protocol::KbsClient`，没有叫 AttestationHub 的结构；真正的“服务端 / trustee 侧连接”由 `coco_keyprovider` 提供。

### 4.4 各平台 attester 实现（`attestation-agent/attester/src/`）

`lib.rs:15-52` 按 feature 声明模块：`az_snp_vtpm`、`az_tdx_vtpm`、`cca`、`tdx`、`sgx_dcap`、`snp`、`csv`、`hygon_dcu`、`se`、`tpm`、`nvidia`、`nvidia_dpu`；始终编译 `sample`、`sample_device`、`utils`，`tsm_report` 受 `tsm-report` feature。

| 模块 | 实现的方法（除基础 `get_evidence` 外） |
|---|---|
| `tdx/mod.rs:101` | `supports_runtime_measurement(true)`、`extend_runtime_measurement`、`bind_init_data`、`get_runtime_measurement`（子文件 `report.rs`、`rtmr.rs`） |
| `snp/mod.rs` | `detect_platform:19`，受 `tsm-report`/`sev` feature |
| `se/mod.rs` | 把 nonce 反序列化为 `SeAttestationRequest` 注入 `runtime_data_digest` |
| `az_snp_vtpm/mod.rs:121` | `supports_runtime_measurement`、`bind_init_data`、`extend_runtime_measurement`、`get_runtime_measurement` |
| `az_tdx_vtpm/mod.rs:74` | `bind_init_data`、`supports_runtime_measurement`、`extend_runtime_measurement` |
| `cca/mod.rs:30` | 仅 `get_evidence`（默认 `challenge` 入参） |
| `csv/mod.rs:95` | **见 §4.5（完整）** |
| `tpm/mod.rs:63` | `supports_runtime_measurement`、`extend_runtime_measurement`、`bind_init_data`、`get_runtime_measurement` |
| `sample/mod.rs:28`、`sample_device/mod.rs:29` | 仅 `get_evidence`（最小桩，fallback 用） |
| `nvidia/mod.rs`、`nvidia_dpu/mod.rs:149` | `get_evidence`（附加设备） |
| `hygon_dcu/mod.rs` | `get_evidence`（DCU 作为附加设备） |

⚠️ **安全约束**：真实 TEE 存在时，绝不能默认或回退到 `sample`/`sample_device` 这类桩证据，否则会把假证据误用进生产。

### 4.5 海光 CSV attester 现状（D2 重点）

- **文件**：`attestation-agent/attester/src/csv/mod.rs`（单文件，无子模块）。依赖 `csv-rs`、`codicon`、`hyper`+`hyper-tls`（`attester/Cargo.toml:41,42,43,106`）。
- **实现结构**：
  - `detect_platform()`（`:30`）：检测 `/dev/csv-guest` 是否存在
  - `CsvAttester`（`:64`，`#[derive(Default)]`）
  - 数据结构：`CsvEvidence` / `CertificateChain` / `HskCek`（`:34-62`）
  - `download_hskcek_from_kds()`（`:67`）：从 `https://cert.hygon.cn/hsk_cek?snumber=` 拉取 HSK/CEK 证书链（受 `CSV_INCLUDE_CERT_CHAIN_ENV` 环境变量控制是否包含证书链）
  - `impl Attester`（`:94-179`）：**实现了全部 6 个** trait 方法：`get_evidence`、`supports_runtime_measurement(true)`、`extend_runtime_measurement`（调 `csv_guest.req_rtmr_extend`）、`get_runtime_measurement`（`req_rtmr_read`）、`pcr_to_ccmr`（`:167` PCR→CCMR 映射）、`ccel_hash_algorithm → HashAlgorithm::Sm3`（`:177`）
- **结论**：CSV attester **功能完整**（含 RTMR 扩展、SM3 CCEL、证书链下载），通过 `csv-attester` feature 启用（`attester/Cargo.toml:106`、`AA/Cargo.toml:105`）。
- **已知缺口**：顶层 `Makefile:37` 明确注释 `# TODO: Add support for CSV`——即 `TEE_PLATFORM=csv` 不会自动把 `ATTESTER` 设为 `csv-attester`；只有 `make build TEE_PLATFORM=all` 或显式传 feature 才会编入。**这是 D2 需要补的构建入口**（在 Makefile 的 `TEE_PLATFORM` 映射里加 `csv → csv-attester`）。

### 4.6 AS（Attestation Service）与 token 获取

- AA 侧 `token/mod.rs` 的 `TokenType`：`Kbs`（feature `kbs`）与 `CoCoAS`（feature `coco_as`）（`token/mod.rs:21-29`）
  - `token/kbs.rs`：`KbsTokenGetter` 用 `kbs_protocol::KbsClientBuilder + NativeEvidenceProvider` 做 RCAR，从 KBS 拿 attestation token（`:19-67`）
  - `token/coco_as.rs`：`CoCoASTokenGetter` 直接 `POST {as_uri}/attestation`，body 为 `verification_requests[{tee, evidence}]`（`:19-58`）——对接 CoCo AS / trustee 风格 AS
- **trustee 侧 / keyprovider**：`attestation-agent/coco_keyprovider/`（bin crate）提供 `src/grpc/mod.rs` 的 `KeyProviderService`（`KeyProvider`），实现 `WrapKey`（生成 annotation 并把密钥注册到 KBS），`UnWrapKey` 目前 `unimplemented`（`:130-139`）；`src/main.rs` 监听 socket，可选 `--kbs`/`--auth-private-key` 自动注册密钥。proto 见 §八。

---

## 五、confidential-data-hub（机密数据中枢）

### 5.1 hub crate 入口与模块树（`confidential-data-hub/hub/`）

- `Cargo.toml`：包名 `confidential-data-hub`。bin：`ttrpc-cdh`、`grpc-cdh`、`ttrpc-cdh-tool`、`cdh-oneshot`、`secret`（CLI）等。
- `src/lib.rs` 模块：`error`、`api`、`hub`、`auth`、`config`、`image`、`secret`、`storage`。
- **关键 trait** `trait DataHub`（`api.rs:15`）：`unseal_secret`、`unwrap_key`、`get_resource`、`secure_mount`、`pull_image`。
- `hub.rs:27` 的 `struct Hub` 实现 `DataHub`：
  - `Hub::get_resource`（`:77`）走 `kms::new_getter("kbs", …)`
  - `Hub::pull_image`（`:98`）调用 image-rs 拉镜像，并**经 ttrpc 调 AA 的 `ExtendRuntimeMeasurement`** 记录 `PullImage` 的 AAEL 事件（`:117-173`）——证明与镜像拉取在此联动
- 其余模块：
  - `image/mod.rs`（`unwrap_key`）、`image/annotation_packet/{v1,v2}`
  - `storage/mod.rs`、`storage/drivers/{filesystem,luks2,zfs}`、`storage/volume_type/{mod,aliyun,blockdevice}`
  - `auth/{mod.rs,kbs.rs}`（feature `kbs`）
  - `config/{mod.rs,ocicrypt_config.rs}`
  - `bin/*`（grpc/ttrpc server、tool、oneshot、secret CLI）

### 5.2 KMS providers（`confidential-data-hub/kms/`）

- 包名 `kms`。`src/lib.rs` 暴露 `new_decryptor`/`new_getter`，模块 `api`、`error`、`plugins`。
- **关键 trait**（`api.rs`）：
  - `Decrypter`：`decrypt`（`:44`）
  - `Encrypter`：`encrypt`（`:57`）
  - `Setter`：`set_secret`（`:67`）
  - `Getter`：`get_secret`（`:75`）
  - 别名：`ProviderSettings`、`Annotations`（`:38,41`）
- **Provider 实现**：
  - **aliyun**：`plugins/aliyun/`（feature `aliyun`）——`client/{client_key_client, ecs_ram_role_client, sts_token_client}`、`annotations.rs`、`mod.rs`；`AliyunKmsClient` 实现 `Decrypter`+`Getter`
  - **aws**：`plugins/aws/`（feature `aws`）——`client.rs`/`credential.rs`/`annotations.rs`/`mod.rs`；`AwsKmsClient` 依赖 `aws-sdk-kms`/`aws-sdk-secretsmanager`
  - **kbs**：见 §5.4
- 枚举分发：`DecryptorProvider{Aliyun,Aws}`、`VaultProvider{Kbs,Aliyun,Aws}`（`plugins/mod.rs:23,54`），均 `#[cfg(feature=…)]` 门控。CDH `default = ["aliyun","kbs",…]`（`hub/Cargo.toml:95`），`kms` 默认 `["aliyun","kbs"]`（`kms/Cargo.toml:50`）。

### 5.3 resource service 如何按 ResourceDescription 寻址

- KBS 资源由 `kms/src/plugins/kbs/mod.rs` 的 `trait Kbc`（`get_resource(ResourceUri)` `:23`）与 `KbcClient` 枚举（`Cc`/`OfflineFs` `:29`）承担。
- `KbcClient::new()`（`:36`）读取 `AA_KBC_PARAMS` 环境变量（格式 `kbc::uri`，见 `attestation-agent/attestation-agent/src/config/aa_kbc_params.rs:33`，也读内核 cmdline `agent.aa_kbc_params=`），按 `kbc` 名选择 `cc_kbc` 或 `offline_fs_kbc`。
- 更底层：`image-rs/src/resource/mod.rs` 的 `ResourceProvider::get_resource`（`:73`）按 URL scheme 分发：`kbs://`（→ `kbs::SecureChannel`）或 `file://`（本地文件）。CDH 内 `Hub::get_resource` 直接走 `kms::new_getter("kbs")`。

### 5.4 KBC 类型

- `cc_kbc`（feature `kbs`）：`plugins/kbs/cc_kbc.rs` 的 `CcKbc`，内持 `kbs_protocol::KbsClient<Box<dyn TokenProvider>>`，用 `AATokenProvider::new_with_socket(aa_socket)` 经 AA 拿 token 再取资源（`:20-65`）。
- `offline_fs_kbc`（**始终编译**）：`plugins/kbs/offline_fs.rs` 的 `OfflineFsKbc`，从 `/etc/aa-offline_fs_kbc-keys.json`、`/etc/aa-offline_fs_kbc-resources.json` 及 `OFFLINE_FS_KBC_EXTRA_FILE_PATH` 载入 base64 资源到内存 HashMap（`:19-89`）。
- `KbcClient` 默认 `kbc = "offline_fs_kbc"`（`AaKbcParams::default`，`aa_kbc_params.rs:23`）。

### 5.5 sealed secret（密封卷）机制（D2 重点，src 内非 docs）

- 入口：`confidential-data-hub/hub/src/secret/mod.rs`
  - `unseal_secret()`（`:48`）：先做 UTF-8 解码（允许 `SKIP_SEALED_SECRET_VERIFICATION` 跳过验签），再 `Secret::from_signed_base64_string`（`:71`）解析 `sealed.<JWS>.<base64>` 形式的签名密钥封套
  - `enum SecretContent { Envelope(EnvelopeSecret), Vault(VaultSecret) }`（`:31-36`）、`VERSION = "0.1.0"`（`:46`）、`SIGNING_CREDENTIALS_PATH`（`:29` = `/run/confidential-containers/cdh/sealed-secret`）
  - `Secret::unseal()`（`:60`）按类型分发到 `layout/envelope.rs`（`EnvelopeSecret`）与 `layout/vault.rs`（`VaultSecret`）
- 该逻辑由 `DataHub::unseal_secret` 经 `bin/secret_cli.rs`（CLI）暴露——即 CDH 的 `secret` 命令行工具用于解封密封密钥。

---

## 六、image-rs（镜像拉取 / 解密 / 签名）

### 6.1 入口与模块树（`image-rs/`）

- 包名 `image-rs`。`src/lib.rs` 模块：`auth`、`builder`、`bundle`、`config`、`decoder`、`decrypt`、`digest`、`image`、`layer_store`、`meta_store`、`pull`、`registry`、`resource`、`signature`、`snapshots`、`stream`，feature `verity` 下还有 `verity`。
- **拉取**：`pull.rs`、`registry/mod.rs`、`builder.rs`、`image.rs`、`stream/{mod,unpack.rs}`、`bundle.rs`、`layer_store.rs`、`meta_store.rs`
- **解密**：`decrypt.rs`（`struct Decryptor` `:54`、`DecryptLayerError`），feature `encryption` 下的 `mod encryption` 调 `ocicrypt_rs`（`:69-90`）
- **签名**：`signature/mod.rs`（`SignatureValidator`）、`signature/policy/{mod,simple,cosign,ref_match,policy_requirement}`、`signature/image/`、`signature/payload/{mod,simple_signing}`

### 6.2 签名验证方案与 trait

- **核心类型** `SignatureValidator`（`src/signature/mod.rs:60`），方法 `check_image_signature()`（`:122`）、`new()`（`:159`），错误 `SignatureError`（`:28`）
- **策略模型** `signature/policy/mod.rs`：`Policy`（`:91`）、`PolicyReqType`（Accept/Reject/SimpleSigning/Cosign）、`requirements_for_image()`（`:103`，按 transport + 命名空间匹配 `containers-policy.json.5` 风格策略）
- **Simple Signing（PGP）**：`signature/policy/simple/`（`mod.rs`、`sigstore.rs`、`verify.rs`、`xrss.rs`），参数 `SimpleParameters`（`policy/mod.rs:50`），底层 `payload/simple_signing.rs`
- **Cosign（sigstore）**：`signature/policy/cosign/mod.rs`，参数 `CosignParameters`（`policy/mod.rs:28`），依赖 `sigstore` crate
- **feature 门控**（`image-rs/Cargo.toml:77-118`）：默认 `["signature-cosign","keywrap-grpc","signature-simple-xrss"]`；`kata-cc` 启用 `encryption`、`signature-simple/cosign`、`keywrap-ttrpc`、`kbs`。未启用对应 feature 时，`SignatureValidator` 内相关方法会 `bail!("feature ... not enabled")`。

### 6.3 auth（credential）模块

- `src/auth/mod.rs` + `src/auth/auth_config.rs`：封装 `oci_client::secrets::RegistryAuth` 与注册表凭据配置（env / kubeconfig 等）。`tests/credential.rs` 有相关集成测试。

### 6.4 如何调用 ocicrypt-rs 与 CDH/KBS

- **ocicrypt-rs**：`decrypt.rs` 的 `mod encryption`（feature `encryption`）直接 `use ocicrypt_rs::{config, encryption, helpers, spec}`，调用 `async_decrypt_layer`/`decrypt_layer`/`decrypt_layer_key_opts_data`/`create_decrypt_config`（`decrypt.rs:71-80`）。
- **CDH/KBS**：`resource/mod.rs` 的 `ResourceProvider::get_resource`（`:73`）按 scheme 分发；`resource/kbs/mod.rs` 的 `SecureChannel`（`:34`）持 `Box<dyn Client>`，feature `keywrap-ttrpc`→`ttrpc::Ttrpc`、feature `keywrap-grpc`→`grpc::Grpc`（`:24-28, :60-68`）。其 `get_resource()`（`:109`）把 `kbs://` URI 经 `GetResourceService`（典型即 CDH）取回并缓存到 `/run/image-security/kbs/<sha256>`（`STORAGE_PATH`，`:31`）。

---

## 七、ocicrypt-rs（镜像加解密库）

- 包名 `ocicrypt-rs`。模块（`src/lib.rs`）：`config`、`helpers`、`keywrap`、`spec`、`utils`，feature `block-cipher` 下 `blockcipher`、`encryption`。
- **`KEY_WRAPPERS`**（`src/lib.rs:23`）：`LazyLock<HashMap<String, Box<dyn KeyWrapper>>>`——全局密钥封装器注册表。feature `keywrap-jwe` 注册 `jwe`，feature `keywrap-keyprovider` 按 `ocicrypt config` 注册 `provider.<name>`。`get_key_wrapper()`（`:65`）、`get_wrapped_keys_map()`（`:73`）。
- **KeyWrapper trait**（`src/keywrap/mod.rs:18`）：`wrap_keys`、`unwrap_keys`、`annotation_id`、`probe`、`private_keys`、`keyids_from_packet`、`recipients`；对 `Box<W>` 有 blanket impl（`:53`）。
- **加密方案实现**：
  - **JWE**：`keywrap/jwe.rs` 的 `JweKeyWrapper`（`:18`），用 `josekit` 的 `ECDH_ES_A256KW`、`RSA_OAEP`（encrypter/decrypter 工厂 `:21,51`）。feature `keywrap-jwe`。
  - **keyprovider**：`keywrap/keyprovider/mod.rs` 的 `KeyProviderKeyWrapper`（大文件 ~45KB），按 annotation 调外部 keyprovider 进程/服务（keyprovider-cmd / keyprovider-grpc / keyprovider-ttrpc，feature `keywrap-keyprovider*`）。
- 块加密：`blockcipher/{mod,aes_ctr,rand}`、`encryption.rs`、`spec.rs`（媒体类型常量 `MEDIA_TYPE_LAYER_ENC` 等）、`helpers.rs`、`utils/{mod,runner}`。

---

## 八、protos（RPC 接口定义）

- 包名 `protos`。feature `grpc`（tonic）/ `ttrpc`（ttrpc-codegen）生成两套绑定；`build` 需 protoc（`Makefile:82-93`）。
- **.proto 文件与 RPC**（`protos/protos/`）：
  - `attestation-agent/attestation-agent.proto`：`service AttestationAgentService` —— `GetEvidence`、`GetAdditionalEvidence`、`GetToken`、`ExtendRuntimeMeasurement`、`BindInitData`、`GetTeeType`、`GetAdditionalTees`
  - `confidential-data-hub/api.proto`：`service SealedSecretService{UnsealSecret}`、`GetResourceService{GetResource}`、`SecureMountService{SecureMount}`、`ImagePullService{PullImage}`
  - `confidential-data-hub/aliyun.proto`（`package dkms_api`）：`Encrypt`、`Decrypt`、`GetSecretValue` 消息（阿里云 KMS/DKMS）
  - `confidential-data-hub/keyprovider.proto`（`package keyprovider`）：`service KeyProviderService{WrapKey, UnWrapKey}`，由 `coco_keyprovider` 实现（§4.6）

---

## 九、api-server-rest（REST 网关）

- 包名 `api-server-rest`。入口 `src/main.rs` + `src/router.rs` + `src/client/{aa,cdh,ttrpc_client,mod}.rs` + `src/utils.rs`。
- **REST 路由表**（`src/router.rs` 的 `Router::route`，`:96`）：
  - `/info`（GET，`:114`）：返回版本 / tee / additional_tees / feature 的 JSON
  - `/aa/*`（`AA_ROOT="/aa"`，`:18`）：
    - `GET /aa/token?token_type=`（`:158`）
    - `GET /aa/evidence?runtime_data=&encoding=`（`:173`）
    - `GET /aa/additional-evidence`（`:197`）
    - `POST /aa/aael`（`:221`，扩展 AAEL 事件；`is_reserved_aael_domain` 守卫 `github.com/confidential-containers`（`:39-42`），拒绝工作负载伪造组件事件）
  - `/cdh/*`（`CDH_ROOT="/cdh"`，`:13`）：`GET /cdh/resource/<path>`（`:276`）→ `CDH_RESOURCE_URL="/resource"`
  - 所有请求要求 **loopback** 来源（`router.rs:101`），否则 403
- **如何 ttrpc 转发**：
  - `client/aa.rs`：`AAClient`（`:44`）内持 `CachedTtrpcClient<AttestationAgentServiceClient>`，方法 `get_token`/`get_evidence`/`get_additional_evidence`/`extend_aael_entry`/`get_tee_type`/`get_additional_tees`，全部经 `AttestationAgentService` ttrpc（protos `protos::ttrpc::aa::attestation_agent`）
  - `client/cdh.rs`：`CDHClient`（`:20`）持 `CachedTtrpcClient<GetResourceServiceClient>`，`get_resource` 经 `GetResourceService` ttrpc（protos `protos::ttrpc::cdh::api`）
  - `client/ttrpc_client.rs`：`CachedTtrpcClient` 提供连接缓存 + 重试（`call_with_retry`），超时常量 `TTRPC_TIMEOUT`
- **结论**：`api-server-rest` 本质是一个 **REST→ttrpc 反向代理**，把本地 loopback HTTP 转成对 AA 与 CDH 的 ttrpc 调用。

---

## 十、通信与数据流（端到端）

```
[消费方: kata / cloud-api-adaptor 编排]
        │
        ▼
  api-server-rest (REST : loopback)
        │  ttrpc
   ┌────┴─────────────┐
   ▼                  ▼
 attestation-agent   confidential-data-hub
 (AA, 生成证据)       (CDH, 取密钥/资源/密封)
   │  evidence          │ 经 ttrpc 调 AA.ExtendRuntimeMeasurement 记录 PullImage AAEL
   │  ─────────────────┤
   ▼  KBS/Trustee(RCAR/Passport)   ◄── kbs_protocol::KbsClient
 image-rs (拉镜像 → decrypt 用 ocicrypt-rs → signature 验证)
   │
   ▼
 机密工作负载（拿到解密密钥 / 密封密钥，启动）
```

典型“拉取加密镜像”时序：
1. 工作负载经 ASR `/cdh/resource` 或 image-rs 直接请求资源
2. CDH 调 AA 的 `ExtendRuntimeMeasurement` 把“正在拉镜像”事件写进硬件测量寄存器（AAEL）
3. image-rs `decrypt` 调用 `ocicrypt_rs` 解密层；解 KEK 时经 `resource/kbs` 向 CDH（`GetResourceService`）请求密钥，CDH 再经 KBS 客户端向 KBS/Trustee 证明并取回
4. 签名验证（simple/cosign）决定镜像是否可信

---

## 十一、构建系统（Makefile）

- **顶层变量**（`Makefile:1-12`）：`TEE_PLATFORM ?= fs`、`ARCH ?= $(uname -m)`、`LIBC ?= musl`、`ATTESTER`、`ENABLE_KBS ?= true`（默认开 `kbs`/`cc_kbc`，`offline_fs_kbc` 始终编入）
- **`TEE_PLATFORM → ATTESTER` 映射**（`Makefile:18-36`）：
  - `none`/`fs` → `none`；`tdx` → `tdx-attester`；`az-cvm-vtpm` → `az-snp-vtpm-attester,az-tdx-vtpm-attester`；`snp`/`amd` → `snp-attester`；`se` → `se-attester`；`cca` → `cca-attester`；`all` → `all-attesters`
  - **CSV 未接入**：`Makefile:37` 注释 `# TODO: Add support for CSV`（即 `TEE_PLATFORM=csv` 不会自动选 `csv-attester`，仅 `all` 或显式 feature 才编入）
- **交叉编译 target**：`BUILD_DIR = target/$(ARCH)-unknown-linux-$(LIBC)/release`（`:56`）；产物 `confidential-data-hub`/`attestation-agent`/`api-server-rest`。s390x/powerpc64le 强制 `LIBC=gnu`（`:47-50`）
- **build 目标**（`Makefile:62-75`）：串行调三个子 make——CDH（`make ENABLE_KBS=…`）、AA（`make ttrpc=true ARCH=… ATTESTER=…`）、ASR（`make ARCH=… LIBC=…`）
- **build-protos**（`:82-93`）：Debian 下自动 `apt-get install protobuf-compiler`，再 `cargo build -p protos --features build`
- **fmt**（`:95-96`）：`cargo fmt --all -- --check`
- **lint**（`:98-103`）：依次 `make -C $(AA) lint`、`$(CDH) LIBC=gnu lint`、`$(ASR) lint`、`image-rs lint`、`ocicrypt-rs lint`（clippy -D warnings，多特性矩阵）
- **test**（`:107-115`）：同样跨 AA/CDH(LIBC=gnu)/ASR/image-rs/ocicrypt-rs；CDH 与 image-rs 集成测试需 root（loop/zfs 设备、`/etc` fixtures）
- **clean**（`:117-118`）：`rm -rf target`
- 各子 crate 各自有 `Makefile` 把 `ATTESTER`/`ENABLE_KBS` 映射为具体 cargo `--features`（AA 顶层默认 `default = ["ttrpc","grpc"]`）

---

## 十二、feature 门控速查

- **Attesters**（均 feature 门控）：`tdx`、`sgx`、`az-snp-vtpm`、`az-tdx-vtpm`、`snp`、`csv`、`hygon-dcu`、`cca`、`se`、`tpm`、`nvidia`、`nvidia-dpu`（`attester/Cargo.toml:71-117`、`attestation-agent/Cargo.toml:73-115`）。默认 `all-attesters`。
- **KMS/Vault providers**（CDH kms）：`aliyun`、`aws`、`kbs`（`kms/Cargo.toml:49-65`，CDH `hub/Cargo.toml:94-104`）
- **KBC**：`cc_kbc`（feature `kbs`）/ `offline_fs_kbc`（始终）
- **image-rs**：`encryption`、`keywrap-grpc`/`keywrap-ttrpc`（二者择一，缺则 `compile_error`）、`keywrap-jwe`、`signature-simple`、`signature-cosign`、`kbs`、`verity`（`image-rs/Cargo.toml:77-118`）
- **ocicrypt-rs**：`block-cipher`、`keywrap-jwe`、`keywrap-keyprovider*`（cmd/grpc/ttrpc）、`async-io`
- **AA token/AS**：`kbs`（→ KBS token）、`coco_as`（→ CoCo AS token）、`token`
- **kbs_protocol**：`background_check`（RCAR）、`passport`、`all-attesters`、`pqc-experimental`（ML-KEM，默认关，`kbs_protocol/Cargo.toml:83-86`）

---

## 十三、安全与代码风格约定（速记）

- 属于 TCB，**尽量缩小攻击面**，新代码要有验证安全属性的测试。
- 错误处理：`thiserror` 定义公共 API 的域错误枚举（如 `SignatureError`、`DecryptLayerError`）；内部传播用 `anyhow::Result`。
- 异步：Tokio + `#[tokio::main]`，异步 trait 用 `async-trait`。
- 日志：`tracing`（`info!`/`debug!`/`warn!`/`error!`），不用 `#[instrument]`。
- 序列化：JSON（配置/API）、TOML（配置文件）、protobuf（RPC）。
- 测试属性：`#[tokio::test]`、`#[serial_test::serial]`、`rstest`；很多测试用 `#[cfg(feature = "...")]` 门控。
- 依赖版本集中在根 `Cargo.toml` 的 `[workspace.dependencies]`，各 crate 用 `dep.workspace = true` 引用。
- 提交 / PR 标题带子系统前缀（`attester:`、`cdh:`、`asr:`、`ci:`），每个 commit 应能独立编译、改动原子化。

---

## 十四、与 Trustee 的关系

`confidential-containers/trustee` 是 guest-components 的“外部 counterpart”：它作为 RATS 模型里的**依赖方 / 验证方**跑在 TEE 之外，消费硬件证据、给机密 Guest 发放证明令牌和机密。

- 两个仓库**配套开发、配套发布**，但**解耦、可独立使用**。
- guest-components 的 `kbs-protocol` crate 被 Trustee 的 `kbs-client` 子项目消费。
- 本地无真实 TEE 时，可用 `sample` / `sample-device` attester/verifier 桩跑端到端流程，但**绝不能**让桩证据进入生产。

---

## 十五、个人开发切入点（D2）

1. **海光 CSV attester（M1）**：
   - 位置 `attestation-agent/attester/src/csv/mod.rs`，已实现 `Attester` 全部 6 方法且功能完整
   - **待补构建入口**：在 `Makefile` 的 `TEE_PLATFORM` 映射里加 `csv → csv-attester`（消除 `Makefile:37` 的 TODO）
   - 参考其它 attester（tdx/snp）的接口与 trait 风格；注意真实 TEE 与 sample 桩的边界
2. **CDH sealed secret（密封卷）**：
   - 围绕 `confidential-data-hub/hub/src/secret/mod.rs` 与 `layout/{envelope,vault}.rs`，依赖 `secret-cli` 暴露
   - 改动要兼顾密钥安全与生命周期（签名凭据路径 `/run/confidential-containers/cdh/sealed-secret`）
3. **涉及 `kbs-types` 字段变更**：务必先与上游 D4 协调，避免协议漂移（它跨项目共享，版本 `0.18.0`）

> 提示：本机 shell 里 `cargo`/`rustc` 可能不在 PATH，需要先 `source ~/.cargo/env` 或用绝对路径；Bash 沙箱代理可能挡 GitHub 与 crates.io。

---

## 十六、交付产物与运行位置（产物 → 消费方 → 在哪跑）

本项目**不发布成终端用户 App**，而是机密容器运行时的 TCB 组件源。其产出分两类：**可直接运行的守护进程二进制** 与 **被上游链接的库**。

### 16.1 产物总览

```
本仓库 (guest-components workspace) 编译产出
│
├─ 二进制守护进程（make build → 默认 musl 静态）
│   ├─ confidential-data-hub (CDH)        ← Makefile:52 产物名
│   ├─ attestation-agent     (AA)         ← ttrpc-aa / grpc-aa 两种 RPC 变体
│   └─ api-server-rest       (ASR)
│         │  install 到 /usr/local/bin，由 kata 运行时 / cloud-api-adaptor 编排
│         ▼
│   【运行位置：机密 VM 内 / Guest TEE】
│
├─ 库（被上游消费，不直接运行）
│   ├─ image-rs      ──► kata-containers agent / 容器运行时（Guest 内）
│   ├─ ocicrypt-rs   ──► image-rs 依赖（Guest 内）
│   ├─ protos        ──► AA/CDH 的 ttrpc/gRPC 接口生成代码
│   └─ kbs_protocol / attester / kms / resource_uri / crypto ──► AA/CDH 内部支撑库
│
└─ 外部 counterpart（非本仓库产物，但紧密配合）
    └─ Trustee / KBS ──► 【运行位置：TEE 之外（Host 侧或远程服务）】
```

### 16.2 产物 → 消费方 → 运行位置 对照表

| 产物 | 类型 | 消费方（谁用它） | 运行位置 |
|---|---|---|---|
| `confidential-data-hub`（CDH） | 二进制守护进程 | kata 运行时 / cloud-api-adaptor 启动 | **机密 VM 内（Guest）** |
| `attestation-agent`（AA） | 二进制守护进程（ttrpc-aa/grpc-aa） | 同上，先启动 | **机密 VM 内（Guest）** |
| `api-server-rest`（ASR） | 二进制守护进程（REST→ttrpc） | 本地 loopback 调用 | **机密 VM 内（Guest）** |
| `image-rs`（lib） | 库 | kata-containers agent / 容器运行时链接 | **机密 VM 内（Guest）** |
| `ocicrypt-rs`（lib） | 库 | image-rs 依赖 | **机密 VM 内（Guest）** |
| `protos`（lib） | 生成代码 | AA/CDH 内部 RPC | 随 AA/CDH 编入 Guest |
| `kbs_protocol` / `attester` / `kms` / `resource_uri` / `crypto`（lib） | 支撑库 | AA/CDH 内部 | 随 AA/CDH 编入 Guest |
| `trustee-attester` / `coco_keyprovider` / `evidence_getter` / `secret` 等 | 辅助 CLI | 调试 / 注册密钥 / 解封 | 多在 Guest 内或构建期工具 |
| **Trustee / KBS** | 外部服务（非本仓） | 验证证据、发令牌与密钥；KMS/离线文件为密钥源 | **TEE 之外（Host 或远程）** |

### 16.3 运行时布局图（Guest 边界）

```
┌──────────────────── 机密 VM 边界 / Guest TEE ────────────────────┐
│                                                                 │
│  containerd / kata agent ──(链接)──► image-rs + ocicrypt-rs       │
│        │  ttrpc / gRPC                                          │
│        ▼                                                        │
│   ┌────────┐   ┌────────┐   ┌────────────┐                      │
│   │  AA    │   │  CDH   │   │   ASR      │  (REST, 仅 loopback) │
│   │证明代理│   │数据中枢│   │  网关      │                      │
│   └───┬────┘   └───┬────┘   └────────────┘                      │
│       │            │ 经 kbs_protocol 向外证明 / 取密钥           │
└───────┼────────────┼────────────────────────────────────────────┘
        │ HTTPS · RCAR(Background-Check) / Passport（出 TEE 的请求）
        ▼
┌──────────────── TEE 之外（Host 侧 / 远程） ──────────────────────┐
│  Trustee / KBS：验证硬件证据、签发证明令牌、下发机密密钥         │
│  密钥源：KMS（阿里云/AWS）、offline_fs_kbc 文件、Sealed Secret   │
└──────────────────────────────────────────────────────────────────┘
```

### 16.4 要点

- **三大守护进程**（CDH/AA/ASR）与 **image-rs/ocicrypt-rs 库** 都跑在**机密 VM（Guest TEE）里**，是 TCB 的一部分。
- **Trustee/KBS 跑在 TEE 之外**（Host 侧或独立远程服务），本仓库不产出它，但二者通过 `kbs_protocol` 配合完成「证明→取密钥」。
- 二进制默认 **musl 静态链接**（`Makefile: LIBC ?= musl`），便于塞进精简 guest 镜像；`make build TEE_PLATFORM=...` 按 TEE 平台裁剪 attester。
- 本仓库**不单独发布安装包**，而是作为组件源被 kata-containers / cloud-api-adaptor 编排进 guest。

---

## 十七、ASR REST API：接口与使用者

ASR（`api-server-rest`）本质是 **REST→ttrpc 反向代理**，把对 AA（证明）和 CDH（密钥/资源）的访问从 ttrpc 包装成标准 **HTTP**，供不会 ttrpc 的普通工作负载使用。定义见 `api-server-rest/openapi/api.json`（OpenAPI 3.1，监听 `http://127.0.0.1:8006`，仅 loopback）。

### 17.1 接口清单（6 个）

AA 组（转发给 attestation-agent）：

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/aa/token?token_type=` | 获取证明令牌（`tee_keypair` + JWT `token`） |
| GET | `/aa/evidence?runtime_data=&encoding=` | 获取 TEE 证据 |
| GET | `/aa/additional-evidence?runtime_data=&encoding=` | 获取附加证据（如 `sev-snp`） |
| POST | `/aa/aael` | 写入 AA 事件日志（AAEL），body = `AaelEvent{domain,operation,content}` |

CDH 组（转发给 confidential-data-hub）：

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/cdh/resource/{repository}/{type}/{tag}` | 按资源路径取回机密资源 |

通用：

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/info` | 版本/能力信息（`VersionInfo`：`version`/`tee`/`additional_tees`/`feature`） |

> 统一错误码：`403`（禁止外部/非 loopback 访问）、`404`、`405`（方法不允许）；AA 组另带 `400`（参数错误）。`/aa/aael` 的 `domain` 若用保留命名空间 `github.com/confidential-containers` 会被 403 拒绝（防工作负载伪造组件事件）。

### 17.2 谁在用（使用者）

- **机密工作负载本身（应用容器 / sidecar / init 容器）—— 核心用户**：运行时经 `/cdh/resource` 拉密钥/密封卷/KMS 资源；经 `/aa/token`、`/aa/evidence`、`/aa/additional-evidence` 生成证明物，向外部依赖方（KBS/依赖服务）证明自己跑在真实 TEE 上；经 `/aa/aael` 写运行期事件扩展硬件测量（measured boot / 远程证明完整性）；`/info` 探活与能力发现。
- **kata-containers agent（guest 内虚机代理）**：编排容器时也会用（取资源、做测量），但它更常直接走 ttrpc 与 AA/CDH 通信，REST 是 HTTP 备选项。

### 17.3 谁**不**用

- **外部验证方 / 依赖方**：跟 **KBS / Trustee** 交互（RCAR/Passport），不经过这个 loopback REST。
- **Host 侧 cloud-api-adaptor**：负责拉起机密 VM、注入配置，但不打 guest 内 loopback REST。

> 设计意图：ASR 让「只会 HTTP 的普通应用」也能消费 TCB 能力；真正「对外证明」的链路是 **AA → KBS/Trustee**（经 `kbs_protocol`），与此 REST 面无关。
