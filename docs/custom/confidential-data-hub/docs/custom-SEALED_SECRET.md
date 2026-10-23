# 密封密钥（Sealed Secrets）

## 简介

在机密容器中，密钥可以通过密封（sealing）来保护。
密封密钥（sealed secret）是一种封装机密数据的方式，使得这些数据只能在机密沙箱（enclave）内，结合一次证明（attestation）才能被访问。

机密数据中枢（CDH）提供了一个 API，用于在机密 guest 内部解封密钥。

你可以使用 secret cli 工具来生成一个密封密钥。

### 预构建二进制（推荐）

拉取适用于 ARM 或 x86 的最新发布版本 secret cli。

```bash
oras pull ghcr.io/confidential-containers/guest-components/secret-cli:latest
chmod +x secret
./secret --help
```

### 从源码构建

或者，自己构建：

```bash
cargo run -p confidential-data-hub --bin secret
```

## Kubernetes 密钥

CoCo 的 [威胁模型](https://github.com/confidential-containers/confidential-containers/blob/main/trust_model_personas.md)
将 Kubernetes 控制平面（Control Plane）和宿主机（Host）组件排除在可信计算基（TCB）之外。
这意味着 CoCo 工作负载不应将敏感数据存储在传统的 [Kubernetes secrets](https://kubernetes.io/docs/concepts/configuration/secret/) 中。

相反，Kubernetes 密钥可以从密封密钥创建，从而让控制平面能够编排这些密钥，却无法读取它们。这一点详见下文。

Kata Agent 与 CDH 协同，可以将这些密钥透明地以环境变量的形式提供。

## 与资源 URI 的对比

机密容器也使用资源 URI（Resource URI）来引用密钥。与资源 URI 不同，密封密钥包含配置元数据，这将解封密钥与通用的证明配置部分解耦。

例如，一个密封密钥可以由 HSM 解包（unwrap），而所有其他密钥资源则从 KBS 获取。
密封密钥可用于创建复杂的环境，其中由不同参与方满足的多个密钥，都可以随工作负载一同传输。

## 格式

密封密钥主要有两种类型。

### 信封（Envelope）

这类密钥使用信封加密（envelope encryption）方案。使用一个加密密钥来加密明文的密钥值。被包装（wrapped）的密钥作为密封密钥的一部分进行存储。
要解封该密钥，需要使用一个 KMS/KBS 来解包被加密的密钥。

$$Sealed Secret := \{Enc_{Sealing key}(Encryption Key), Enc_{Encryption Key}(secret value)\}$$

KMS 类型密封密钥的格式如下：
```json
{
	"version": "0.1.0",
	"type": "envelope",
	"provider": "xxx",
	"key_id": "xxx",
	"encrypted_key": "ab27dc=",
	"encrypted_data": "xxx",
	"wrap_type": "A256GCM",
	"iv": "xxx",
	"provider_settings": {
		...
	},
	"annotations": {
		...
	}
}
```
其中：
- `version`：**必需**。指示密封密钥的格式版本。当前为 `0.1.0`。
- `type`：**必需**。必须为 `envelope`，表示这是一个信封类型的密封密钥。
- `provider`：**必需**。指示**密封密钥**的提供方。该字段决定如何使用 `annotations` 字段和 `key_id` 字段来解密 `encrypted_key`。
- `key_id`：**必需**。用于唯一区分用于加密**加密密钥**的**密封密钥**，该密钥始终被提供方驱动使用。
- `encrypted_key`：**必需**。由 `provider` 加密的**加密密钥**。Base64 编码。
- `encrypted_data`：**必需**。由 `encrypted_key` 加密的**密钥值**。Base64 编码。
- `wrap_type`：**必需**。用于**加密密钥**加密**密钥值**的算法。`A256GCM`（AES256-GCM）优先。
- `iv`：**必需**。**加密密钥**加密**密钥值**过程中使用的初始向量（Initial Vector）。Base64 编码。
- `provider_settings`：**必需**。一个键值映射。用于创建 KMS 客户端的提供方特定信息。
- `annotations`：**可选**。一个键值映射。提供方驱动用于把 `encrypted_key` 解密为**加密密钥**明文的提供方特定信息。

### Vault

Vault 密钥本质上只是一个指向存储在其他地方（KMS 或 KBS 中）的密钥的指针。
要满足一个 vault 密钥，CDH 会从密钥提供方自行获取该密钥。

创建 vault 密钥不需要任何加密。
只需创建下面的元数据，并将你的密钥预置到提供方：
```json
{
	"version" : "0.1.0",
	"type": "vault",
	"provider": "xxx",
	"name": "xxx",
	"provider_settings": {
		...
	},
	"annotations": {
		...
	}
}
```
其中：
- `version`：**必需**。指示密封密钥的格式版本。当前为 `0.1.0`。
- `type`：**必需**。必须为 `vault`，表示这是一个 Vault 类型的密封密钥。
- `provider`：**必需**。指示**密钥值**的提供方。该字段决定如何使用 `annotations` 字段和 `name` 字段来获取**密钥值**的明文。
- `name`：**必需**。用于唯一区分**密钥值**，始终被提供方驱动使用。
- `provider_settings`：**必需**。一个键值映射。用于创建 vault 客户端的提供方特定信息。
- `annotations`：**可选**。一个键值映射。提供方驱动用于获取**密钥值**明文的 vault 特定信息。

## 密封密钥的完整性保护

使用广泛采用的 [JWS](https://datatracker.ietf.org/doc/html/rfc7515) 来保护密封密钥的完整性。
密封密钥是 JWS 的载荷（payload）。一个已签名的密封密钥如下：
```
BASE64URL(UTF8(JWS Protected Header)) || '.'
    || BASE64URL(JWS Payload) || '.'
    || BASE64URL(JWS Signature)
```

我们可以利用 ["kid"](https://datatracker.ietf.org/doc/html/rfc7515#section-4.1.4)
字段来指定用于验证此签名的公钥。

必须提供一个由 `kid` 标识的公钥来验证该密钥。
该公钥既可以作为 CDH 凭据预置，也可以直接从 Trustee 获取。在后一种情况下，`kid` 应当是一个资源 URI。

## 在 CoCo 中使用

创建密封密钥最简单的方式是使用 secret CLI 工具。

你可以用以下命令创建一个 vault 密钥：

```bash
cargo run -p confidential-data-hub --bin secret seal \
    --signing-kid kbs://signing/key/uri --signing-jwk-path ./path/to/jwk \
    vault \
    --resource-uri kbs://secret/key/uri --provider kbs
```

这将创建一个指向 Trustee 中资源 `secret/key/uri` 的密封密钥。
该密钥将由存储在 Trustee 中的公钥进行校验。
公钥/私钥对应当是一个带有 P256 EC 密钥的 JWK。

你可以用 `keygen` 子命令生成密钥对：

```bash
cargo run -p confidential-data-hub --bin secret keygen --kid my-signing-key --output-dir ./keys
```

这会写入两个文件：`my-signing-key-private.json`（用于签名）和 `my-signing-key-public.json`（预置到 Trustee）。

只需将公钥组件预置到 Trustee。

### 创建一个 Kubernetes 密钥

```bash
kubectl create secret generic sealed-secret --from-literal='secret=<sealed-secret>'
```

在工作负载中使用该密钥：
```yaml
...
    env:
    - name: PROTECTED_SECRET
      valueFrom:
        secretKeyRef:
          name: sealed-secret
          key: secret
```

你的密钥将被提供到 `PROTECTED_SECRET` 环境变量中。

## 支持的提供方

| 提供方名称      | README                                                      			| 维护者                |
| ------------------ | -------------------------------------------------------------------- | ------------------------- |
| aliyun       	     |  [aliyun](../../../../confidential-data-hub/docs/kms-providers/alibaba.md)                               	| 阿里云                   |
| aws       	     |  [aws](../../../../confidential-data-hub/docs/kms-providers/aws.md)                                     	| CoCo                      |
| kbs                |                                                                          | CoCo                  |
