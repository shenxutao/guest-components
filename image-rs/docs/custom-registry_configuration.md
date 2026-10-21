# 注册表配置（Registry Configuration）

## 背景

CONTAINERS-REGISTRIES 配置文件是一个容器镜像注册表的配置文件。

它可以基于注册表/仓库/镜像层面提供拦截（blocking）、重映射（remapping）和镜像（mirroring）功能。

> [!NOTE]
> 该配置将在 [镜像安全策略](./ccv1_image_security_design.md) 之前被应用。

### 相关链接

- [容器注册表配置的语法](https://github.com/containers/image/blob/main/docs/containers-registries.conf.5.md)
- [如何管理 Linux 容器注册表](https://www.redhat.com/en/blog/manage-container-registries)

## 示例

配置文件的路径可以通过 `image-rs` 配置的 `registry_configuration_uri` 设置。其格式类似如下：

```toml
# 处理短名称
unqualified-search-registries = ["docker.io", "example1.com"]

# 拦截注册表
[[registry]]
prefix = "example.com/banned"
blocked = true

# 注册表镜像
[[registry]]
prefix = "example.com/foo"
insecure = false
blocked = false

[[registry.mirror]]
location = "example-mirror-0.local/mirror-for-foo"

[[registry.mirror]]
location = "example-mirror-1.local/mirrors/foo"
insecure = true

# 注册表重映射
[[registry]]
prefix = "registry.com"
location = "remapping.registry.com"

# 允许不安全的注册表
[[registry]]
location = "localhost:5000"
insecure = true
```

让我们通过一些典型场景来逐一了解其用法。

## 典型用法

### 通过短名称拉取镜像

通常当我们使用 kubernetes 或 docker 时，不会指定镜像完整的注册表和仓库路径。默认情况下，它会从 `docker.io` 下载。`docker pull alpine` 会解析为 `docker.io/library/alpine:latest`，而 `docker pull repo/image:tag` 会解析为 `docker.io/repo/image:tag`（注意指定的 repo）。

因此，如果我们希望短名称被解析到更多注册表，我们可以使用 `unqualified-search-registries`。

```toml
unqualified-search-registries = ["docker.io", "example1.com"]
```

名为 `alpine` 的镜像将被解析为 `docker.io/library/alpine:latest` 和 `example1.com/alpine:latest`。
名为 `repo/alpine` 的镜像将被解析为 `docker.io/repo/alpine:latest` 和 `example1.com/repo/alpine:latest`。
注意，如果镜像名未限定，注册表 `docker.io` 会自动添加一个命名空间 `library`。

### 拦截一个注册表、命名空间或镜像

如果一个注册表不允许被使用，我们可以使用 `blocked` 字段来拦截它。

```toml
[[registry]]
prefix = "example.com/banned"
blocked = true
```

`blocked=true` 会阻止拉取带有此前缀的镜像，例如 `example.com/banned/repo:tag`。

如果要拦截一个特定镜像，可以使用以下方式设置 `prefix`：

```toml
prefix="registry.example.org/namespace/image"
```

### 镜像注册表（Mirroring）

我们经常在隔离的网络环境中拉取镜像。在这种情况下，我们无法连接到原始注册表，或者网络很慢，因此我们需要运行一个镜像注册表来镜像本地网络的内容，以加速网络访问。

会首先尝试注册表镜像，然后再尝试原始注册表。如果所有镜像拉取都失败，才会尝试原始注册表。

```toml
[[registry]]
location="registry.access.redhat.com"
[[registry.mirror]]
location="internal.registry.mirror"

[[registry]]
location="docker.io"
[[registry.mirror]]
location="123456.mirror.aliyuncs.com"
```

此时 `registry.access.redhat.com/nginx:latest` 将被镜像到 `internal.registry.mirror/nginx:latest`。类似地，`nginx:latest` 将被镜像到 `123456.mirror.aliyuncs.com/library/nginx:latest`，而 `foo/bar:latest` 将被镜像到 `123456.mirror.aliyuncs.com/foo/nginx:latest`。

### 重映射引用（Remapping references）

在镜像场景中，原始仓库最终仍会被尝试，但重映射会将原始的镜像拉取请求重定向到新的注册表。让我们考虑在空气隔离（air-gapped）环境中运行的情况。由于我们与互联网断开连接，无法访问容器注册表。我们的工作负载使用来自 `Quay.io`、`Docker Hub` 和 Red Hat 容器注册表的镜像。虽然我们每个注册表都可以有一个网络本地镜像，但我们也可以用以下配置只使用一个：

```toml
[[registry]]
prefix="quay.io"
location="internal.registry.mirror/quay"

[[registry]]
prefix="docker.io"
location="internal.registry.mirror/docker"

[[registry]]
prefix="registry.access.redhat.com"
location="internal.registry.mirror/redhat"
```

### 不安全的注册表（Insecure registry）

运行一个本地容器注册表是很常见的。这意味着通过 HTTP 而不是 HTTPS 连接到注册表。可以通过将 `insecure` 字段设为 `true` 来实现。

```toml
[[registry]]
location = "localhost:5000"
insecure = true
```
