# 镜像安全设计（CCv1）

## 背景

- [CC 安全方案解析 #1](https://github.com/confidential-containers/documentation/issues/18)
- [机密容器信任模型](https://github.com/confidential-containers/confidential-containers/blob/main/trust_model.md)
- [机密容器威胁模型](https://github.com/confidential-containers/confidential-containers/blob/main/threats_overview.md)

## 组件

- 镜像加密与签名工具，例如 [`skopeo`](https://github.com/containers/skopeo)
- [`image-rs`](../../../../image-rs)
- [`ocicrypt-rs`](../../../../ocicrypt-rs)
- [`attestation-agent`](../../../../attestation-agent)
- [`confidential-data-hub`](../../../../confidential-data-hub)
- [密钥代理服务（KBS）](https://github.com/confidential-containers/trustee)

# 受保护容器镜像的生产

所谓“受保护容器镜像”，是指由镜像所有者加密并签名的容器镜像。

**注意**：
- 加密过程必须先于签名过程进行，换句话说，当一个镜像被加密并签名时，被签名的对象实际上是加密后的容器镜像。
- 理想情况下，镜像的创建、加密和签名需要“原子化”地发生，且每一步紧接上一步进行。（否则，会存在一个很大的时间窗口，让他人有机会篡改镜像）

容器镜像的加密/解密和签名目前[仍在开发中](https://github.com/opencontainers/image-spec/pull/775)。
对于加密/解密，我们将依赖 [`ocicrypt`](https://github.com/containers/ocicrypt) 的 Rust 实现 [`ocicrypt-rs`](../../../../ocicrypt-rs)，它本身应当与 `ocicrypt` 兼容。
对于签名，我们将依赖标准的[镜像库](https://github.com/containers/image)或力求与其兼容。

对容器镜像进行加密和签名的总体概览如下：

![image-1](../../../../image-rs/docs/images/security-1.png)

在所有者侧，用于加密的密钥和用于签名的私钥可以是同一个密钥，这取决于所有者采用的密钥管理策略，这不是本文档的重点。

## 镜像加密

镜像加密基于层（layer）粒度：对于每一层，生成一个随机对称密钥并用于加密该层；该对称密钥本身通过所有者的密钥、经由[密钥提供方协议](https://github.com/containers/ocicrypt/blob/main/docs/keyprovider.md)进行加密（“包装”，wrap），被包装的密钥材料作为注解（annotation）记录在镜像 manifest 的该层上，并为该层的 `mediaType` 添加 `"+encrypted"` 后缀。

所有者可以使用任何自定义的镜像加密工具来实现这一过程
（例如集成了 [`ocicrypt`](https://github.com/containers/ocicrypt) 的 [`skopeo`](https://github.com/containers/skopeo)），只要它满足
[IMAGE_ENCRYPTION.md](../../../../attestation-agent/docs/IMAGE_ENCRYPTION.md)（注解包格式、层注解键）和 [IMPLEMENTATION.md](../../../../attestation-agent/docs/IMPLEMENTATION.md)（KeyProvider 协议）中描述的实现规范。关于生成后的 manifest 注解的可运行示例，请参见[检视镜像](../../../../attestation-agent/coco_keyprovider/README.md#inspecting-the-image)。

## 镜像签名

业界存在多种镜像签名与验证协议/方案。

签名方案由镜像安全[策略文件](../../../../image-rs/docs/ccv1_image_security_design.md#policy)的 `type` 字段指定，该策略文件被分发给 image-rs。

在验证签名时，image-rs 可以根据该字段选择合适的签名验证方案。

我们从支持[Red Hat simple signing 格式](https://www.redhat.com/en/blog/container-image-signing)开始。这是一个简单直接的签名系统，它使用 OpenPGP（[RFC 4880](https://datatracker.ietf.org/doc/html/rfc4880#section-5.4)）的密钥和一个简单的签名[payload 格式](https://github.com/containers/image/blob/main/docs/containers-signature.5.md)。

未来，机密容器将逐步支持多种镜像签名方案。这些方案的区别如下：

1. 签名 payload 格式。
2. 签名算法。
3. 签名的存储与分发。

我们在签名验证时对上述三者做模块化设计，并根据策略配置选择合适的签名验证方法。

## 镜像分发

加密和签名完成后，我们得到两个产物：加密后的容器镜像本身，以及签名。两者的分发方案如下：

- 容器镜像：
  - 当使用受保护的启动镜像（protected boot image）方案时，容器镜像可以直接放置在启动镜像的 rootfs 中，或推送至远程注册表；
  - 当使用非受保护的启动镜像方案时，所有者必须将容器镜像推送至远程注册表。
- 签名：
  - 如果镜像被推送至远程注册表：根据所使用的不同签名方案存储在不同位置。
  - 如果镜像被放置在启动镜像 rootfs 中：将其存储在指定的 `sigstore`（启动镜像 rootfs 中的一个定制化本地目录）。

# 受保护容器镜像的部署

在机密容器设计中，安全功能将在 `image-rs` 拉取容器镜像时执行，包括检查注册表允许列表、验证容器镜像签名（如果需要），以及解密容器镜像层。步骤如下：

1. 从 `policy.json` 文件中获取与镜像匹配的策略集。
   - 如果是拒绝（reject），将直接终止拉取动作；
   - 如果是无条件接受（unconditional acceptance），跳过第二和第三步；
   - 如果是需要签名验证，则进入后续步骤。
2. （如果策略需要签名验证）获取容器镜像的签名。
3. （如果策略需要签名验证）根据策略的配置验证容器镜像的签名。
4. 逐层拉取容器镜像层。如果某加密容器镜像层是加密的，则解密它。

镜像拉取完成后，后续的部署过程与普通容器镜像一致。

## 策略（Policy）

这里的策略文件来自 Red Hat simple signing 实现中引入的签名验证[策略配置文件](https://github.com/containers/image/blob/main/docs/containers-policy.json.5.md)，该实现见于 [containers/image](https://github.com/containers/image) 项目。该策略文件不仅能用于 Red Hat simple signing，在机密容器设计中，我们将继续对策略文件的内容进行定制与扩展，使其成为兼容不同签名方案的通用签名验证配置文件。

其主要功能如下：

- 以“传输范围（transport-scope）”粒度声明容器镜像的允许列表
- 声明用于验证各种镜像签名的签名方案
- （可选）指定在验证镜像签名时应当使用的公钥（路径、数据、ID 等）

目前，机密容器中支持以下两种传输（transport）类型：

- `docker`：用于匹配实现了 docker registry HTTP API V2 协议的容器注册表中的镜像。
- `dir`：用于匹配位于本地文件系统中的镜像。

一份安全且合理的 `policy.json` 文件可能如下所示：

```json
{
    "default": [{"type": "reject"}],
    "transports": {
        "docker": {
            "docker.io/my_private_registry": [
                {
                    "type": "signedBy",
                    "keyType": "GPGKeys",
                    "keyData": "<public Key>",
                }
            ],
            "registry.access.redhat.com": [
                {
                    "type": "signedBy",
                    "keyType": "GPGKeys",
                    "keyPath": "/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release",
                }
            ],
        },
        "dir": {
            "": [{"type": "insecureAcceptAnything"}]
        }
    }
}
```

在拉取容器镜像层之前，根据[容器镜像引用](https://github.com/containers/image/blob/main/docker/reference/reference.go)，按以下顺序匹配策略：

- 匹配 `transport` 下各成员（member）内的单个特定范围（scope），例如：
  - 对于来自实现了 Docker Registry HTTP API V2 协议的容器注册表的镜像，匹配 `docker` 成员下的每个 scope；
  - 对于来自本地文件系统的镜像，匹配 `dir` 成员下的每个 scope；
- 匹配 transport 成员下的默认范围（default scope），例如 transport `dir` 的 `""` 范围。
- 匹配全局默认范围，例如上述示例中第一行的 `default` 字段。

匹配成功后，执行对应范围下的策略集，详见[策略要求](https://github.com/containers/image/blob/main/docs/containers-policy.json.5.md#policy-requirements)。

为了灵活支持不同的签名方案，我们会像[策略要求](https://github.com/containers/image/blob/main/docs/containers-policy.json.5.md#policy-requirements)那样，检查 `type` 字段是否为签名方案。

目前，涉及签名验证的 `type` 取值应为：

- `signedBy`：Red Hat simple signing 方案。

未来将支持更多签名方案，该字段将拥有更多允许的取值。

以上述策略文件为例，其含义如下：

1. 对于来自本地文件系统的镜像，无论是否存在有效签名，都允许拉取和运行。
2. 对于来自 `docker.io/my_private_registry` 注册表的镜像，必须至少存在一个可以用 `keyData` 中的密钥在 simple signing 方案下验证通过的签名。
3. 对于来自 `registry.access.redhat.com` 的镜像，必须至少存在一个可以用 `/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release` 中的密钥验证通过的 simple signing 签名。
4. 拒绝所有其他镜像。

上述示例提供了一个安全且健壮的策略配置，但策略文件仍对弱安全要求提供了足够的配置灵活性。例如，如果所有者需要完全禁用容器镜像签名验证功能（例如所有者认为仅加密就足以满足其安全要求），策略文件可以是：

```json
{
  "default": [
    {
      "type": "insecureAcceptAnything"
    }
  ],
}
```

**警告**：该配置将使 Pod 接受所有未签名的容器镜像。

如果所有者想要无条件接受来自特定注册表的镜像，只需将该注册表对应范围下匹配的成员的策略改为 `insecureAcceptAnything` 即可。

## 签名验证

### 获取签名

不同的签名方案通常使用不同的签名存储位置。当 image-rs 需要验证签名时，首先需要获取镜像的签名。存储位置可能是：

1. 本地文件系统。
2. 容器注册表。
3. 自定义的远程服务器。例如一个 http/https web 服务器。
4. 镜像元数据。

### 验证步骤

单个签名的验证动作分为以下步骤：

1. 获取并解析签名 blob。
2. 读取 `policy.json` 的策略，根据 `type` 字段选择验证签名时要使用的方案。
3. 获取公钥。
4. 使用公钥验证密码学签名。
5. 比较签名 payload 中的信息与实际镜像的信息是否一致。

## 镜像层解密

在验证完容器镜像签名后，`image-rs` 调用 `ocicrypt-rs` 来解密每一个加密的镜像层。`ocicrypt-rs` 将层的注解包发送给 `confidential-data-hub` 的 KeyProvider 服务，由它进行解密（使用所配置的任意 KBC 插件——如果使用的是 `cc_kbc`，则经由 `attestation-agent` 进行证明并与 KBS 通信；如果使用的是 `offline_fs_kbc`，则读取本地资源文件），并返回该层的对称密钥。完整的提交流程请参见下方的“Attestation Agent 与 Confidential Data Hub”小节以及 [IMPLEMENTATION.md](../../../../attestation-agent/docs/IMPLEMENTATION.md)。

# Attestation Agent 与 Confidential Data Hub

[`attestation-agent`](../../../../attestation-agent)（AA）和 [`confidential-data-hub`](../../../../confidential-data-hub)（CDH）是机密容器架构中不可或缺的核心组件，共同承担机密容器的信任分发功能：

- **`attestation-agent`** 与依赖方（KBS）执行 TEE 证明握手（RCAR 协议）以获取一份经过签名的证明 token。它本身并不向 `image-rs`/`ocicrypt-rs` 提供 `GetResource` 或 `KeyProvider` 请求服务。AA 仅在 CDH 配置了其 `cc_kbc` KBC 插件（见下文）时才被涉及；其他的 KBC 插件，例如 `offline_fs_kbc`，并不使用 AA，也不执行任何证明。
- **`confidential-data-hub`** 才是 `image-rs` 和 `ocicrypt-rs` 真正通信的组件。当使用 `cc_kbc` KBC 插件时，它从 AA（经由 ttrpc/gRPC）获取证明 token，并将其作为 bearer token 直接调用 KBS 的 REST API——CDH 无需知道 token 是如何获取的。它同时作为所有者机密信息的来源，服务于签名验证（`GetResource` 服务，用于获取 `policy.json` 及相关材料）和镜像解密（`KeyProvider` 服务，用于解包每层的对称密钥）两件事。CDH 以遗留的 ocicrypt 提供方名称 `attestation-agent` 来声明其 `KeyProvider` 服务，以保持向后兼容的注解处理。

完整的协议与实现细节请参见 [IMPLEMENTATION.md](../../../../attestation-agent/docs/IMPLEMENTATION.md) 和[资源服务](../../../../confidential-data-hub/docs/RESOURCES_SERVICES.md)，以及 [`protos/protos/confidential-data-hub`](../../../../protos/protos/confidential-data-hub) 中的 `.proto` 定义。
