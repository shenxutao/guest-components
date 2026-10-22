# 个人文档清单（custom- 索引）

> 目的：作为本仓库所有 `custom-` 前缀文件的**总索引**，方便总览、并跟踪「译文相对 upstream 原文的过期情况」。
> 命名约定：每份译文与原文**同目录**、文件名加 `custom-` 前缀（个人新增文档直接放根目录，亦加 `custom-`）。

## 用法：如何发现「上游已更新、译文该同步」

「原文基准」列是**本地仓库中该原文最后一次被修改的提交与日期**（即翻译时所依据的版本）。当后续执行 `git fetch upstream` 后，若某原文在基准提交之后又有新提交，说明该译文可能已过期，需要重译对应段落。

```bash
git fetch upstream
# 检查某个原文是否在基准之后被改动（以 SEALED_SECRET 为例）
git log --oneline <基准commit>..upstream/main -- confidential-data-hub/docs/SEALED_SECRET.md
```

> 说明：本清单的「原文基准」取自**当前本地仓库历史**（fork 时拉取的快照）。若本地尚未 fetch 过 upstream，请先 `git fetch upstream` 再比对。

## 索引表

| 序号 | 译文文件 | 对应原文 | 原文基准 (commit@日期) | 类型 | 文档介绍 |
|---|---|---|---|---|---|
| 1 | [api-server-rest/custom-README.md](api-server-rest/custom-README.md) | [api-server-rest/README.md](api-server-rest/README.md) | c8cef69b@2026-10-20 | 翻译 | ASR 组件说明：REST 网关，把本地 loopback HTTP 请求转成对 AA 与 CDH 的 ttrpc 调用 |
| 2 | [attestation-agent/attester/custom-README.md](attestation-agent/attester/custom-README.md) | [attestation-agent/attester/README.md](attestation-agent/attester/README.md) | bd40486b@2026-06-26 | 翻译 | attester 库：各 TEE 平台证明器（CSV/TDX/SNP/CCA 等）实现与 `Attester` trait 约定 |
| 3 | [attestation-agent/coco_keyprovider/custom-README.md](attestation-agent/coco_keyprovider/custom-README.md) | [attestation-agent/coco_keyprovider/README.md](attestation-agent/coco_keyprovider/README.md) | 8709d40b@2026-10-16 | 翻译 | CoCo gRPC keyprovider：实现 `WrapKey` 生成 annotation 并向 KBS 注册密钥 |
| 4 | [attestation-agent/custom-README.md](attestation-agent/custom-README.md) | [attestation-agent/README.md](attestation-agent/README.md) | 8338f138@2026-10-13 | 翻译 | AA 组件总说明：远程证明代理，负责采集 TEE 证据、换取证明令牌 |
| 5 | [attestation-agent/docs/custom-IMAGE_ENCRYPTION.md](attestation-agent/docs/custom-IMAGE_ENCRYPTION.md) | [attestation-agent/docs/IMAGE_ENCRYPTION.md](attestation-agent/docs/IMAGE_ENCRYPTION.md) | ee2b1f15@2026-09-18 | 翻译 | 镜像加密方案：如何借助 AA/KBS 做镜像层加密与密钥分发 |
| 6 | [attestation-agent/docs/custom-IMPLEMENTATION.md](attestation-agent/docs/custom-IMPLEMENTATION.md) | [attestation-agent/docs/IMPLEMENTATION.md](attestation-agent/docs/IMPLEMENTATION.md) | ee2b1f15@2026-09-18 | 翻译 | AA 实现细节：模块结构、token 获取、Background-Check/Passport 两种 RATS 模型 |
| 7 | [attestation-agent/docs/custom-RESOURCE_URI.md](attestation-agent/docs/custom-RESOURCE_URI.md) | [attestation-agent/docs/RESOURCE_URI.md](attestation-agent/docs/RESOURCE_URI.md) | fa70c5d6@2026-08-14 | 翻译 | 资源 URI 格式规范（`kbs://` 等），用于在 KBS 中寻址机密资源 |
| 8 | [attestation-agent/kbs_protocol/src/bin/trustee-attester/custom-README.md](attestation-agent/kbs_protocol/src/bin/trustee-attester/custom-README.md) | [attestation-agent/kbs_protocol/src/bin/trustee-attester/README.md](attestation-agent/kbs_protocol/src/bin/trustee-attester/README.md) | 13404cc0@2026-10-10 | 翻译 | trustee-attester 工具：从 TEE 采集证据并向 Trustee 完成证明握手 |
| 9 | [confidential-data-hub/custom-README.md](confidential-data-hub/custom-README.md) | [confidential-data-hub/README.md](confidential-data-hub/README.md) | 4f7aeded@2026-08-27 | 翻译 | CDH 组件说明：机密数据中枢，统一提供密钥、资源、密封卷与镜像拉取 |
| 10 | [confidential-data-hub/docs/custom-RESOURCES_SERVICES.md](confidential-data-hub/docs/custom-RESOURCES_SERVICES.md) | [confidential-data-hub/docs/RESOURCES_SERVICES.md](confidential-data-hub/docs/RESOURCES_SERVICES.md) | 73c1d021@2026-08-14 | 翻译 | CDH 资源服务：按 `ResourceDescription` 寻址并分发各类机密资源 |
| 11 | [confidential-data-hub/docs/custom-SEALED_SECRET.md](confidential-data-hub/docs/custom-SEALED_SECRET.md) | [confidential-data-hub/docs/SEALED_SECRET.md](confidential-data-hub/docs/SEALED_SECRET.md) | 4a00fe7b@2026-09-17 | 翻译 | 密封密钥机制：把密钥密封到特定 TEE 实例，仅同实例可解封（D2 重点） |
| 12 | [confidential-data-hub/docs/custom-SECURE_STORAGE.md](confidential-data-hub/docs/custom-SECURE_STORAGE.md) | [confidential-data-hub/docs/SECURE_STORAGE.md](confidential-data-hub/docs/SECURE_STORAGE.md) | 1e5c48c9@2026-05-12 | 翻译 | 安全存储：LUKS2/ZFS 等加密卷与存储后端实现 |
| 13 | [confidential-data-hub/docs/kms-providers/custom-alibaba.md](confidential-data-hub/docs/kms-providers/custom-alibaba.md) | [confidential-data-hub/docs/kms-providers/alibaba.md](confidential-data-hub/docs/kms-providers/alibaba.md) | 40bac017@2026-09-17 | 翻译 | 阿里云 KMS/DKMS 接入方式 |
| 14 | [confidential-data-hub/docs/kms-providers/custom-aws.md](confidential-data-hub/docs/kms-providers/custom-aws.md) | [confidential-data-hub/docs/kms-providers/aws.md](confidential-data-hub/docs/kms-providers/aws.md) | f27acb27@2026-07-27 | 翻译 | AWS KMS / Secrets Manager 接入方式 |
| 15 | [confidential-data-hub/docs/use-cases/custom-secure-mount-with-aliyun-oss.md](confidential-data-hub/docs/use-cases/custom-secure-mount-with-aliyun-oss.md) | [confidential-data-hub/docs/use-cases/secure-mount-with-aliyun-oss.md](confidential-data-hub/docs/use-cases/secure-mount-with-aliyun-oss.md) | 0be56f8a@2024-04-16 | 翻译 | 用例：使用阿里云 OSS 做安全挂载 |
| 16 | [confidential-data-hub/docs/use-cases/custom-secure-mount-with-block-device.md](confidential-data-hub/docs/use-cases/custom-secure-mount-with-block-device.md) | [confidential-data-hub/docs/use-cases/secure-mount-with-block-device.md](confidential-data-hub/docs/use-cases/secure-mount-with-block-device.md) | 1e5c48c9@2026-05-12 | 翻译 | 用例：使用块设备做安全挂载 |
| 17 | [custom-README.md](custom-README.md) | [README.md](README.md) | 73c1d021@2026-08-14 | 翻译 | 仓库总览 README：组件组成、构建与消费方说明 |
| 18 | [custom-AGENTS.md](custom-AGENTS.md) | [AGENTS.md](AGENTS.md) | 13404cc0@2026-10-10 | 翻译 | 贡献者指南：架构约定、构建/测试/lint 流程与提交规范 |
| 19 | [image-rs/custom-README.md](image-rs/custom-README.md) | [image-rs/README.md](image-rs/README.md) | ee2b1f15@2026-09-18 | 翻译 | image-rs 组件说明：OCI 镜像拉取、解密与签名验证 |
| 20 | [image-rs/docs/custom-ccv1_image_security_design.md](image-rs/docs/custom-ccv1_image_security_design.md) | [image-rs/docs/ccv1_image_security_design.md](image-rs/docs/ccv1_image_security_design.md) | ee2b1f15@2026-09-18 | 翻译 | CCv1 镜像安全设计：机密容器镜像的安全模型 |
| 21 | [image-rs/docs/custom-design.md](image-rs/docs/custom-design.md) | [image-rs/docs/design.md](image-rs/docs/design.md) | f9ae4601@2023-07-13 | 翻译 | image-rs 整体设计：模块划分与拉取/解密流程 |
| 22 | [image-rs/docs/custom-image_auth.md](image-rs/docs/custom-image_auth.md) | [image-rs/docs/image_auth.md](image-rs/docs/image_auth.md) | 0b763045@2024-10-29 | 翻译 | 镜像仓库认证（credential）机制与配置 |
| 23 | [image-rs/docs/custom-pull_image_with_nydus.md](image-rs/docs/custom-pull_image_with_nydus.md) | [image-rs/docs/pull_image_with_nydus.md](image-rs/docs/pull_image_with_nydus.md) | b4f0472d@2025-12-01 | 翻译 | 使用 nydus 格式拉取镜像的说明 |
| 24 | [image-rs/docs/custom-registry_configuration.md](image-rs/docs/custom-registry_configuration.md) | [image-rs/docs/registry_configuration.md](image-rs/docs/registry_configuration.md) | 52b8de14@2025-04-08 | 翻译 | 注册表（registry）相关配置说明 |
| 25 | [image-rs/docs/quickstart/custom-image_signing.md](image-rs/docs/quickstart/custom-image_signing.md) | [image-rs/docs/quickstart/image_signing.md](image-rs/docs/quickstart/image_signing.md) | ee2b1f15@2026-09-18 | 翻译 | 镜像签名快速上手指南 |
| 26 | [image-rs/src/auth/custom-README.md](image-rs/src/auth/custom-README.md) | [image-rs/src/auth/README.md](image-rs/src/auth/README.md) | 7083aeda@2023-06-02 | 翻译 | auth 模块：注册表凭据配置（env / kubeconfig 等） |
| 27 | [image-rs/src/signature/policy/cosign/custom-README.md](image-rs/src/signature/policy/cosign/custom-README.md) | [image-rs/src/signature/policy/cosign/README.md](image-rs/src/signature/policy/cosign/README.md) | f6320d34@2024-10-21 | 翻译 | cosign（sigstore）签名验证策略说明 |
| 28 | [image-rs/src/signature/policy/simple/custom-README.md](image-rs/src/signature/policy/simple/custom-README.md) | [image-rs/src/signature/policy/simple/README.md](image-rs/src/signature/policy/simple/README.md) | f6320d34@2024-10-21 | 翻译 | simple signing（PGP）签名验证策略说明 |
| 29 | [image-rs/test_data/custom-generate_test_data.md](image-rs/test_data/custom-generate_test_data.md) | [image-rs/test_data/generate_test_data.md](image-rs/test_data/generate_test_data.md) | 2f755e30@2023-07-31 | 翻译 | 生成测试数据脚本的使用说明 |
| 30 | [image-rs/tests/custom-README.md](image-rs/tests/custom-README.md) | [image-rs/tests/README.md](image-rs/tests/README.md) | ee2b1f15@2026-09-18 | 翻译 | image-rs 集成测试说明（部分需 root） |
| 31 | [ocicrypt-rs/custom-README.md](ocicrypt-rs/custom-README.md) | [ocicrypt-rs/README.md](ocicrypt-rs/README.md) | 2e23d995@2023-06-16 | 翻译 | ocicrypt-rs 库：OCI 镜像层加解密与密钥封装（JWE/keyprovider） |
| 32 | [ocicrypt-rs/data/custom-generate_keys.md](ocicrypt-rs/data/custom-generate_keys.md) | [ocicrypt-rs/data/generate_keys.md](ocicrypt-rs/data/generate_keys.md) | 5d882e15@2023-06-02 | 翻译 | 测试密钥生成脚本说明：用 openssl 生成单测/集成测试所需的 RSA/EC 密钥、证书与口令文件 |
| 33 | [custom-项目理解.md](custom-项目理解.md) | （无原文） | — | **个人新增** | 个人原创：基于源码核实的项目架构理解（含组件/feature/时序） |
| 34 | [custom-个人开发指南.md](custom-个人开发指南.md) | （无原文） | — | **个人新增** | 个人原创：D2 主责（CSV attester + CDH sealed secret）开发指南 |
| 35 | [custom-D2连调runbook.md](custom-D2连调runbook.md) | （无原文） | — | **个人新增** | 个人原创：D2 连调详细指南（**顶部带锚点目录可跳转**；逐步骤命令+说明；offline_fs_kbc + none/all attester 免 Beeceptor；**步骤 8 含「测试 VM → 真海光 CSV」迁移映射，双用途**；含 mock KBS 草图） |
| 36 | [custom-CDH-SealedSecret.md](custom-CDH-SealedSecret.md) | （无原文） | — | **个人新增** | 个人原创：CDH sealed secret 信封格式（JWS ES256 外层 + Envelope/Vault 内层）与 secret_cli（二进制名 `secret`）用法、本地 Vault+offline_fs_kbc 端到端配方 |
| 37 | [custom-真机CSV部署.md](custom-真机CSV部署.md) | （无原文） | — | **个人新增** | 个人原创：真海光 CSV 机密服务器部署指南（D2 收尾/生产验明）；复用测试 VM 逻辑，只讲真机专属（构建口径/KBC 指向真 KBS/sealed secret 密钥预置/CSV 证据链路/kata 接入/验证检查表） |
| 38 | [custom-CSV证据与Trustee对齐.md](custom-CSV证据与Trustee对齐.md) | （无原文） | — | **个人新增** | 个人原创：D2↔D4 跨仓协调；CSV attester 证据格式（`CsvEvidence`/report_data 挑战绑定/证书链来源/RTMR+SM3）与 Trustee verifier 经 `kbs-types`(Tee::Csv/HashAlgorithm::Sm3/Response-Challenge) 的字段对齐清单与变更控制 |

> 注：序号 33、34、35、36、37、38 为个人原创笔记（项目理解 / 个人开发指南 / D2 连调 runbook / CDH sealed secret / 真机 CSV 部署 / CSV 证据与 Trustee 对齐），无固定原文，无过期概念，随项目认知更新即可。

## 统计

- 翻译类：`31` 份（覆盖仓库内全部原始 `.md` 文档）
- 个人新增：`5` 份
- 合计：`36` 份 `custom-` 文件

## 维护约定

- 新增译文：同目录建 `custom-<原名>`，并在本表追加一行（填原文路径 + 原文基准 commit/日期）。
- 上游原文更新后：更新对应译文，并把「原文基准」刷新为该原文最新 commit。
- 删除某原文时：同步删除其 `custom-` 译文与本表行。
