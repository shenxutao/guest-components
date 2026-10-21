# CCv1 镜像认证（Image Auth）

## 背景

当租户想要使用来自私有注册表的镜像来部署机密容器时，Pod 内部的 `image-rs` 模块需要从该私有注册表拉取镜像。
这里，私有注册表意味着 `image-rs` 模块需要凭据（credentials）来展示该注册表的权限。
不同的 OCI 注册表支持不同类型的认证，然而 `image-rs` 的上游 crate [`oci_distribution`](https://github.com/krustlet/oci-distribution/tree/main) 只支持以下两种类型：
- `Anonymous`：从不带任何认证的公开注册表拉取镜像。
通过这种方式，除了来自私有注册表的镜像外，大多数公开镜像都可以被拉取。此外，像 `dockerhub` 这样的注册表可以限制每月（我记得约 100 次）请求数。
- `Basic`：使用 `username` 和 `password` 作为该注册表的 _凭据_（Credential）。这种方式不会出现上述限制。

[Containers](https://github.com/containers) 有一套 [定义良好的机制](https://github.com/containers/image/blob/main/docs/containers-auth.json.5.md) 来在拉取镜像时分发注册表的 _凭据_。其工作流程和考量将在下文详述。

### 相关链接

- [从私有仓库拉取镜像的需求](https://github.com/kata-containers/kata-containers/issues/4601)
- [注册表认证文件的语法](https://github.com/containers/image/blob/main/docs/containers-auth.json.5.md)

## 目标

总目标是支持使用认证信息（即特定注册表的凭据）来拉取镜像。在此之下，子目标是：
- 在拉取镜像时支持 [`注册表认证文件`](https://github.com/containers/image/blob/main/docs/containers-auth.json.5.md) 机制。
- 当启用了 KBS 且在特定文件系统路径下找不到时，支持从 KBS 获取 [`注册表认证文件`](https://github.com/containers/image/blob/main/docs/containers-auth.json.5.md)。

## 工作流程

本节将阐明一个注册表的授权（authorization）与认证（authentication）流程。首先让我们做一些假设以便说明。

### 基本模型

- 用户 `Alice` 想要在一个机密 VM（即 Pod）内部署一个镜像 `busybox`。假设机密 VM 的主机是 `Bob`，他可以代表 CSP（云服务提供商）。
- 该镜像来自一个私有注册表 `private-registry.org`，需要凭据才能登录。
- 该镜像在 VM 内部拉取，以防止 `Bob` 知晓凭据。
- `Alice` 拥有该注册表的凭据，即 `username:Alice`、`password:pswd`。
- `Bob` 侧用于部署机密容器的 Pod 由 `Alice` 独占。

### 授权

`Alice` 应当首先按照 [格式](https://github.com/containers/image/blob/main/docs/containers-auth.json.5.md#format) 编辑一个 `auth.json`。在这个故事中，例如，`auth.json` 可以是：

```json
{
	"auths": {
		"private-registry.org": {
			"auth": "QWxpY2U6cHN3ZAo="
		},
	}
}
```

这里 `QWxpY2U6cHN3ZAo=` 是 base64 编码的 `Alice:pswd`。
所有凭据都有一个通用格式 `<username>:<password>`。

以上所有操作都发生在 `Alice` 侧，因此对 `Bob` 而言是完全安全的、不可知的。

### 认证

当 `Alice` 想要在 `Bob` 侧的机密 VM 内部部署镜像 `private-registry.org/busybox` 时，`image-rs` 需要拉取该镜像。

1. 首先，它检查是否存在 `auth.json` 文件，如果存在，执行第 3 步。
2. 通过同 Pod 内 Attestation Agent 的 `GetResource` gRPC 获取 `auth.json`。关于 `GetResource` 和 Attestation Agent 的更多细节请参考 [get-resource-service](ccv1_image_security_design.md#get-resource-service) 和 [attestation-agent](ccv1_image_security_design.md#attestation-agent)。
3. 然后 `image-rs` 模块使用最长前缀匹配来匹配 `auth.json` 中的条目。在这个故事中，它会这样做：
* 首先查找条目 `private-registry.org/busybox`，但没有找到。
* 然后搜索条目 `private-registry.org`，匹配到的值将是 `"auth": "QWxpY2U6cHN3ZAo="`。
在其他场景中，如果没有任何条目匹配，则在第 4 步使用 `Anonymous` 认证。
4. `image-rs` 模块使用匹配到的凭据来拉取镜像。

## 考量

### 将 `auth.json` 存储在何处？

与 [镜像安全](ccv1_image_security_design.md#policy) 中的 `policy.json` 相同。我们将文件放在 Pod 内部的 `/run/image-security/auth.json`，因为 `/run` 目录挂载在 `tmpfs` 中，位于由硬件 TEE 保护的加密内存中。

### 当 `image-rs` 在找不到时应何时检查并获取 `auth.json`？

每次执行拉取操作时，如果找不到就检查并获取 `auth.json`。这种方式是 _惰性的_ 且 _按需的_。这种方式是首选，因为它具有较低的 `image-rs` 启动延迟。

### `image-rs` 如何知道相关的 `auth.json` 的 `ResourceDescriptor`？

有两个步骤：

- **步骤 1** 我们在 `image-rs` 侧和 `attestation-agent` 侧都为 `auth.json` 设置一个硬编码的 `ResourceDescriptor`。通过这种方式，我们可以测试 `auth.json` 的能力。

- **步骤 2** 我们为 `image-rs` crate 的 `PullClient` 提供一个配置，用于指示 `ResourceDescriptor` 是什么。通过这种方式，不仅 `auth.json`，`policy.json` 以及 `image-rs` 需要的其他资源都可以被定制。

步骤 1 是短期的，未来我们将逐步实现步骤 2。届时，本文档应当被修改。
