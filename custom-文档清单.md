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

| 序号 | 译文文件 | 对应原文 | 原文基准 (commit@日期) | 类型 |
|---|---|---|---|---|
| 1 | [api-server-rest/custom-README.md](api-server-rest/custom-README.md) | [api-server-rest/README.md](api-server-rest/README.md) | c8cef69b@2026-10-20 | 翻译 |
| 2 | [attestation-agent/attester/custom-README.md](attestation-agent/attester/custom-README.md) | [attestation-agent/attester/README.md](attestation-agent/attester/README.md) | bd40486b@2026-06-26 | 翻译 |
| 3 | [attestation-agent/coco_keyprovider/custom-README.md](attestation-agent/coco_keyprovider/custom-README.md) | [attestation-agent/coco_keyprovider/README.md](attestation-agent/coco_keyprovider/README.md) | 8709d40b@2026-10-16 | 翻译 |
| 4 | [attestation-agent/custom-README.md](attestation-agent/custom-README.md) | [attestation-agent/README.md](attestation-agent/README.md) | 8338f138@2026-10-13 | 翻译 |
| 5 | [attestation-agent/docs/custom-IMAGE_ENCRYPTION.md](attestation-agent/docs/custom-IMAGE_ENCRYPTION.md) | [attestation-agent/docs/IMAGE_ENCRYPTION.md](attestation-agent/docs/IMAGE_ENCRYPTION.md) | ee2b1f15@2026-09-18 | 翻译 |
| 6 | [attestation-agent/docs/custom-IMPLEMENTATION.md](attestation-agent/docs/custom-IMPLEMENTATION.md) | [attestation-agent/docs/IMPLEMENTATION.md](attestation-agent/docs/IMPLEMENTATION.md) | ee2b1f15@2026-09-18 | 翻译 |
| 7 | [attestation-agent/docs/custom-RESOURCE_URI.md](attestation-agent/docs/custom-RESOURCE_URI.md) | [attestation-agent/docs/RESOURCE_URI.md](attestation-agent/docs/RESOURCE_URI.md) | fa70c5d6@2026-08-14 | 翻译 |
| 8 | [attestation-agent/kbs_protocol/src/bin/trustee-attester/custom-README.md](attestation-agent/kbs_protocol/src/bin/trustee-attester/custom-README.md) | [attestation-agent/kbs_protocol/src/bin/trustee-attester/README.md](attestation-agent/kbs_protocol/src/bin/trustee-attester/README.md) | 13404cc0@2026-10-10 | 翻译 |
| 9 | [confidential-data-hub/custom-README.md](confidential-data-hub/custom-README.md) | [confidential-data-hub/README.md](confidential-data-hub/README.md) | 4f7aeded@2026-08-27 | 翻译 |
| 10 | [confidential-data-hub/docs/custom-RESOURCES_SERVICES.md](confidential-data-hub/docs/custom-RESOURCES_SERVICES.md) | [confidential-data-hub/docs/RESOURCES_SERVICES.md](confidential-data-hub/docs/RESOURCES_SERVICES.md) | 73c1d021@2026-08-14 | 翻译 |
| 11 | [confidential-data-hub/docs/custom-SEALED_SECRET.md](confidential-data-hub/docs/custom-SEALED_SECRET.md) | [confidential-data-hub/docs/SEALED_SECRET.md](confidential-data-hub/docs/SEALED_SECRET.md) | 4a00fe7b@2026-09-17 | 翻译 |
| 12 | [confidential-data-hub/docs/custom-SECURE_STORAGE.md](confidential-data-hub/docs/custom-SECURE_STORAGE.md) | [confidential-data-hub/docs/SECURE_STORAGE.md](confidential-data-hub/docs/SECURE_STORAGE.md) | 1e5c48c9@2026-05-12 | 翻译 |
| 13 | [confidential-data-hub/docs/kms-providers/custom-alibaba.md](confidential-data-hub/docs/kms-providers/custom-alibaba.md) | [confidential-data-hub/docs/kms-providers/alibaba.md](confidential-data-hub/docs/kms-providers/alibaba.md) | 40bac017@2026-09-17 | 翻译 |
| 14 | [confidential-data-hub/docs/kms-providers/custom-aws.md](confidential-data-hub/docs/kms-providers/custom-aws.md) | [confidential-data-hub/docs/kms-providers/aws.md](confidential-data-hub/docs/kms-providers/aws.md) | f27acb27@2026-07-27 | 翻译 |
| 15 | [confidential-data-hub/docs/use-cases/custom-secure-mount-with-aliyun-oss.md](confidential-data-hub/docs/use-cases/custom-secure-mount-with-aliyun-oss.md) | [confidential-data-hub/docs/use-cases/secure-mount-with-aliyun-oss.md](confidential-data-hub/docs/use-cases/secure-mount-with-aliyun-oss.md) | 0be56f8a@2024-04-16 | 翻译 |
| 16 | [confidential-data-hub/docs/use-cases/custom-secure-mount-with-block-device.md](confidential-data-hub/docs/use-cases/custom-secure-mount-with-block-device.md) | [confidential-data-hub/docs/use-cases/secure-mount-with-block-device.md](confidential-data-hub/docs/use-cases/secure-mount-with-block-device.md) | 1e5c48c9@2026-05-12 | 翻译 |
| 17 | [custom-README.md](custom-README.md) | [README.md](README.md) | 73c1d021@2026-08-14 | 翻译 |
| 18 | [custom-AGENTS.md](custom-AGENTS.md) | [AGENTS.md](AGENTS.md) | 13404cc0@2026-10-10 | 翻译 |
| 19 | [image-rs/custom-README.md](image-rs/custom-README.md) | [image-rs/README.md](image-rs/README.md) | ee2b1f15@2026-09-18 | 翻译 |
| 20 | [image-rs/docs/custom-ccv1_image_security_design.md](image-rs/docs/custom-ccv1_image_security_design.md) | [image-rs/docs/ccv1_image_security_design.md](image-rs/docs/ccv1_image_security_design.md) | ee2b1f15@2026-09-18 | 翻译 |
| 21 | [image-rs/docs/custom-design.md](image-rs/docs/custom-design.md) | [image-rs/docs/design.md](image-rs/docs/design.md) | f9ae4601@2023-07-13 | 翻译 |
| 22 | [image-rs/docs/custom-image_auth.md](image-rs/docs/custom-image_auth.md) | [image-rs/docs/image_auth.md](image-rs/docs/image_auth.md) | 0b763045@2024-10-29 | 翻译 |
| 23 | [image-rs/docs/custom-pull_image_with_nydus.md](image-rs/docs/custom-pull_image_with_nydus.md) | [image-rs/docs/pull_image_with_nydus.md](image-rs/docs/pull_image_with_nydus.md) | b4f0472d@2025-12-01 | 翻译 |
| 24 | [image-rs/docs/custom-registry_configuration.md](image-rs/docs/custom-registry_configuration.md) | [image-rs/docs/registry_configuration.md](image-rs/docs/registry_configuration.md) | 52b8de14@2025-04-08 | 翻译 |
| 25 | [image-rs/docs/quickstart/custom-image_signing.md](image-rs/docs/quickstart/custom-image_signing.md) | [image-rs/docs/quickstart/image_signing.md](image-rs/docs/quickstart/image_signing.md) | ee2b1f15@2026-09-18 | 翻译 |
| 26 | [image-rs/src/auth/custom-README.md](image-rs/src/auth/custom-README.md) | [image-rs/src/auth/README.md](image-rs/src/auth/README.md) | 7083aeda@2023-06-02 | 翻译 |
| 27 | [image-rs/src/signature/policy/cosign/custom-README.md](image-rs/src/signature/policy/cosign/custom-README.md) | [image-rs/src/signature/policy/cosign/README.md](image-rs/src/signature/policy/cosign/README.md) | f6320d34@2024-10-21 | 翻译 |
| 28 | [image-rs/src/signature/policy/simple/custom-README.md](image-rs/src/signature/policy/simple/custom-README.md) | [image-rs/src/signature/policy/simple/README.md](image-rs/src/signature/policy/simple/README.md) | f6320d34@2024-10-21 | 翻译 |
| 29 | [image-rs/test_data/custom-generate_test_data.md](image-rs/test_data/custom-generate_test_data.md) | [image-rs/test_data/generate_test_data.md](image-rs/test_data/generate_test_data.md) | 2f755e30@2023-07-31 | 翻译 |
| 30 | [image-rs/tests/custom-README.md](image-rs/tests/custom-README.md) | [image-rs/tests/README.md](image-rs/tests/README.md) | ee2b1f15@2026-09-18 | 翻译 |
| 31 | [ocicrypt-rs/custom-README.md](ocicrypt-rs/custom-README.md) | [ocicrypt-rs/README.md](ocicrypt-rs/README.md) | 2e23d995@2023-06-16 | 翻译 |
| 32 | [custom-项目理解.md](custom-项目理解.md) | （无原文） | — | **个人新增** |
| 33 | [custom-个人开发指南.md](custom-个人开发指南.md) | （无原文） | — | **个人新增** |

> 注：序号 32、33 为个人原创笔记（项目理解 / 个人开发指南），无固定原文，无过期概念，随项目认知更新即可。

## 统计

- 翻译类：`30` 份（覆盖仓库内几乎全部原始 `.md` 文档）
- 个人新增：`2` 份
- 合计：`32` 份 `custom-` 文件

## 维护约定

- 新增译文：同目录建 `custom-<原名>`，并在本表追加一行（填原文路径 + 原文基准 commit/日期）。
- 上游原文更新后：更新对应译文，并把「原文基准」刷新为该原文最新 commit。
- 删除某原文时：同步删除其 `custom-` 译文与本表行。
