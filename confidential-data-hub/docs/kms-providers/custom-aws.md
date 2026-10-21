# AWS KMS 驱动

该驱动支撑两类密封密钥：

- **信封密钥（Envelope secrets）**：通过 [AWS KMS](https://aws.amazon.com/kms/)。数据加密密钥（DEK）通过 KMS 的 `Encrypt`/`Decrypt` 操作进行包装（wrap）/解包（unwrap）。
- **Vault 密钥**：通过 [AWS Secrets Manager](https://aws.amazon.com/secrets-manager/)。所指向的值通过 `GetSecretValue` 获取。

两者都由同一个客户端（`AwsKmsClient`）服务提供，使用同一组静态 IAM 凭据进行认证。

## 规范

### 常量与布局

| 名称         | 值   |
| ------------ | ------- |
| `provider`   | `aws`   |

[密封密钥](../SEALED_SECRET.md#format) 中定义的 `provider_settings` 和 `annotations` 如下：

#### provider_settings

| 名称       | 用途                                                     |
| ---------- | --------------------------------------------------------- |
| `region`   | KMS 密钥 / 密钥（secret）所在的 AWS 区域，例如 `us-east-1`。     |

KMS 密钥标识符（密钥 ID、ARN 或 `alias/...`）在信封密钥的 `key_id` 字段中携带。Secrets Manager 的密钥 ID（名称或 ARN）在 vault 密钥的 `name` 字段中携带。

#### annotations

##### 加密/解密（envelope）

| 名称                 | 用途                                                                                              |
| -------------------- | ------------------------------------------------------------------------------------------------- |
| `encryption_context` | （可选）AWS KMS 加密上下文（AAD）。如果在密封时设置，解封时必须与之匹配。     |

默认情况下它为空。当提供了 `encryption_context` 时，它会在密封时传递给 KMS `Encrypt` 并绑定进密文；随后在解封时必须提供完全相同的上下文，否则操作失败。AWS KMS 将 IV/nonce 嵌入在密文 blob 中，因此不使用 `iv` 注解。

##### get_secret（vault）

| 名称             | 用途                                                                       |
| ---------------- | --------------------------------------------------------------------------- |
| `version_id`     | （可选）获取密钥的特定版本。为空 = 当前版本。 |
| `version_stage`  | （可选）要获取的暂存标签。为空 = `AWSCURRENT`。                     |

### 凭据文件

要连接 AWS，需要一个凭据文件。它是一个包含静态 IAM 凭据的 JSON 文档：

```json
{
  "access_key_id": "AKIA...",
  "secret_access_key": "...",
  "session_token": null
}
```

`session_token` 是可选的，仅用于临时（STS）凭据。

在 TEE 内部，凭据文件应当放置在 `/run/confidential-containers/cdh/kbs/kms-credential/aws/credential.json`。
该位置可以通过 `AWS_IN_GUEST_KEY_PATH` 环境变量覆盖（该目录内的文件名始终为 `credential.json`）。

推荐通过该文件的 CDH 凭据接口来预置：向 CDH 配置中添加一个 `[[credentials]]` 条目，这样该文件会在 CDH 启动时从 KBS 获取（受证明门控）。将上面展示的 JSON 凭据文档作为 KBS 资源存储，然后引用它：

```toml
[[credentials]]
path = "/run/confidential-containers/cdh/kbs/kms-credential/aws/credential.json"
resource_uri = "kbs:///default/aws/credential"
```

`path` 必须位于 `/run/confidential-containers/cdh/kbs` 之下，并且必须与该驱动读取的目录相匹配（上面的默认值，或 `AWS_IN_GUEST_KEY_PATH` 指向的位置）。

> [!IMPORTANT]
> 静态 IAM 密钥不会自动轮换；建议将其权限严格收紧（一个专用的 IAM 主体，只允许对特定密钥执行 `kms:Decrypt` 和/或对特定密钥执行 `secretsmanager:GetSecretValue`），并在带外进行轮换。

## 行为

`AwsKmsClient` 实现了 `Encrypter`、`Decrypter`、`Getter` 和 `Setter`。
`Encrypter`/`Setter` 用于用户侧（密封/预置），而 `Decrypter`/`Getter` 用于 guest 内部（解封）。

客户端直接由区域和静态凭据构建；它**不**执行环境化的 AWS 凭据发现（不扫描环境变量/实例元数据），从而将 guest 内部的攻击面保持在最小。

## 密封密钥

### 信封（Envelope）

假设我们在一台能够访问 AWS、且所用 IAM 主体被允许对目标密钥执行 `kms:Encrypt` 的机器上。

准备：
- `kms-key-id.txt`：KMS 密钥 ID/ARN/别名，例如 `alias/my-coco-key`
- `aws-region.txt`：例如 `us-east-1`
- `aws-credential.json`：上面展示的凭据文件
- `plaintext`：内容将被密封的文件

一个预构建的 `secret` CLI（捆绑了所有 KMS 提供方）可从 [GitHub releases](https://github.com/confidential-containers/guest-components/releases) 获取；使用它可以跳过下面从源码构建的步骤。

```bash
KEY_ID=$(cat kms-key-id.txt)
REGION=$(cat aws-region.txt)
CREDENTIAL_FILE_PATH=$(pwd)/aws-credential.json

git clone https://github.com/confidential-containers/guest-components.git && cd guest-components

cargo build -p confidential-data-hub --bin secret --features aws

target/debug/secret seal \
    --signing-kid kbs://signing/key/uri --signing-jwk-path ./path/to/jwk \
    envelope --key-id "$KEY_ID" --file-path ../plaintext \
    aws \
    --region "$REGION" \
    --credential-file-path "$CREDENTIAL_FILE_PATH" \
    > sealed_secret.json
```

生成的 `sealed_secret.json` 如下所示：

```json
{
    "version": "0.1.0",
    "type": "envelope",
    "key_id": "alias/my-coco-key",
    "encrypted_key": "AQIDAH...",
    "encrypted_data": "QzWk...",
    "wrap_type": "A256GCM",
    "iv": "T32...",
    "provider": "aws",
    "provider_settings": {
        "region": "us-east-1"
    },
    "annotations": {}
}
```

### Vault

Vault 密钥只是一个指针；其值必须另行预置到 AWS Secrets Manager（例如 `aws secretsmanager create-secret ...`）。

```bash
cargo run -p confidential-data-hub --bin secret --features aws -- seal \
    --signing-kid kbs://signing/key/uri --signing-jwk-path ./path/to/jwk \
    vault \
    --resource-uri my/secret/name \
    --provider aws \
    --provider-settings '{"region":"us-east-1"}'
```

## 解封（Unsealing）

解封发生在 guest 内部、经由 CDH 进行，但也可以用 CLI 来演练：将 `--key-path` 指向直接包含 `credential.json` 的目录（这会设置 `AWS_IN_GUEST_KEY_PATH`，驱动读取 `$AWS_IN_GUEST_KEY_PATH/credential.json`）：

```bash
target/debug/secret unseal \
    --file-path sealed_secret.json \
    --key-path /path/to/dir/containing/credential.json
```
