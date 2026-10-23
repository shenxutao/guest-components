# 使用阿里云 OSS 进行安全挂载

本指南帮助用户：
- 使用 gocrypt-fs 创建客户端加密的存储并上传到阿里云 OSS
- 使用机密数据中枢在 TEE 环境内进行安全挂载

## 准备工作

用户应当准备以下内容：
- 一个 [OSS 存储](https://www.alibabacloud.com/product/object-storage-service?spm=a3c0i.23458820.2359477120.62.94807d3f6Q2Oqb) 服务，以及一个 OSS bucket，其 id 例如 `<bucket-id>`
- 安装 [ossutil](https://www.alibabacloud.com/help/en/oss/developer-reference/install-ossutil) 和 [ossfs](https://github.com/aliyun/ossfs)，这是用于与 OSS 交互的工具
- 假设操作系统为 ubuntu。

## 步骤

有两种模式：[OSS 中的明文数据](../../../../../confidential-data-hub/docs/SECURE_STORAGE.md#plaintext-data-in-oss) 和 [OSS 中的密文数据](../../../../../confidential-data-hub/docs/SECURE_STORAGE.md#ciphertext-data-in-oss)。以下步骤针对 [OSS 中的密文数据](../../../../../confidential-data-hub/docs/SECURE_STORAGE.md#ciphertext-data-in-oss)。如果用户想使用 [OSS 中的明文数据](../../../../../confidential-data-hub/docs/SECURE_STORAGE.md#plaintext-data-in-oss) 模式，只需跳过 gocryptfs 加密部分，直接用 `ossutil` 上传明文数据即可。

### 创建 gocryptfs 并上传到 OSS 存储

首先，安装 golang 和 gocryptfs
```shell
# 安装 golang
wget https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# 安装 gocryptfs
git clone https://github.com/rfjakob/gocryptfs.git
cd gocryptfs
./build-without-openssl.bash
sudo apt install libssl-dev
```

准备一个由 gocryptfs 用于加密内容的密码 `<PASSWORD>`
```shell
mkdir -p /path/to/workspace
cd /path/to/workspace
echo <PASSWORD> > password
```

创建 gocryptfs 的工作目录
```shell
mkdir cipher plain

cat password | gocryptfs -init cipher
cat password | gocryptfs cipher plain
```

然后，将要加密的任何数据移动到路径 `/path/to/workspace/plain`。
同时，数据会被 gocryptfs 自动加密。
密文将位于 `/path/to/workspace/cipher`。

然后，将密文（整个目录 `/path/to/workspace/cipher`）上传到 OSS 存储 bucket
```shell
ossutil64 cp -r /path/to/workspace/cipher oss://<bucket-id>/<bucket-path>
```

### 在 TEE 环境内进行安全挂载

首先，构建 [CDH 客户端工具](../../../../../confidential-data-hub/README.md#client-tool) 和 [CDH](../../../../../confidential-data-hub/README.md#confidential-data-hub)。

确保 `gocryptfs` 和 `ossfs` 都已安装到 `/usr/local/bin`。

运行 CDH
```shell
confidential-data-hub
```

准备一个请求 JSON `storage.json`。本例针对阿里云 OSS。
```json
{
    "volume_type": "alibaba-cloud-oss",
    "options": {
        "akId": "XXX",
        "akSecret": "XXX",
        "annotations": "",
        "bucket": "<bucket-id>",
        "encrypted": "gocryptfs",
        "encPasswd": "<PASSWORD>",
        "kmsKeyId": "",
        "otherOpts": "-o max_stat_cache_size=0 -o allow_other",
        "path": "<bucket-path>",
        "readonly": "",
        "targetPath": "/mnt/aliyun-oss",
        "url": "https://oss-cn-beijing.aliyuncs.com",
        "volumeId": ""
    },
    "flags": [],
    "mount_point": "/mnt/target-path"
}
```
字段说明：
- `volume_type`：安全挂载插件的类型名。它决定了其余字段如何使用。
- `options`：一个键值映射，用于指定挂载操作的设置。不同的插件可以定义不同的 `option` 键。在本例中，所有键都针对阿里云 OSS。
- `flags`：一个字符串列表，用于指定挂载操作的设置。不同的插件可以定义该字段的不同用途。
- `mount_point`：操作的挂载目标路径。

让我们深入了解示例的 `options` 字段。注意，本例针对阿里云 OSS，不同的挂载插件可以定义自己的 `options`！

这里的字段：
- `akId`：访问 OSS bucket 的 AK 的 Id。在创建 OSS bucket 时会提供。这也可以是一个 [密封密钥](../../../../../confidential-data-hub/docs/SEALED_SECRET.md)。
- `akSecret`：访问 OSS bucket 的 AK 的明文。在创建 OSS bucket 时会提供。这也可以是一个 [密封密钥](../../../../../confidential-data-hub/docs/SEALED_SECRET.md)。
- `annotations`：空。
- `bucket`：OSS bucket 的 id，即 `<bucket-id>`。
- `encrypted`：如果设为 `gocryptfs`，意味着将使用 `gocryptfs` 解密 oss 存储，并将明文挂载到 `targetPath`。否则（如留空），意味着 oss 存储将被直接挂载到 `targetPath`。
- `encPasswd`：如果 `encrypted` 设为 `gocryptfs`，此字段应为使用 `gocryptfs` 加密时的密码。此字段也可以是一个 [密封密钥](../../../../../confidential-data-hub/docs/SEALED_SECRET.md)。
- `kmsKeyId`：空。
- `otherOpts`：挂载 oss 存储时的其他选项。
- `path`：OSS bucket 中的路径，即 `/<bucket-path>`。
- `readonly`：空。
- `targetPath`：此字段未被使用。
- `url`：OSS 存储服务的 URL。在本例中，oss 服务位于中国北京。在创建 OSS bucket 时可选择。
- `volumeId`：空。

:warning: **警告：** 如果使用了任何 [密封密钥](../../../../../confidential-data-hub/docs/SEALED_SECRET.md)，CDH 将尝试访问相关的 KMS 服务（很可能是 KBS）。

向 CDH 发送请求
```shell
client-tool secure-mount --storage-path storage.json

# 检查目标路径以确认挂载是否成功
ls /mnt/aliyun-oss
```
