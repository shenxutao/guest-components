# 使用 Nydus 拉取镜像（已弃用）

> [!NOTE]
> image-rs 已不再支持 Nydus。本文档即将被删除。

## 准备环境

### 1. 安装所有 Nydus 二进制文件

需要 Nydus 二进制文件来将容器镜像或目录转换为（加密的）Nydus 镜像。按照说明安装 Nydus。

从 [release](https://github.com/dragonflyoss/image-service/releases) 页面获取 `nydus-image`、`nydusd`、`nydusify`、`nydusctl` 和 `nydus-overlayfs` 二进制文件。

```shell
sudo install -D -m 755 nydusd nydus-image nydusify nydusctl nydus-overlayfs /usr/bin
```

### 2. 部署并配置 CoCo 密钥代理系统（Key Broker System）集群

一个租户侧的 CoCo 密钥代理系统集群包括：
* 密钥代理服务（KBS）：机密资源的代理服务。
* 证明服务（AS）：用于远程证明的验证方。
* 参考值提供方服务（RVPS）：为 AS 提供参考值。
* CoCo Keyprovider：遵循 ocicrypt 规范加密镜像的组件。

我们将使用该密钥代理系统集群来加密镜像。按照 [说明](https://github.com/confidential-containers/confidential-containers/blob/main/quickstart.md#deploy-and-configure-tenant-side-coco-key-broker-system-cluster) 准备 CoCo 密钥代理系统。

----

## 生成加密的 Nydus 镜像

使用 `nydusify` 和 `nydus-image` 将 OCI 容器镜像转换为带有 KBS 集群的加密 Nydus 镜像。以 busybox:latest 为例：

```shell
cat > ocicrypt.conf << EOF
{
    "key-providers": {
        "attestation-agent": {
            "grpc": "127.0.0.1:50000"
        }
    }
}
EOF
```

```shell
OCICRYPT_KEYPROVIDER_CONFIG=ocicrypt.conf \
nydusify convert --source docker.io/library/busybox:latest \
--target [REGISTRY_URL]/busybox:encrypted-nydus \
--encrypt-recipients provider:attestation-agent \
--nydus-image /usr/bin/nydus-image
```

请务必将 [REGISTRY_URL] 替换为所需的注册表 URL，例如 `docker.io/myregistry`。

----

## 在 CC 硬件上将加密 Nydus 镜像作为 CoCo 工作负载部署

下面是一个加密 Nydus 镜像部署的示例 yaml：

encrypted-image-test-busybox.yaml
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: encrypted-image-test-busybox
spec:
  containers:
  - image: [REGISTRY_URL]/busybox:encrypted-nydus
    name: busybox
  dnsPolicy: ClusterFirst
  runtimeClassName: [RUNTIME_CLASS]
```

请务必将 [REGISTRY_URL] 替换为前一步生成的加密镜像的注册表 URL，将 [RUNTIME_CLASS] 替换为 CC 硬件的 kata 运行时类。将加密镜像作为工作负载部署：

```shell
kubectl apply -f encrypted-image-test-busybox.yaml
```

----

## 优化结果
|镜像|未压缩镜像大小|OCI 镜像大小|Nydus 镜像大小|CMD|使用加密 OCI 镜像创建并启动容器的时间|使用加密 Nydus 镜像创建并启动容器的时间|优化百分比|
|-|-|-|-|-|-|-|-|
|busybox|4.86MB|2.47MB|2.21MB|top|1.782s|1.904s|-6.8%|
|ubuntu|72.8MB|28.16MB|30.86MB|sh|3.412s|2.167s|36.5%|
|redis|113MB|45.9MB|48.29MB|redis-server|5.214s|2.455s|52.9%|
|nginx|141MB|67.32MB|69.06MB|nginx|6.937s|2.578s|62.8%|
|mysql|516MB|157.98MB|168.33MB|mysqld|16.577s|2.444s|85.3%|
|python|917MB|360.43MB|351.78MB|python|33.531s|2.303s|93.13%|
|node|993MB|380.02MB|363.75MB|node|37.123s|2.257s|93.92%|
|gradle|752MB|396.99MB|395.8MB|gradle|35.767s|2.069s|94.22%|
