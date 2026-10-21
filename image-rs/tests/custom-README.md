# image-rs 集成测试

该集成测试包含以下主要子类型测试集：
* 使用 [ocicrypt-rs](../../ocicrypt-rs) 进行镜像解密
* 镜像签名验证
* 异常镜像拉取回归矩阵（`odd_images.rs`）

解密与签名测试套件使用以下密钥代理客户端：
* `Offline-fs-kbc`

## 镜像解密

实现于 `image_decryption.rs`。

镜像解密将覆盖 `Offline-fs-kbc`：
* `Offline-fs-kbc` 使用 `ghcr.io/confidential-containers/test-container:encrypted`

每个测试套件会按以下步骤进行：

* 拉取镜像的 manifest，但不验证签名。
* 拉取上述镜像的各层。
* Ocicrypt-rs 会请求机密数据中枢（Confidential Data Hub）来解密层加密密钥（简称 LEK），该密钥是用密钥加密密钥（简称 KEK）加密的。KEK 存储在 KBS 中。
* Ocicrypt-rs 使用 LEK 解密各层。完成镜像拉取。

不同的 KBC 使用不同的协议格式，因此需要不同的 KBS 来加密镜像。关于如何生成 KBS 加密镜像，请参考以下链接：

* [使用 Offline-fs-kbc](../../confidential-data-hub/docs/RESOURCES_SERVICES.md)

## 镜像签名验证

实现于 `signature_verification.rs`。

镜像签名验证包含以下四个测试，如 <https://github.com/confidential-containers/guest-components/issues/43> 所述，即：

| |已签名镜像|未签名镜像|
|---|---|---|
|受保护的注册表|protected_signed_allow, protected_signed_deny|protected_unsigned_deny|
|未受保护的注册表|-|unprotected_unsigned_allow|

这里
* `protected_signed_allow`：允许从受保护的注册表拉取镜像，包括 `Simple Signing` 和 `Cosign`
* `protected_signed_deny`：拒绝从受保护的注册表拉取镜像，包括
    * 带有未知签名的 `Simple Signing`
    * 使用了错误公钥的 `Cosign`
* `protected_unsigned_deny`：拒绝从受保护的注册表拉取未签名的镜像
* `unprotected_unsigned_allow`：允许从未受保护的注册表拉取未签名的镜像

在 `signature_verification.rs` 中，测试按不同类型的 KBC 进行组织，这意味着对于每一个给定的 KBC，上述四个测试都会被覆盖。

## 注册表凭据获取

实现于 `credential.rs`。

注册表凭据获取将通过以下步骤来测试该功能：
- 从证明代理（Attestation Agent）获取 `auth.json`。测试的 KBC 是 `Offline-Fs-Kbc`。
- 尝试使用 `auth.json` 中匹配的凭据从私有注册表拉取镜像。

测试用例为
| 镜像引用 | 相关凭据 |
|---|---|
|`docker.io/liudalibj/private-busy-box` |`bGl1ZGFsaWJqOlBhc3N3MHJkIXFhego=`|
|`quay.io/liudalibj/private-busy-box`|`bGl1ZGFsaWJqOlBhc3N3MHJkIXFhego=`|

## 异常镜像拉取回归矩阵

实现于 `odd_images.rs`。

这些测试需要 root 权限来创建 overlay 快照，目前仅在 `x86_64` 上运行。

| 镜像标签 | 覆盖的回归场景 | 预期结果 |
|---|---|---|
| `odd-duplicated-layers` | 重复的层 digest | 拉取成功 |
| `odd-whiteout-agnhost` | whiteout 处理 | 拉取成功 |
| `odd-empty-pax` | 空的本地 PAX 值 | 拉取失败 |
| `odd-whiteout-deletion` | 删除型 whiteout 转换 | 拉取成功，且 `rootfs/etc/apache2` 不存在 |

这些镜像托管在 `ghcr.io/confidential-containers/test-container-image-rs:<tag>`。
