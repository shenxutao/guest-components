# 阿里云 KMS 驱动

## 规范

### 常量与布局

以下是阿里云 KMS 的常量。

| 名称               | 值       |
| ------------------ | ----------- |
| `provider`       	 | `aliyun`       |

[密封密钥](../SEALED_SECRET.md#format) 中定义的 `provider_settings` 和 `annotations` 如下：

#### annotations

##### 加密/解密

| 名称               | 用途                                                                |
| ------------------ | -------------------------------------------------------------------- |
| `iv`       	     | 加密/解密操作中使用的初始向量（initialization vector） |

##### get_secret

| 名称               | 用途                                                                |
| ------------------ | -------------------------------------------------------------------- |
| `version_stage`    | （可选）如果指定了该参数，KMS 会返回被标记为指定状态的版本对应的凭据值。 |
| `version_id`       | （可选）如果指定了该参数，KMS 会返回指定版本号对应的凭据值。 |

#### provider_settings

`client_type` 用于指定访问 KMS 的方式。对于加密/解密，只有 'client_key' 可用。而对于 get_secret，'client_key' 和 'ecs_ram_role' 都可用。

如果 `client_type` 设为 'client_key'，provider_settings 应如下：

| 名称               | 用途                                                                |
| ------------------ | -------------------------------------------------------------------- |
| `client_type`      | 用于指定访问 KMS 的方式。（此处设为 'client_key'） |
| `client_key_id`    | 用于访问 KMS 实例的客户端密钥（client key）ID             |
| `kms_instance_id`  | 要连接的 KMS 实例 ID                                  |

如果 `client_type` 设为 'ecs_ram_role'，provider_settings 应如下：

| 名称               | 用途                                                                |
| ------------------ | -------------------------------------------------------------------- |
| `client_type`      | 用于指定访问 KMS 的方式。（此处设为 'ecs_ram_role'） |

如果 `client_type` 设为 'sts_token'，provider_settings 应如下：

| 名称               | 用途                                                                |
| ------------------ | -------------------------------------------------------------------- |
| `client_type`      | 用于指定访问 KMS 的方式。（此处设为 'sts_token'） |
| `token_path`       | Pod 内部 STS Token 的路径。STS token 的格式为 `AK:SK:STS`|
| `region_id`        | KMS 实例的区域 ID                                               |

### 凭据文件

要以 `client_type` 设为 'client_key' 的方式连接 KMS 实例，需要一个客户端密钥（client key）。一个客户端密钥实际上是一个 [内部带有加密私钥的 json](../../kms/src/plugins/aliyun/client/client_key_client/example_credential/clientKey_KAAP.f4c8____.json) 文件。客户端密钥的名称总是从客户端密钥 ID 派生而来。假设客户端密钥 ID 为 `xxx`，那么客户端密钥文件名为 `clientKey_xxx.json`。用于加密私钥的密钥是从同样保存在 [一个文件](../../kms/src/plugins/aliyun/client/client_key_client/example_credential/password_KAAP.f4c8____.json) 中的密码派生而来。假设客户端密钥 ID 为 `xxx`，那么密码文件名为 `password_xxx.json`。
此外，还需要 [KMS 服务端证书](../../kms/src/plugins/aliyun/client/client_key_client/example_credential/PrivateKmsCA_kst-shh64702cf2jvc_____.pem)。假设 KMS 实例 ID 为 `xxx`，那么 KMS 服务端证书文件名为 `PrivateKmsCA_xxx.pem`。

更多细节请参见 [阿里云开发者文档](https://www.alibabacloud.com/help/en/key-management-service/latest/api-overview)。

要以 `client_type` 设为 'ecs_ram_role' 的方式连接 KMS 实例，需要一个 [ecsRamRole.json](../../kms/src/plugins/aliyun/client/ecs_ram_role_client/example_credential/ecsRamRole.json) 文件。
在该 json 文件中，设置了 `ecs_ram_role_name` 和 `region_id` 以便访问专用 KMS（Dedicated KMS）。
其中，`ecs_ram_role_name` 指 CDH 所运行的 VPC 网络中 ECS 实例的 RAM 角色。可以在阿里云控制台上设置。
而 `region_id` 指专用 KMS 的区域 ID，更多细节可参考 [此处](https://www.alibabacloud.com/help/en/kms/product-overview/supported-regions)。

关于通过 EcsRamRole 访问的更多细节，可参见 [以安全方式从 ECS 实例访问 KMS](https://www.alibabacloud.com/help/en/kms/use-cases/access-kms-from-an-ecs-instance-in-a-secure-manner)。

## 行为

客户端 `AliyunKmsClient` 支持 `Encrypter`、`Decrypter` 和 `Getter` API。在用户侧，凭据文件可以直接由用户提供。

在 TEE 内部，凭据文件应当放置在 `/run/confidential-containers/cdh/kbs/kms-credential/aliyun` 目录下。

## 密封密钥

本节介绍如何使用 `aliyun` KMS 来密封一个密钥。

假设我们登录在一台能够连接 KMS 实例的 ECS 机器上。

准备以下文件：
- `kms-key-id.txt`：内容为对称密钥的密钥 ID。示例：
```
key-bjj...
```
- `kms-instance-id.txt`：内容为 KMS 的实例 ID。示例：
```
kst-bjj652...
```
- `ClientKeyPassword.json`：内容为 ClientKey 的密码。示例：
```json
1e367c6b24...
```
- `ClientKeyContent.json`：内容为 ClientKeyContent。示例：
```json
{
  "KeyId": "KAAP.e9692...",
  "PrivateKeyData": "MIIJ2wIBAzCC..."
}
```
- `ca.pem`：KMS 实例的公钥证书。示例：
```
-----BEGIN CERTIFICATE-----
MIIDuzCCAqOgAwIBAgIJALTKwWAjvbMiMA0GCSqGSIb3DQEBCwUAMHQxCzAJBgNV
...
nc8BTncWI0KGWIzTQasuSEye50R6gc9wZCGIElmhWcu3NYk=
-----END CERTIFICATE-----
```
- `plaintext`：内容将被密封的文件。

一个预构建的 `secret` CLI（捆绑了所有 KMS 提供方）作为 OCI 制品发布在 `ghcr.io`（参见 [SEALED_SECRET.md](../SEALED_SECRET.md)）；使用 ORAS 拉取它，可以跳过下面从源码构建的步骤。

然后，我们执行：
```bash
# 定义参数
KEY_ID=$(cat kms-key-id.txt)
KMS_INSTANCE_ID=$(cat kms-instance-id.txt)
CLIENT_KEY_PASSWORD_FILE_PATH=$(pwd)/ClientKeyPassword.json
CERT_PATH=$(pwd)/ca.pem
CLIENT_KEY_FILE_PATH=$(pwd)/ClientKeyContent.json

git clone https://github.com/confidential-containers/guest-components.git && cd guest-components

cargo build --bin secret --release --features "aliyun"

target/release/secret seal --file-path ../plaintext \
    envelope --key-id $KEY_ID ali \
    --password-file-path $CLIENT_KEY_PASSWORD_FILE_PATH \
    --cert-path $CERT_PATH \
    --kms-instance-id $KMS_INSTANCE_ID \
    --client-key-file-path $CLIENT_KEY_FILE_PATH \
    > sealed_secret.json
```

最终密封密钥将输出到 `sealed_secret.json`。

```bash
cat sealed_secret.json | python -m json.tool
```

输出：
```json
{
    "version": "0.1.0",
    "type": "envelope",
    "key_id": "key-bj...",
    "encrypted_key": "XTXa...",
    "encrypted_data": "7vfE...",
    "wrap_type": "A256GCM",
    "iv": "Q/g...",
    "provider": "aliyun",
    "provider_settings": {
        "client_type": "client_key",
        "client_key_id": "KAAP.e9...",
        "kms_instance_id": "kst-bj..."
    },
    "annotations": {
        "iv": "s2O..."
    }
}
```
