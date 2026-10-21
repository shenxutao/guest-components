# 资源 URI（Resource URIs）

## 简介

资源 URI 在机密容器中被广泛用于标识资源。例如，一个加密镜像的元数据可以包含一个引用镜像解密密钥的资源 URI。一个镜像签名策略或一个密封密钥也可以包含一个资源 URI。

尽管这些一直被称为 KBS 资源 URI，但该抽象实际上由 CDH 实现。

资源 URI 与向 Trustee 的 REST API 请求资源的路径并不相同。这两者之间的映射关系描述如下。

从技术上讲，资源 URI 并不绑定到任何特定的 KBS，但本文档主要关注 Trustee 以及 CC_KBC，并描述资源 URI 与 Trustee 的关系。一些遗留代码，例如 FS KBC，可能会以不同的方式满足资源 URI。

## 规范

一个资源 URI 必须符合以下格式：

```plaintext
kbs[+<plugin>]://<kbs_host>:<kbs_port>/<path>[/<path>...][?<query>]
```

授权（authority）之后的路径由一个或多个由 `/` 分隔的片段（segment）组成。URI 可以包含多少个片段并没有固定限制。

### 插件（Plugin）

scheme 中可选的 `<plugin>` 字段标识了由哪个 Trustee 插件来满足该资源。
如果未给出，默认使用 `resource` 插件。

- `kbs://` —— 默认 `resource` 插件的简写。
- `kbs+<plugin>://` —— 从特定插件请求资源（例如，`kbs+pkcs11://` 对应 Trustee 的 `pkcs11` 插件）。

当 URI 被解析时，`kbs://` 和 `kbs+resource://` 在内部都存储为插件名 `resource`。当序列化时（例如通过 JSON），默认的 `resource` 插件会被省略，规范形式为 `kbs://`。

### 主机与端口

主机和端口指向将提供该资源的 KBS 实例。目前，CDH 会忽略这些字段，转而从 CDH 配置文件中获取 KBS 的 URI 和端口。这样，如果 KBS URI 发生变化，就无需更新资源 URI。这意味着通常只有一个 KBS 为 Pod 提供资源，也有通过密封密钥绕过这一限制的办法。未来可能会支持多 KBS 的工作负载。

由于这些字段被忽略，大多数资源 URI 都省略了它们。这就导致了连续三个斜杠。例如，`kbs:///default/cosign-public-key/test`。

### 资源路径（片段）

URI 的路径部分是一系列由一个或多个 `/` 分隔的片段。

一个常见的约定是，`resource` 插件使用三个片段——通常称为 `repository`、`type` 和 `tag`——但这些名称是任意的。只要路径非空，任意数量的片段都是有效的。

当使用 Trustee 的 `resource` 插件时，拼接起来的片段构成发送给 KBS 的资源路径。其他插件可能会以不同的方式解释这些片段。

### 查询字符串

资源 URI 支持查询字符串，当存在时会被转发到 KBS 的 HTTP 请求中。

## 示例

* `kbs://example.cckbs.org:8081/alice/decryption-key/1`
* `kbs:///a/b/c`
* `kbs+pkcs11:///a/b/c`
* `kbs:///repo/nested/type/tag/extra`（超过三个片段的路径）
* `kbs:///repo/type/tag?param1=value1&param2=value2`

经过解析与重新序列化后，默认 `resource` 插件的 URI 会被规范化为 `kbs://` 形式，例如 `kbs:///a/b/c`。带有其他插件的 URI 会在 scheme 中保留显式的插件名，例如 `kbs+pkcs11:///a/b/c`。

## 映射

资源 URI 被转换为对 Trustee 的一个 HTTP(S) 请求。路径片段（授权之后的所有内容）用 `/` 拼接，并附加在插件名之后：

```plaintext
http://<kbs_host>:<kbs_port>/kbs/v0/<plugin>/<segment1>/<segment2>/...
```

例如，`kbs://example.cckbs.org:8081/alice/decryption-key/1` 变为：

```plaintext
http://example.cckbs.org:8081/kbs/v0/resource/alice/decryption-key/1
```

如果资源 URI 中没有指定插件（`kbs://`），则使用 `resource`。

关于 KBS API 的更多信息可以参见 [此处](https://github.com/confidential-containers/trustee/blob/main/kbs/docs/kbs.yaml)。
