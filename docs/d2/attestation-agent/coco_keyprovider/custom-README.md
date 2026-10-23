# CoCo 密钥提供器（Keyprovider）

CoCo Keyprovider 是一个非常简单的密钥提供工具，可帮助生成与 CoCo 兼容的加密镜像。
该加密镜像可以使用以下密钥代理客户端（KBC）进行解密，两者都作为 [机密数据中枢（Confidential Data Hub）](../../../../confidential-data-hub) 的插件实现：
 * cc_kbc
 * offline_fs_kbc

下面的指南将帮助你使用 [skopeo](https://github.com/containers/skopeo) 和 CoCo keyprovider 制作加密镜像、检视该镜像并进行解密。

## 加密（Encryption）

### Docker

提供了一个 docker 镜像，内含预构建的 CoCo keyprovider 和 skopeo，以简化镜像加密：

```bash
$ docker run ghcr.io/confidential-containers/staged-images/coco-keyprovider /encrypt.sh -h
usage: /encrypt.sh [-k <b64-encoded key>] [-i <key id>] [-s <source>] [-d <destination>]
```

源（source）和目的（destination）必须以 [container/image](https://github.com/containers/image/blob/main/docs/containers-transports.5.md) 的传输 URI（transport URIs）形式提供。

下面的例子会从 docker/library 加密一个镜像，并将生成的加密镜像缓存在本地 `./output` 文件夹：

```bash
head -c 32 /dev/urandom | openssl enc > image_key
mkdir output
docker run -v "$PWD/output:/output" ghcr.io/confidential-containers/staged-images/coco-keyprovider:latest /encrypt.sh \
	-k "$(base64 < image_key)" \
	-i kbs:///some/key/id \
	-s docker://nginx:stable \
	-d dir:/output
```

随后可以使用 skopeo 将该镜像推送到镜像仓库（registry）：

```bash
skopeo copy dir:output docker://ghcr.io/confidential-containers/nginx-encrypted
```

或者，也可以挂载一个授权文件（authorization file）到容器中，以便直接访问私有仓库：

```bash
docker run -v ~/.docker/config.json:/root/.docker/config.json ghcr.io/confidential-containers/staged-images/coco-keyprovider:latest /encrypt.sh \
	-k "$(base64 < image_key)" \
	-i kbs:///some/key/id \
	-s docker://private.registry.io/nginx:stable \
	-d docker://private.registry.io/nginx:encrypted
```

### 详细说明

在本地 localhost 的 50000 端口构建并运行 CoCo keyprovider：

```shell
$ cd attestation-agent/coco_keyprovider
$ RUST_LOG=coco_keyprovider cargo run --release -- --socket 127.0.0.1:50000 &
```

当同时给定 `--kbs` 和 `--auth-private-key` 时，keyprovider 会自动将每个生成的密钥加密密钥（KEK）注册到 KBS。该注册使用由 `--auth-private-key` 签名的 JWT 进行认证。KBS 的管理员授权会将 JWT 的 `role` 声明与其 ACL 进行匹配，因此该 role 必须被 KBS 配置所允许：

- `--kbs <address>`：密钥代理服务（Key Broker Service）的地址。启用自动 KEK 注册。
- `--auth-private-key <path>`：用于签发管理员 JWT 的 Ed25519 私钥 PEM 文件。
- `--admin-role <role>`：管理员 JWT 中包含的 role 声明（默认 `admin`）。必须与 KBS `regex_acl` 允许的 role 相匹配。

Skopeo 利用 [Ocicrypt](https://github.com/containers/ocicrypt) 库来加密/解密镜像。如下方所示创建一份 [Ocicrypt keyprovider](https://github.com/containers/ocicrypt/blob/main/docs/keyprovider.md) 配置文件，并导出 `OCICRYPT_KEYPROVIDER_CONFIG` 变量：

```shell
$ cat <<EOF > ocicrypt.conf
{
  "key-providers": {
    "attestation-agent": {
      "grpc": "127.0.0.1:50000"
}}}
EOF

$ export OCICRYPT_KEYPROVIDER_CONFIG="$(pwd)/ocicrypt.conf"
```

使用 skopeo 的 *copy* 命令复制原始镜像并加密它。该工具可以使用多种传输协议（如 docker、oci、docker-archive 等）在不同存储之间复制镜像，但并非所有存储都支持加密镜像。另需注意：加密失败时 skopeo 不会告警镜像被遗留为未加密状态。根据我们的经验，有两种场景会产生正确的加密镜像：
 * 复制到当前目录下的 oci 镜像
 * 只要目标仓库支持加密镜像，就使用 docker 协议直接推送到远程镜像仓库。支持加密镜像的镜像仓库服务示例有 [docker.io](https://docker.io) 和 [ghcr.io](https://ghcr.io)。

下面的例子将 *busybox* 复制并加密为当前目录下的 *busybox_encrypted* 镜像：

```shell
$ skopeo copy --insecure-policy --encryption-key provider:attestation-agent:<parameters> docker://busybox oci:busybox_encrypted
```

或者我们可以直接将加密镜像推送到远程镜像仓库：

```shell
$ skopeo copy --insecure-policy --encryption-key provider:attestation-agent:<parameters> docker://busybox docker://docker.io/myrepo/busybox:encrypted
```

在上面这些例子中，加密时其实并不需要 `--insecure-policy` 选项，它只是禁用系统的信任策略以避免镜像校验出现任何错误，因此如果你的系统策略配置正确，可以省略它。`--encryption-key` 指定了加密协议，下一节将进行说明。

### 加密协议详解

如上一节所示，传递给 skopeo 的加密协议（`--encryption-key`）格式为 `provider:attestation-agent:<parameters>`。

`<parameters>` 是一个以双冒号分隔的键值列表（例如 key1=value1::key2=value2）。以下是已定义的键：
- `sample`：非必需。取值为 `true` 或 `false`。如果不设置，则使用 `false`。该值指示是否使用硬编码的加密密钥，而不是真实的 KEK。
  > [!WARNING]
  > `confidential-data-hub` 中没有 KBC 会自动知晓这个硬编码密钥。要解密一个
  > `sample=true` 加密的镜像，你需要手动将同一个硬编码密钥作为 `kbs:///default/test-key/1`
  > 资源预置到你的 KBC 中（例如作为一条 `offline_fs_kbc` 资源条目）。在实践中，建议优先使用下面的 `keyid`/`keypath` 模式。
- `keyid`：如果未启用 `sample`，则为必需。它是一个密钥代理服务（KBS）的资源 URI（resource URI，见下方规范）。解密发生时，`keyid` 的值被用于索引密钥加密密钥（KEK）。
- `keypath`：如果未启用 `sample`，则为必需。一个本地文件系统路径，推荐使用绝对路径。指定在本地文件系统上用于加密镜像的 KEK。KEK 将从文件系统读取，然后用于加密镜像。该密钥的长度必须为 32 字节。
- `algorithm`：非必需。指示所使用的加密算法。取值为 `A256GCM` 或 `A256CTR`。如果不提供，默认使用 `A256GCM`，因为它是 AEAD 方案。

`keyid` 参数引用一个 KBS 资源 URI，必须遵循以下格式之一：
- `kbs:///<repository>/<type>/<tag>`
- `kbs://<kbs-addr>/<repository>/<type>/<tag>`
- `<kbs-addr>/<repository>/<type>/<tag>`
- `/<repository>/<type>/<tag>`

其中：
- `kbs-addr`：KBS 的 `address[:port]`
- `repository`：资源的仓库（例如 docker.io）
- `type`：资源的类型（例如 key）
- `tag`：资源的标签或标识符（例如 key\_id1）

### 示例

本节包含加密的示例。

#### 示例 1：使用样例（硬编码）密钥加密

让我们从最简单的可能示例开始，即使用硬编码的样例密钥加密一个镜像。
注意，如上所述，当前如果没有手动预置同一个硬编码密钥，该镜像无法被 `confidential-data-hub` 中的任何 KBC 解密：

```shell
$ skopeo copy --insecure-policy --encryption-key provider:attestation-agent:sample=true docker://busybox oci:busybox_encrypted:sample
```

#### 示例 2：为 Offline fs KBC 加密

对于 `offline-fs-kbc`，省略 KBS 地址，并提前创建加密密钥。该密钥随后可以被预置到 KBS 中。

所以先创建一个随机的 32 字节密钥文件：

```shell
$ head -c32 < /dev/random > key1
```

使用路径为 `key1` 的密钥，以及 keyid `kbs:///default/key/key_id1` 来加密一个镜像。这样 sample 被禁用，并将使用 A256GCM（AES-256-GCM）：

```shell
$ skopeo copy --insecure-policy --encryption-key provider:attestation-agent:keypath=$(pwd)/key1::keyid=kbs:///default/key/key_id1::algorithm=A256GCM docker://busybox oci:busybox_encrypted:default
```

### 检视镜像

如果不确定镜像是否已加密，我们可以将镜像导出以检查它是否被加密。

上一节的示例一和示例二中，我们可以在当前目录下的 `busybox` 目录中找到 OCI 镜像。

> **注意** ：如果镜像被推送到仓库，请在下面的示例中使用 "docker://" 传输协议代替。

你可以使用 skopeo 的 *inspect* 命令打印镜像的底层信息：

```bash
$ skopeo inspect oci:busybox_encrypted:default
{
    "Digest": "sha256:28d649e5c1fb00b5a2cfdc8a0e95057a17addf80797ce2a6b45d89964b35b968",
    "RepoTags": [],
    "Created": "2023-05-11T22:48:43.533857581Z",
    "DockerVersion": "",
    "Labels": null,
    "Architecture": "amd64",
    "Os": "linux",
    "Layers": [
        "sha256:4d7ebe01f6574c525dc52ad6506d19aac1ad14eb783955cc1df93fda14073ae1"
    ],
    "LayersData": [
        {
            "MIMEType": "application/vnd.oci.image.layer.v1.tar+gzip+encrypted",
            "Digest": "sha256:4d7ebe01f6574c525dc52ad6506d19aac1ad14eb783955cc1df93fda14073ae1",
            "Size": 2590751,
            "Annotations": {
                "org.opencontainers.image.enc.keys.provider.attestation-agent": "eyJraWQiOiJrYnM6Ly8vZGVmYXVsdC9rZXkva2V5X2lkMSIsIndyYXBwZWRfZGF0YSI6IjNFZ1FidzZDUlY0YmlrMnNLM3RrTUpweWNWV0RVZXVIY1luZ1drZFd1K0swQXpDUGY3dFlCQ1oxSGxXaWFsZmdFdEQxdDBuc3N2YS81aElFbUxPbXZjYXJ2SGlNdERyRElhY1JIdElOTHFyUUpCZUY1M2Q4MTN1L0dDK3prL3RHeEF3ZVd6ZTR1S0VROG1qc2hyMytiYll3RUhKdVFyM3VncWlXRTlnNUhndU1HVmVFZ2ZReWR2dS9TZmVYMmZSeTRQWmtGcjhWbkQ3WjRrNUhXVkhaTWY0U21oSUhhUnlVa1NoT3B4dVdQcG54OW9IaGJSMEdKd2Zwb3l4TzRydEpYaTI4ODVxZ1Uya0dVaFo2RTJTbmgrQT0iLCJpdiI6IjRlekxiZU1RZEVrWS9pdUYiLCJ3cmFwX3R5cGUiOiJBMjU2R0NNIn0=",
                "org.opencontainers.image.enc.pubopts": "eyJjaXBoZXIiOiJBRVNfMjU2X0NUUl9ITUFDX1NIQTI1NiIsImhtYWMiOiJQM08rQ1lhRGNSNkJteEpvdWlFV0lYM05XN1l2Nk5UcEp5dmhlNlBmbFA4PSIsImNpcGhlcm9wdGlvbnMiOnt9fQ=="
            }
        }
    ],
    "Env": [
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    ]
}
```

我们可以看到该层的 `MIMEType` 为 `application/vnd.oci.image.layer.v1.tar+gzip+encrypted`，这意味着该层是加密的。

层的 `org.opencontainers.image.enc.keys.provider.attestation-agent` 注解包含（base64 编码的）所使用的加密参数，`org.opencontainers.image.enc.pubopts` 包含密码选项（cipher options）。这些会在解密过程中被 kbc 使用。

你可以像这样检视层注解的内容：

```bash
$ skopeo inspect oci:busybox_encrypted:default | jq -r '.LayersData[].Annotations."org.opencontainers.image.enc.keys.provider.attestation-agent"' | base64 -d
{"kid":"kbs:///default/key/key_id1","wrapped_data":"3EgQbw6CRV4bik2sK3tkMJpycVWDUeuHcYngWkdWu+K0AzCPf7tYBCZ1HlWialfgEtD1t0nssva/5hIEmLOmvcarvHiMtDrDIacRHtINLqrQJBeF53d813u/GC+zk/tGxAweWze4uKEQ8mjshr3+bbYwEHJuQr3ugqiWE9g5HguMGVeEgfQydvu/SfeX2fRy4PZkFr8VnD7Z4k5HWVHZMf4SmhIHaRyUkShOpxuWPpnx9oHhbR0GJwfpoyxO4rtJXi2885qgU2kGUhZ6E2Snh+A=","iv":"4ezLbeMQdEkY/iuF","wrap_type":"A256GCM"}
$ skopeo inspect oci:busybox_encrypted:default | jq -r '.LayersData[].Annotations."org.opencontainers.image.enc.pubopts"' | base64 -d
{"cipher":"AES_256_CTR_HMAC_SHA256","hmac":"P3O+CYaDcR6BmxJouiEWIX3NW7Yv6NTpJyvhe6PflP8=","cipheroptions":{}}
```

确保镜像已加密的另一种方法是使用 offline_fs_kbc 进行测试，这将在下一节描述。

## 解密（Decryption）

让我们展示如何解密在 [示例二](../../../../attestation-agent/coco_keyprovider#example-2-encrypting-for-offline-fs-kbc) 中创建的镜像。

构建并以 localhost 上的 gRPC 套接字运行机密数据中枢（CDH）：

```shell
$ cd confidential-data-hub
$ make KMS_PROVIDER=none RPC=grpc
$ cat <<EOF > cdh_conf.toml
socket = "127.0.0.1:48888"

[kbc]
name = "offline_fs_kbc"
url = ""
kbs_cert = ""
EOF
$ RUST_LOG=confidential_data_hub ../target/x86_64-unknown-linux-gnu/release/confidential-data-hub -c cdh_conf.toml &
```

新建一个 ocicrypt.conf 并重新导出 OCICRYPT_KEYPROVIDER_CONFIG：

```shell
$ cat <<EOF > ocicrypt.conf
{
  "key-providers": {
    "attestation-agent": {
      "grpc": "127.0.0.1:48888"
}}}
EOF
$ export OCICRYPT_KEYPROVIDER_CONFIG="$(pwd)/ocicrypt.conf"
```

确保密钥已记录在 `/etc/aa-offline_fs_kbc-keys.json` 中。在 [加密](../../../../attestation-agent/coco_keyprovider#encryption) 的示例二中，`"default/key/key_id1":"<base64-encoded-key>"` 应当被包含在 `/etc/aa-offline_fs_kbc-keys.json` 中：

```shell
$ cd attestation-agent/coco_keyprovider
$ ENC_KEY_BASE64="$(cat key1 | base64)"
$ cat <<EOF > aa-offline_fs_kbc-keys.json
{
  "default/key/key_id1": "${ENC_KEY_BASE64}"
}
EOF
$ sudo cp aa-offline_fs_kbc-keys.json /etc/
```

解密镜像：

```shell
$ skopeo copy --insecure-policy --decryption-key provider:attestation-agent:offline_fs_kbc::null oci:busybox_encrypted:default oci:busybox_decrypted
```

解密后的镜像其层的 `MIMEType` 应当为 `application/vnd.oci.image.layer.v1.tar+gzip`，如下：

```shell
$ skopeo inspect oci:busybox_decrypted | jq -r '.LayersData[].MIMEType'
application/vnd.oci.image.layer.v1.tar+gzip
```

## 相关工具

### 测试密钥生成与 Offline-Fs-KBC

`tools/generate_keys.sh` 是一个辅助脚本，用于生成十个不同的 base64 编码 KEK。同时，它还可以帮助生成 offline-fs-kbc 使用的 `aa-offline_fs_kbc-keys.json`。
**警告**：需要 `jq`，因此使用前请先安装 jq。例如在 ubuntu 上，`apt install jq` 即可。

#### 生成 `aa-offline_fs_kbc-keys.json`

```bash
tools/generate_keys.sh generate > aa-offline_fs_kbc-keys.json
```

你将得到一个随机生成的 `aa-offline_fs_kbc-keys.json`，类似如下内容：
```
{
  "default/key/key_id7": "gH4b2MYb/lGrYRVmrf3qtNo46mzC6C87cN5hdRt+Wvg=",
  "default/key/key_id6": "cemWcxJw9fG11Y3WhrzcZNKBWebdFt7qQDsIa6h6kJI=",
  "default/key/key_id10": "FePQCdgX/UONTIOl6eQP+7Itq5fdwr8JPufkmypbMWI=",
  "default/key/key_id5": "uDAikSR/Hadk7RXkA86DBsQs8eekP/dkLkXyuVjyLf8=",
  "default/key/key_id4": "5PN33vLpX+UO82Ryl/BhZNm5+suhTrBEqdWTDi1wqVU=",
  "default/key/key_id3": "Y8ptYp5WgJxXdhe5tIS+ZIoSlVup1DUHu63MyHOsxsA=",
  "default/key/key_id2": "sIDb9K+J7IEfYQMbcDzEYz8t+hABQlHSR+55SIAgsUw=",
  "default/key/key_id1": "TfyYGL/gBbtXwgDmx3a6N6WxFJFamcSRUFlpBPXu0f4=",
  "default/key/key_id9": "CfGZPsmKq1pkzraBpMAsbBZGIGlbWUepu4eR/Z4exnE=",
  "default/key/key_id8": "eXIlv83nTjfyeLZcCvTda9ypYIYj83eGjbqjoVFAQHA="
}
```

#### 使用生成的密钥加密镜像

如果我们想使用 `aa-offline_fs_kbc-keys.json` 中 id 为 `default/key/key_id1` 的密钥来加密镜像，我们首先把密钥内容导出到文件 `key1`

```
tools/generate_keys.sh export aa-offline_fs_kbc-keys.json default/key/key_id1 key1
```

> **警告** ：因为在当前代码中，我们并未真正使用 KBS 资源 URI 中的 `<kbs-addr>`。当使用 skopeo 加密镜像时，我们可以以 `kbs:///<repo>/<type>/<tag>` 格式指定 `keyid`，例如 `kbs:///default/key/key_id1`。
