# Simple Signing（简单签名）

Simple Signing 是 CC 支持的第一种签名方案。参见 [CCv1 镜像安全设计](../../../../../../../image-rs/docs/ccv1_image_security_design.md#image-signing)。

## 策略格式

Simple Signing 是基于容器的策略配置文件来验证的。

Simple Signing 的一个策略要求（Policy Requirement）应当如下：

```json
{
    "type": "signedBy",
    "keyType": "<KEY-TYPE>",
    "keyData": "<PUBKEY-DATA-IN-BASE64>",
    "keyPath": "<PATH-TO-THE-PUBKEY>",
    "signedIdentity": <JSON-OBJECT>,
}
```

这里，
* `type` 字段必须为 `signedBy`，表明该策略要求是面向 Simple Signing 的。
* `keyType` 字段表示公钥的类型。当前只支持 `GPGKeys`。
* `keyData` 字段包含以 base64 编码的公钥内容。
* `keyPath` 字段指向公钥的路径。并且它**必须**为 `"/run/image-security/simple_signing/pubkey.gpg"`。
* `signedIdentity` 包含一个 JSON 对象，详见 [signedIdentity](https://github.com/containers/image/blob/main/docs/containers-policy.json.5.md#signedby)。

**警告**：必须指定 `keyData` 或 `keyPath` 之一，且不能两者都指定。

## 工作流程

让我们在此走一遍验证逻辑。

验证一个签名所需的两样东西是：`signature`（签名）和 `public key`（公钥）。

* `public key` 由策略要求给出，既可以是数据，也可以是路径。
* `signature` 的存储位置（本地路径或远程 url）记录在 `Sigstore Config File`（Sigstore 配置文件）中，因此我们首先需要创建一个目录来保存 `Sigstore Config File`，然后需要获取 `Sigstore Config File`。
* 拿到 `signature` 后，我们就可以进行验证了。

让我们看看代码在这里做了什么：

1. `init()` 会检查并创建目录
* Sigstore 目录：`/run/image-security/simple_signing/sigstore_config`

2. 一个镜像相关签名的存储位置定义在 `Sigstore Configfile` 中。`Sigstore Configfile` 的 uri 将定义在 `ImageClient.config.file_paths.sigstore_config` 中。将会获取该 `Sigstore Configfile`。

3. 然后访问 `Sigstore Configfile`，收集与镜像相关的签名，并进行验证。

## KBS ResourceDescription

要验证由 simple signing 签名的签名，必须有一个 sigstore config 文件和一个 gpg 公钥。

虽然两者的路径都在策略文件中给出，但当宿主（host）启动时，这两个文件是缺失的。因此我们需要从 kbs 收集它们。

以下是两个 KBS Resource Description（资源描述）：
|资源描述| KBS 的预期响应 |
|---|---|
|`Sigstore Config`|Sigstore 配置|
|`GPG Keyring`| 用于验证签名的 GPG 公钥环|

更多信息请参考 [get-resource-service](../../../../../../../image-rs/docs/ccv1_image_security_design.md#get-resource-service)。
