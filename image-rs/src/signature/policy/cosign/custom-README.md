# Cosign

Cosign 是 Container Signing, Verification and Storage in an OCI registry（OCI 注册表中的容器签名、验证与存储）的缩写。它旨在让签名成为“看不见的基础设施”。参见 [Cosign](https://github.com/sigstore/cosign/blob/main/README.md)。

## 策略格式

Cosign 是基于容器的策略配置文件来验证的。

Cosign 的一个策略要求（Policy Requirement）应当如下：

```json
{
    "type": "sigstoreSigned",
    "keyData": "<PUBKEY-DATA-IN-BASE64>",
    "keyPath": "<URL-TO-THE-PUBKEY>",
    "signedIdentity": <JSON-OBJECT>,
}
```

这里，
* `type` 字段必须为 `sigstoreSigned`，表明该镜像由 `cosign` 签名（`cosign` 是 [`sigstore`](https://www.sigstore.dev) 的一个镜像签名子项目）。
* `keyData` 字段包含以 base64 编码的公钥内容。
* `keyPath` 字段指向公钥的 URL。
* `signedIdentity` 包含一个 JSON 对象，详见 [signedIdentity](https://github.com/containers/image/blob/main/docs/containers-policy.json.5.md#sigstoreSigned)。由于 Cosign 的机制，只有 `matchRepository` 和 `exactRepository` 可被用于接受镜像。

> **警告**：必须指定 `keyData` 或 `keyPath` 之一，但不能同时指定两者。

## 实现

我们封装了 sigstore 的 [Rust 实现](https://github.com/sigstore/sigstore-rs)，以适配我们为签名方案定义的接口。

## 工作流程

让我们快速了解 Cosign 的工作原理。例如，有一个待签名的镜像，名为 `example.com/alpine:test`。作为一个引用，它的
* `registry`：`example.com`，即一个测试注册表。
* `repository`：`alpine`
* `tag`：`test`

### 签名

签名分为三个步骤：
- 对 `Payload` 签名
- 将 `Payload` 与签名打包成一个镜像 bundle
- 将镜像 bundle 上传到注册表

#### 签名生成

当我们对该镜像签名时，使用 cosign 生成的密钥对。数字签名算法为 ECDSA-P256。被签名的对象，即 `Payload`，是 [simple signing payload](https://github.com/sigstore/cosign/blob/main/specs/SIGNATURE_SPEC.md#simple-signing)。被签名镜像的引用会被包含在 `Payload` 中。不过，只包含 `registry` 和 `repository`，而**不会**包含 `tag`。在此示例中，它类似如下：

```json
{
    "critical": {
        "identity": {
            "docker-reference": "example.com/alpine"
        },
        "image": {
            "docker-manifest-digest": "sha256:9b2a28eb47540823042a2ba401386845089bb7b62a9637d55816132c4c3c36eb"
        },
        "type": "cosign container image signature"
    },
    "optional": null
}
```

因此，在 Cosign 中，只有 `matchRepository` 和 `exactRepository` 可被用于接受镜像。

Cosign 是如何知道同一仓库中哪个镜像被签名的呢？答案是 `docker-manifest-digest`。每个拥有不同 `tag` 的镜像都有各自的 manifest。由于 `tag` 不同，manifest 的 sha256 digest 也不同。我们可以将 `docker-manifest-digest` 视同于 `tag`。

现在，如果客户端拿到了签名和 `Payload`，他们可以验证签名，然后检查 `Payload` 中的 `"docker-reference"` 是否与待使用镜像相匹配。

#### 签名存储

现在，让我们把签名和 `Payload` 存储到仓库中。

将会有一个新的条目被存储到仓库中。该新条目包含签名和 `Payload`。

根据 [OCI Distribution Spec](https://github.com/opencontainers/distribution-spec/blob/main/spec.md)，一个镜像在镜像注册表中的存储方式如下：
* 必须有一个 `manifest` 文件来展示组成一个容器镜像的各个组件。
* 每个组件（例如文件系统层）以 sha256 寻址的 blob 形式存储。

一个 manifest 的格式可能如下：
```json
{
   "schemaVersion": 2,
   "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
   "config": {
      "mediaType": "application/vnd.docker.container.image.v1+json",
      "size": 1472,
      "digest": "sha256:d7d3d98c851ff3a95dbcb70ce09d186c9aaf7e25d48d55c0f99aae360aecfd53"
   },
   "layers": [
      {
         "mediaType": "application/vnd.docker.image.rootfs.diff.tar.gzip",
         "size": 2798806,
         "digest": "sha256:530afca65e2ea04227630ae746e0c85b2bd1a179379cbf2b6501b49c4cab2ccc"
      }
   ]
}
```

这里的 layers 是镜像的组件，可以通过 blob 中的 `digest` 字段寻址。

manifest 可以通过镜像的引用寻址。

为了避免为签名额外占用存储空间，Cosign 巧妙地将签名和 `Payload` 存储在镜像所在的同一个注册表中。

#### “image” 格式

如示例所示，当 `example.com/alpine:latest` 的签名被存储时，将会有一个新的“image”被存储，该“image”包含签名和已签名的 `Payload`。这里的“image”并非真正的镜像，而是遵循 [OCI Distribution Spec](https://github.com/opencontainers/distribution-spec/blob/main/spec.md) 的一些文件。

该“image”的 manifest 会包含以 base64 编码的签名，并有一个指向 `Payload` 的指针。可能类似如下：

```json
{
    "schemaVersion": 2,
    "mediaType": "application/vnd.oci.image.manifest.v1+json",
    "config": {
        "mediaType": "application/vnd.oci.image.config.v1+json",
        "size": 233,
        "digest": "sha256:eca5f5f99822d62181a93ebe1df31db7eeebdf47c47b0a5515c26adc3abf3226"
    },
    "layers": [
        {
            "mediaType": "application/vnd.dev.cosign.simplesigning.v1+json",
            "size": 238,
            "digest": "sha256:a252c3b3b26bad13a82cb65b252d5f409ab72d7db433ceb7242ebdbcf0fd9889",
            "annotations": {
                "dev.cosignproject.cosign/signature": "MEUCIQDVshyS+xIpdq5YkAAvrACS5wzg3Zsk4n4UTwcgjiwsnwIgfhy+SeAocHKQVFjX4HgljoAOu27g/p4E2x8izHicbeY="
            }
        }
    ]
}
```

这里，`"annotations"` 中的 `"dev.cosignproject.cosign/signature"` 是使用 ECDSA P256 算法对该镜像进行的 base64 编码签名。

blob 中的层 `sha256:a252c3b3b26bad13a82cb65b252d5f409ab72d7db433ceb7242ebdbcf0fd9889` 即为 `Payload`。它正是前面提到的那个示例 `Payload`。

```json
{
    "critical": {
        "identity": {
            "docker-reference": "example.com/alpine"
        },
        "image": {
            "docker-manifest-digest": "sha256:9b2a28eb47540823042a2ba401386845089bb7b62a9637d55816132c4c3c36eb"
        },
        "type": "cosign container image signature"
    },
    "optional": null
}
```

#### 将“image”存储到注册表

让我们看看“image”是如何存储的：
- 待签名的镜像是 `example.com/alpine:latest`
- 将镜像引用的 tag 解析为 digest `sha256:9b2a28eb47540823042a2ba401386845089bb7b62a9637d55816132c4c3c36eb`。这里的 sha256 digest 与 `tag` 功能相同，二者都可用于定位特定的镜像。这个 sha256 digest 仅为示例，并非真实值。
- 将 digest 编码为一个新的名称 `sha256-9b2a28eb47540823042a2ba401386845089bb7b62a9637d55816132c4c3c36eb.sig`。规则是
    - 将 `:` 字符替换为 `-`
    - 附加 `.sig` 后缀
- 将“image”存储为 `example.com/alpine:sha256-9b2a28eb47540823042a2ba401386845089bb7b62a9637d55816132c4c3c36eb.sig`

### 验证

当一个 `type` 设为 `sigstoreSigned` 的策略要求被处理时，将根据 `keyPath` 或 `keyData` 字段读取相应的公钥。

然后，按照以下步骤验证一个 Cosign 签名的镜像：
- 下载镜像的 manifest 和 digest。
- 根据 digest 计算签名“image”的引用。
- 下载签名“image”。
- 从下载的签名“image”中提取签名与 `Payload`。
- 以密码学方式验证签名与 `Payload`。
- 检查其中 `Payload` 的引用与策略中 `signedIdentity` 规则的引用是否一致。

> **警告**：对于 Cosign，在 `signedIdentity` 中只能使用 `matchRepository` 和 `exactRepository`。
