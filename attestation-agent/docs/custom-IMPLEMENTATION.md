# 实现（IMPLEMENTATION）

## 术语定义

### CC

CNCF 机密容器（Confidential Containers），机密数据中枢（CDH）的上级项目。

### KBS

密钥代理服务（Key Broker Service）。

### KBC

密钥代理客户端（Key Broker Client），KBS 的客户端。

### KBS 协议

一类 KBS 用于与其 KBC 通信的协议，例如 EAA、GOP、ISECL 等。

### KBS 实例

KBS 类的一个具体实例，在运行时与 KBC 实例进行通信。

### KBC 模块

一类特定 KBS 协议的 KBC 实现。在 CDH 中，这体现为 [`confidential-data-hub/kms/src/plugins/kbs`](../../confidential-data-hub/kms/src/plugins/kbs) 中的一个插件。

### KBC 实例

CDH 运行时中存在的 KBC 的实例化对象。它用于实际处理 UnWrapKey/获取资源的请求。

## KeyProvider 协议

在 CC 框架下，这是 ocicrypt 调用方与密钥提供方服务（CDH）之间的通信协议。由于从 ocicrypt 的视角来看 CDH 是作为一个密钥提供方服务存在的，因此该协议符合标准密钥提供方协议的格式。为了更好地支持不同于标准密钥提供方的功能，我们进一步规范了标准密钥提供方协议中的 DC 参数。其内容及字段含义如下：

> [!NOTE]
> 历史上，该协议由 `attestation-agent` 二进制直接实现。该功能此后已迁移到 `confidential-data-hub`，后者仍然以遗留的 ocicrypt 提供方名称 `attestation-agent` 进行自标识，以保持向后兼容的注解处理（参见 [`ocicrypt_config.rs`](../../confidential-data-hub/hub/src/config/ocicrypt_config.rs)）。

### UnWrapKey API 请求

```
{
    "op":"keyunwrap",
    "keyunwrapparams":{
        "dc":{
            "Parameters":{
                "attestation-agent":[
                    "KBC_NAME::KBS_URI <base64encode>"
                ],
                "DecryptConfig":{"Parameters":{}}
            }
        }
    },
    "annotation": #layer-annotation,
}
```

`keyunwrappparams` 字段中的 `dc` 字段是“解密配置信息”（Decryption Configuration），其中的 `Parameters` 字段包含其主要内容。`Parameters` 的第一项是 ocicrypt 所调用的密钥提供方服务的名称（此处需要是 attestation-agent，以保持向后兼容）以及传递给目标服务的用户自定义参数（Base64 编码）。我们将该用户自定义参数定义为 ` "KBC_NAME::KBS_URI" `。该标准格式用于将 KBC 选择信息和相应的 KBS 访问信息传递给 CDH。关于这里的更多疑问，请参考下文的“将 KBC 名称和 KBS URI 传递给 CDH”章节。

`"annotation"` 字段是传递给 CDH 的主要内容。实际上，它是待解密容器镜像的层注解字段。该字段包含需要由 CDH 解密的载荷。关于层注解的更多信息，请参考下面的“容器镜像的加密与解密”和“层注解”两章。

### UnWrapKey API 响应

```
{
    "keyunwrapresults": {
        "optsdata": #decrypted-payload,
    }      
}
```

这是返回给 ocicrypt 的响应，其中 `"optsdata"` 字段包含由 CDH 解密后的层注解明文载荷。

### WrapKey API

CDH 仅作为密钥提供方提供解密路径的服务，因此不需要 wrapkey API。但是，为了保持密钥提供方协议的一致性，CDH 提供了一个空的 wrapkey API，并会在响应的 ` "optsdata"` 字段中返回 “UNIMPLEMENT”。

## 容器镜像的加密与解密

在镜像层加密期间，ocicrypt 会调用密钥提供方的 WrapKey() API。一个 KBS 实例可以实现该 API，用密钥加密密钥（KEK）对“私有层块加密选项”（简称 PLBCO）进行加密，并将加密后的 PLBCO 以及 KBS 特定参数打包进层注解中。（注：如何与 KBS 协作进行加密是可定制的，WrapKey() API 不一定要由 KBS 实现。）

在解密容器镜像层时，kata-agent（ocicrypt-rs）会请求 CDH 的 UnWrapKey API，将 KBC 名称、KBS URI 和层注解传递给 CDH，并期望 CDH 返回解密后的 PLBCO（包含 LEK）。

## 层注解

