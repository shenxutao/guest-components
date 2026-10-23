# 设计与架构

## 作者
 * [Arron Wang](https://github.com/arronwy)
 * [Jiang Liu](https://github.com/jiangliu)

## 设计

`image-rs` crate 是 [containers/image](https://github.com/containers/image) 的 Rust 化且定制过的版本，旨在提供一个小巧、简单、安全、轻量且高性能的 OCI 容器镜像管理库。
该 crate 的开发由 [机密容器（Confidential Containers）](https://github.com/confidential-containers) 项目范围驱动，但也可能以更通用的方式使用。

目前 `image-rs` crate 聚焦于在 Kubernetes 集群上配合 [Kata Containers](https://katacontainers.io/) 运行机密容器的使用场景。也可以按需增强以支持其他机密容器运行时。因此它实现了 [CRI Image Service](https://github.com/kubernetes/cri-api/blob/4d83b9bd4e13b76ae8cbb317f6515cb84effa5d2/pkg/apis/runtime/v1/api.proto#L137) 接口，以便与 K8s 生态系统轻松集成。在容器镜像的 `构建`（Build）、`分发`（Ship）和`运行`（Run）三个阶段中，它聚焦于 `运行` 阶段，而不是 `构建` 和 `分发`。`运行` 阶段将主要覆盖 `拉取`（Pull）和`解包`（Unpack）操作，提供在机密环境中准备容器镜像的接口。用户可以使用任何兼容 OCI 镜像/分发规范的工具来构建和分发带有或不带有签名的加密/明文容器镜像。

`image-rs` crate 同时支持未加密和加密的容器镜像，因为 [加密容器镜像](https://github.com/opencontainers/artifacts/pull/15) 对于许多机密容器使用场景是必需的。它还支持镜像签名验证以确保完整性。根据机密容器的威胁建模，应当可配置支持哪些类型的镜像。策略可能如下，目前我们支持镜像级签名和层级加密，是否需要每层签名支持仍是 TBD（待定）：

 1. 加密且带签名，强制
 2. 加密但不带签名，强制
 3. 未加密但带签名，可配置且应启用
 4. 未加密且不带签名，可配置且可能被禁用

### 目标（Goals）
 * 支持从注册表（registry）拉取带或不带认证的 OCI/docker v2 镜像
 * 支持从本地 [OCI layout 兼容](https://github.com/opencontainers/image-spec/blob/main/image-layout.md) 存储下载 OCI 镜像
 * 支持 OCI 镜像解密
 * 支持 OCI 镜像签名验证
 * 支持针对允许的 OCI 镜像的可配置安全策略
 * 支持与 Kata Agent 和 Attestation Agent 无缝集成
 * 提供用于调试的命令行工具
 * 探索镜像解密与解压缩加速技术
 * 探索镜像按需加载技术
 * 探索在容器/Pod 之间以机密性和完整性共享镜像数据的技术

### 非目标（Non-Goals）
 * 镜像推送，针对远程注册表的内容发现/管理操作
 * 镜像加密与签名
 * 镜像导出到本地存储
 * 从其他服务守护进程或其他本地存储格式导入镜像

### 现有方案
 * [containers-image-proxy-rs](https://github.com/containers/containers-image-proxy-rs)：skopeo 的 Rust 绑定，无法满足我们对小 TCB 和轻量的要求。
 * [oci-distribution](https://github.com/krustlet/oci-distribution)：来自 [krustlet](https://github.com/krustlet/krustlet) 的一个 crate，用于在 K8S 上运行 wasm 应用。由于 wasm 平台无关且代码体积小，`oci-distribution` 不支持不同平台的 manifest 列表（manifest lists），且内部数据结构对通用容器工作负载不友好。
 * [oci-registry-client](https://github.com/ecarrara/oci-registry-client)：一个非常简单的 OCI 镜像注册表客户端，功能有限，且最新提交已是一年半以前。

这些项目聚焦于镜像分发，不支持镜像解包和存储管理功能。

## 架构

下图展示了整体架构以及它与 Kata Agent 的集成方式：
![架构](../../../../image-rs/docs/images/architecture.png)

架构图源文件：[architecture.pptx](../../../../image-rs/docs/images/architecture.pptx)

`image-rs` crate 提供了一个覆盖 OCI 规范的容器镜像拉取和管理部分的 API。

在镜像拉取部分，它将遵循 OCI 分发（distribution）和镜像规范，与远程注册表交互以下载容器镜像元数据和 blob 数据，这些信息将被镜像管理模块消费。容器镜像下载完成后，`image-rs` 将与远程证明服务通信，以验证镜像签名并在需要时对镜像进行解密。镜像解包之后，为了支持 guest 内部的镜像缓存，镜像格式模块可以处理 oci v1 与 docker v2 之间的格式转换。

镜像拉取模块与 [Attestation-agent](../../../../attestation-agent) 协作，从远程证明和密钥管理服务器获取用于解密/验证的密钥。

快照（Snapshot）模块将准备 rootfs 以及容器配置和元数据，可以生成供运行时服务消费的 bundle。快照模块还可以支持不同的 snapshotter，以支持镜像按需拉取。

由于容器镜像层的解密和解压缩可能很耗时，`image-rs` 将支持不同的加速库来加速这些过程，例如 Intel 存储加速库：[isa-l](https://github.com/intel/isa-l) 和 [isa-l_crypto](https://github.com/intel/isa-l_crypto)。

## 参考
 * [Nydus Image Service](https://github.com/dragonflyoss/image-service)：用于数据按需加载、数据去重和加密。
 * [stargz](https://github.com/containerd/stargz-snapshotter)：用于数据按需加载。
