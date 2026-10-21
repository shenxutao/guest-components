# 使用 cosign 进行镜像签名

本文档包含以下内容：
* 生成 cosign 签名镜像的指南。
* 配置镜像安全策略以启用镜像签名验证的指南。
* 通过 offline-fs-kbc 分发公钥与镜像安全策略的指南。

## 对加密/未加密镜像签名，并在运行工作负载时启用签名验证

当从容器注册表拉取镜像时，[策略要求](https://github.com/containers/image/blob/main/docs/containers-policy.json.5.md#policy-requirements)可以决定该镜像是否可被接受。

这些要求可以是：

* 直接拒绝
* 无条件接受
* 需要签名验证

本节展示如何对镜像进行签名，并启用特定仓库的签名验证。

### 使用 cosign 对镜像签名

加密和未加密的镜像都可以被签名。

我们需要安装 `cosign` 来签名镜像。cosign 背后的详细工作流程可见[此文档](../../src/signature/policy/cosign/README.md)。按照[这里的指南](https://github.com/sigstore/cosign#installation)安装 `cosign`：

安装完 `cosign` 后，我们需要生成一个密钥对来签名镜像并验证相关签名。

```
# 生成签名密钥对
cosign generate-key-pair
```

输入两次密码后，会生成一个密钥对，即私钥 `cosign.key` 和公钥 `cosign.pub`。这里，密码用于加密私钥。当我们使用私钥对镜像签名时，需要输入该密码。当然，密码也可以为空。

假设已经准备好一个名为 `example.org/test` 的待签名镜像：

```
# sudo docker images
REPOSITORY            TAG                  IMAGE ID       CREATED         SIZE
example.org/test      latest               ff4a8eb070e1   2 weeks ago     1.24MB
```

现在让我们使用新生成的私钥对该镜像签名：

```
cosign sign --key cosign.key [REGISTRY_URL]:cosign-signed
```

这里，`cosign.key` 可以替换为任何 cosign 生成的私钥。

现在该镜像已被 cosign 签名，签名被推送到与镜像相同的仓库中。

想了解更多关于 cosign 的信息，请参考[该 GitHub 仓库](https://github.com/sigstore/cosign)。

### 启用 cosign 镜像签名验证，并通过 KBC 通道获取公钥

以 [机密数据中枢](../../../confidential-data-hub/docs/RESOURCES_SERVICES.md)（简称 Offline-FS-KBC）提供的 `offline_fs_kbc` KBC 为例。

#### 准备带 Offline-Fs-KBC 的机密数据中枢（CDH）

克隆仓库。

```
git clone https://github.com/confidential-containers/guest-components
```

构建 CDH，禁用 KMS provider 以加快构建速度（`offline_fs_kbc` 始终被内置构建）：
```
cd guest-components/confidential-data-hub
make KMS_PROVIDER=none
```

#### 添加 Offline-Fs-KBC 资源

所有的签名验证规则都定义在一个 `policy.json` 中。但在处理 `policy.json` 之前，有几点需要澄清：
* `policy.json` 由依赖方（relying party）提供，因此我们将使用 Offline-Fs-KBC 来提供这个机密文件。该通道是安全的。
* 验证用的公钥也经由 KBC 安全通道获取。

因此接下来的步骤会首先将两个资源（`policy.json` 和公钥）添加到 Offline-Fs-KBC 资源中。

让我们继续以镜像 `example.org/test` 为例，并启用安全策略（包括签名验证）。

首先编辑一个类似如下的 `policy.json`：

```
{
    "default": [{"type": "reject"}], 
    "transports": {
        "docker": {
            "example.org": [
                {
                    "type": "sigstoreSigned",
                    "keyPath": "/run/image-security/cosign/cosign.pub"
                }
            ]
        }
    }
}
```

这里，`"keyPath"` 指向 `cosign.pub` 公钥的路径。当验证发生时，首先检查该路径下是否存在该文件。如果不存在，则通过 KBC 安全通道获取该密钥。

让我们为这两个资源计算 base64 编码值：
```bash
cat /path/to/policy.json | base64 --wrap=0
cat /path/to/cosign.pub | base64 --wrap=0
```

`offline_fs_kbc` 从 `/etc/aa-offline_fs_kbc-resources.json` 读取资源。将两个资源的 base64 编码值添加到该文件中，键分别为 `default/security-policy/test`（策略）和 `default/cosign-public-key/test`（公钥），例如：

```
{
  "default/security-policy/test": "<base64-encoded policy.json>",
  "default/cosign-public-key/test": "<base64-encoded cosign.pub>"
}
```

然后安装该文件，以及一个（空的，如果未使用）密钥文件：
```
sudo cp aa-offline_fs_kbc-resources.json /etc/aa-offline_fs_kbc-resources.json
sudo cp aa-offline_fs_kbc-keys.json /etc/aa-offline_fs_kbc-keys.json
```

通过这种方式，当拉取来自 `"example.org"` 的镜像时，将使用路径 `"/run/image-security/cosign/cosign.pub"` 处的公钥来验证签名。

现在让我们启动 CDH，配置为通过 ttRPC/gRPC 提供 `offline_fs_kbc` 资源（完整的配置示例请参见[机密数据中枢文档](../../../confidential-data-hub/docs/RESOURCES_SERVICES.md)）：

```
confidential-data-hub -c cdh_conf.toml
```

现在机密数据中枢就可以对 image-rs 的资源提供方（它通过 ttRPC/gRPC 连接到 CDH，参见 [`image-rs/src/resource/kbs`](../../src/resource/kbs)）以正确的资源作出响应了。