层注解的生产者是 KBS 实例，因此层注解的格式是 KBS 协议和实现特定的。（如果未使用 KBS 进行加密，层注解也应被设置为 KBS 协议特定的格式）

层注解的消费者是实现相应 KBS 协议的 KBC 实例，因为只有它才能解析 KBS 协议特定的注解格式。

关于生成后的 manifest 注解的可运行示例，请参见 [检视镜像](../coco_keyprovider/README.md#inspecting-the-image)。

## KBC 运行时

CDH 在编译时通过 cargo 特性启用一个或多个 KBC 插件（例如 `kbs` 启用 `cc_kbc`；`offline_fs_kbc` 始终内置构建）。在运行时，CDH 读取配置的（或从 `aa_kbc_params` 派生的）KBC 名称，并实例化匹配的插件一次；该实例随后会在 CDH 进程的整个生命周期内被复用以处理所有后续的 UnWrapKey/获取资源的请求。参见 [`confidential-data-hub/kms/src/plugins/kbs/mod.rs`](../../confidential-data-hub/kms/src/plugins/kbs/mod.rs) 了解当前的派发（dispatch）实现。

## 将 KBC 名称和 KBS URI 传递给 CDH

在当前实现中，KBC 名称和 KBS URI 由密钥提供方协议的实现者（例如 ocicrypt 和 ocicrypt-rs）传递。

### 当前不能通过层注解透传

这两条信息不应作为容器镜像的一部分放置在层注解中。主要有两方面原因：

1. **灵活性**：将 KBC 名称和 KBS URI 排除在镜像之外，意味着同一个加密镜像可以针对不同的 KBC/KBS 配置进行部署，而无需重新构建。
2. **安全性**：层注解是公开的明文数据。如果没有额外的加密保护，攻击者可以利用 KBS URI 发起拒绝服务（DoS）攻击，阻止租户启动任何基于该 KBS 的机密容器；如果没有额外的完整性保护，攻击者可以篡改内容，并在解密镜像层时引发潜在的安全问题。

> [!WARNING]
> 层注解应当保持独立于任何特定的 KBC。在当前 CoCo guest 技术栈中，镜像拉取和层解密由 CDH 处理，CDH 从 CDH 配置（或相关的 guest 参数）获取 KBC/KBS 配置，而不是从镜像层中获取。

### 由 ocicrypt 而非 kata-agent 传递

在 CDH 的实现中，KBC 名称和 KBS URI 是通过 ocicrypt 的密钥提供方协议传递的，而不是由 kata-agent 在 CDH 的启动阶段传递。

KBC 名称::KBS URI 通过密钥提供方协议中保留的用户自定义字段传递。UnWrapKey API 的请求应如下：

```
{
    "op":"keyunwrap",
    "keyunwrapparams":{
        "dc":{
            "Parameters":{
                "attestation-agent":[
                    "KBC_NAME::KBS_URI <base64encode>"
                ],
                "DecryptConfig":{"Parameters":{}}
            }
        }
    },
    "annotation": #kbs-protocol-specific,
}
```

当 CDH 在启动后收到第一个 unwrapkey 请求时，它会根据 KBC 名称选择正确 KBC（编译期选项）并实例化它。在后续请求中，如果 KBC 名称相同，CDH 总是使用同一个 KBC 实例来处理请求。

尽管你可能认为在 CDH 的启动阶段由 kata-agent 传递这些参数似乎更直接，但当前通过密钥提供方协议传递它们的方案可以统一 CDH 的参数接收接口，并使其架构更具可扩展性。此外，由于实例化一个 KBC 非常简单，该方案对性能的影响可以忽略不计。

## 其他

### KBC 解密流程

KBC 模块解析 ocicrypt-rs 传递过来的注解字段，获取密钥代理服务（KBS）的连接地址信息和 KEK 的 ID，然后与 KBS 通信以实际解密注解字段中的载荷（镜像加密密钥）。`cc_kbc` 实现了这一行为，在访问 KBS 之前使用 `attestation-agent` 获取一个 bearer token。`offline_fs_kbc` 实现了该流程的简化版本用于测试：它不进行证明，也不与 KBS 通信，而是直接从本地文件读取 KEK/资源。

### gRPC 与 ttRPC

与 gRPC 相比，ttRPC 具有更轻量的优势。CDH 作为 CoCo guest 技术栈客户端侧的一个常驻内存服务，可以使用轻量的 ttRPC 来节省更多资源。gRPC 和 ttRPC 都受支持，并可在编译时通过 `grpc`/`ttrpc` cargo 特性进行选择。
