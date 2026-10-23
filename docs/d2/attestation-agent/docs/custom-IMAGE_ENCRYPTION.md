# 镜像加密与解密

## 简介

正如 [CCv0 镜像安全设计](../../../../image-rs/docs/ccv1_image_security_design.md) 所述，CoCo 使用与 [ocicrypt](https://github.com/containers/ocicrypt) 和 [ocicrypt-rs](../../../../ocicrypt-rs) 兼容的镜像加密机制。

机密数据中枢（CDH）作为一个 [密钥提供方（Key Provider）](../../../../image-rs/docs/ccv1_image_security_design.md#update-manifest) 实现了 `unwrapkey` API，它与实现了 `wrapkey` API 的 [样例密钥提供方（Sample Key Provider）](../../../../attestation-agent/coco_keyprovider) 协同工作。

> [!NOTE]
> 这里的“样例密钥提供方”指的是 `coco_keyprovider` 参考工具整体（其正常的、使用真实 KEK 的加密模式）。这与 `coco_keyprovider` 的 `sample=true` 玩具模式不同，后者使用当前任何 CDH KBC 插件都不知道如何自动解密的硬编码密钥。详见
> [`coco_keyprovider` 的 README](../../../../attestation-agent/coco_keyprovider/README.md#the-encryption-protocol-explained)。

> [!NOTE]
> 历史上，`attestation-agent` 二进制本身实现了 `unwrapkey` API。该功能此后已迁移到 `confidential-data-hub`；CDH 仍然以遗留的 ocicrypt 提供方名称 `attestation-agent` 进行自标识，以保持向后兼容的注解（annotation）处理（参见 [`ocicrypt_config.rs`](../../../../confidential-data-hub/hub/src/config/ocicrypt_config.rs)）。

本文档将描述机密数据中枢和样例密钥提供方在镜像加密中所扮演的角色，同时也会定义一些规范。

## 镜像的加密与解密

### 加密

`wrapkey` API 与镜像加密直接相关。让我们看看镜像加密是如何发生的，例如，在 `ocicrypt-rs` 中（其背后的原理与 `ocicrypt` 相同）。假设有一个用户想要加密一个镜像层 `L`。

1. `ocicrypt-rs` 随机 [生成一个对称密钥](../../../../ocicrypt-rs/src/blockcipher/mod.rs#L167)。该密钥称为 LEK（Layer Encryption Key，用于加密层的密钥）。
2. `L` [被 LEK 加密](../../../../ocicrypt-rs/src/blockcipher/mod.rs#L169)
3. 该对称密钥连同其他私有信息一起，包含在一个名为 `PrivateLayerBlockCipherOptions` 的结构体中，即 [PLBCO](https://github.com/opencontainers/image-spec/pull/775/commits/bc0fcd698946be7e8bb1fa88f178ed2c66274aa2#diff-ecf63e7090e873922f62c4749c01f63f7eccd42912c1465fbee515cb7c4916c1R362)。
4. `PLBCO` 的明文将通过 `wrapkey` 的 gRPC 调用发送给样例密钥提供方。至此，步骤 1、2、3、4 是 `ocicrypt` 定义的标准行为。然后，如何为样例密钥提供方执行 `wrapkey` API 由 CoCo 定义，如 5、6 所述。
5. 样例密钥提供方将加密 `PLBCO`，并生成一个名为 `AnnotationPacket` 的结构体。一个 `AnnotationPacket` 包含：
    * `wrapped data`：即 `PLBCO` 的密文
    * `wrap type`：即用于加密 `PLBCO` 的加密方案。该字段的规范将在 [规范章节](../../../../attestation-agent/docs#specs) 中说明。
    * `iv`：本次加密的初始向量
    * `key id`：即用于加密 `PLBCO` 的密钥的身份标识。该密钥也称为 `KEK`（Key Encryption Key，用于加密 LEK 的密钥）。
6. `AnnotationPacket` 将被返回给 `ocicrypt-rs`，`ocicrypt-rs` 会将 base64 编码（标准）后的 `AnnotationPacket` 写入加密层的注解中，注解键为 `org.opencontainers.image.enc.keys.provider.attestation-agent`。

### 解密

`unwrapkey` API 与镜像解密直接相关。一个由 `样例密钥提供方` 加密的镜像层，可以在 `机密数据中枢` 的参与下被解密。步骤如下：
1. `ocicrypt-rs` 发现 `L` 是一个加密层，并且 `L` 带有 `org.opencontainers.image.enc.keys.provider.attestation-agent` 注解。
2. `ocicrypt-rs` 会通过 `unwrapkey` gRPC/ttRPC 将该注解的值发送给 `机密数据中枢`。
3. `机密数据中枢` 会将注解解析为一个 `AnnotationPacket`。
4. `机密数据中枢` 会使用 `AnnotationPacket`，调用配置的 KBC（例如 `cc_kbc` 或 `offline_fs_kbc`，参见 [资源服务](../../../../confidential-data-hub/docs/RESOURCES_SERVICES.md)）根据 `key id` 获取 `KEK`，然后解密 PLBCO。
7. `ocicrypt-rs` 使用 `PLBCO` 解密该层。

## 规范

本节给出 CoCo 涉及的镜像加密/解密的一些规范。

### 层注解（Layer Annotation）

正如 [ocicrypt](https://github.com/opencontainers/image-spec/pull/775/commits/bc0fcd698946be7e8bb1fa88f178ed2c66274aa2#diff-ecf63e7090e873922f62c4749c01f63f7eccd42912c1465fbee515cb7c4916c1R423) 中所述，一个用于解密 `PLBCO` 的指定协议，应当在镜像层 [OciDescriptor](https://github.com/opencontainers/image-spec/blob/main/descriptor.md) 的 [manifest](https://github.com/opencontainers/image-spec/blob/main/manifest.md) 中包含一个注解键值对。

在 CoCo 场景中，注解的键应为 `org.opencontainers.image.enc.keys.provider.attestation-agent`。这表示该镜像层可以通过调用注册在（遗留的）`attestation-agent` 提供方名称下的密钥提供方的 `unwrapkey` API 来解密，在当前部署中即为 `confidential-data-hub`。

### 注解包（Annotation Packet）

一个 `Annotation Packet` 是加密层的 [OciDescriptor](https://github.com/opencontainers/image-spec/blob/main/descriptor.md) 中 `org.opencontainers.image.enc.keys.provider.attestation-agent` 注解的值（该值为标准 base64 编码）。`Annotation Packet` 的格式影响着：
* CoCo 的密钥提供方如何包装 LEK。
* CDH 如何解包 LEK。
* 不同的 KBC 之间如何相互兼容。

我们将 `Annotation Packet` 的格式定义如下：
```json
{
    "kid": "<KEK 的身份标识>",
    "wrapped_data": "<已加密的 LEK（标准 base64 编码）>",
    "iv": "<加密方案的初始向量（标准 base64 编码）>",
    "wrap_type": "<用于加密 LEK 的加密方案>"
}
```

### 解密接口

一旦给定一个 `Annotation Packet`，CDH 就可以派发给配置的 KBC 来处理它。对于那些能够通过 `key id` 获取 KEK 明文的 KBC，CDH 可以使用 `KEK`、`wrapped_data`、`iv` 和 `wrap_type` 来执行解密操作。该功能由共享的 [`crypto`](../../../../attestation-agent/deps/crypto) crate 提供。

不同的 wrap 类型共享一个通用的解密接口，即
```rust
pub fn decrypt(encrypted_data: &[u8], key: &[u8], iv: &[u8]) -> Result<Vec<u8>>;
```

其中：
* `key` 是 `KEK`
* `iv` 是 `iv`
* `encrypted_data` 是 `wrapped_data`

我们可以在特定方案中重载其中一些参数（例如我们在 `aes-256-gcm` 中将 `iv` 用作 `nonce`）。

### Wrap 类型（Wrap Type）

Wrap Type 是 [`Annotation Packet`](../../../../attestation-agent/docs#annotation-packet) 中的一个字段，它说明了使用了什么加密/解密方案。目前，我们支持以下方案：
* `A256GCM`：AES，256 位密钥长度，Galois 计数器模式（GCM）。为了复用 `decrypt` API，我们约定：
    * `wrapped_data := ciphertext | Tag`。`Tag` 是认证标签，在 `aes-256-gcm` 中为 16 字节。
    * `iv` 字段实际上作为 `nonce` 使用。
* `A256CTR`：AES，256 位密钥长度，CTR 模式。

### OpenSSL 支持

默认情况下，解密依赖于 Rust 实现。
为了能在更多平台上利用硬件加速（例如 s390x），我们使用 OpenSSL 来实现加密/解密过程。
要启用 OpenSSL，用户可以开启 `openssl` 特性进行编译。
