机密数据中枢（CDH）提供资源服务，例如从密钥代理服务（KBS）获取解密密钥和策略文件。

当前工作负载可以通过 CDH 从以下提供方获取资源：

* [CoCo KBS](https://github.com/confidential-containers/trustee/tree/main/kbs)

CDH 服务应当配置为以下密钥代理客户端（KBC）之一，由它们建立与提供方的接口：

* `cc_kbc` - 用于 CoCo KBS
* `offline_fs_kbc` - 用于从系统的本地文件系统读取

关于配置 CDH 的更多信息，请参考 [README.md](../../../../confidential-data-hub/README.md) 中的 [配置章节](../../../../confidential-data-hub/README.md#configuration-file)。

## 用法

建议用户通过 [CoCo RESTful API 服务](../../../../api-server-rest/README.md) 访问 CDH 服务，因此需要确保 API 服务和 CDH 进程都在本地主机上运行。默认情况下 API 服务监听 `8006` 端口，而资源通过 `cdh/resource` 端点以 HTTP 方式提供。

例如，假设 CDH 配置了 `cc_kbc`，要从 `default` 仓库获取标签为 `1` 的密钥 `key`：

```
$ curl http://127.0.0.1:8006/cdh/resource/default/key/1
```

注意，CoCo Pod 也能访问该 API 服务，因为容器与 CDH/API-server 进程属于同一个网络命名空间。因此，从 Pod 中读取资源应当就像向 CDH 端点发送一条 HTTP GET 请求一样简单，如下面的部署示例所示：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: cdh-example
spec:
  runtimeClassName: kata-qemu-tdx
  containers:
    - name: bash-curl
      image: storytel/alpine-bash-curl:latest
      imagePullPolicy: Always
      command:
        - sh
        - -c
        - |
          curl http://127.0.0.1:8006/cdh/resource/default/key/1; tail -f /dev/null
```

## 示例：offline_fs_kbc

在本示例中，我们将使用 `offline_fs_kbc` KBC 从本地文件系统获取资源。运行此示例既不需要 TEE 硬件，也不需要虚拟机或 Kubernetes。

出于历史与向后兼容的原因，`offline_fs_kbc` 会从 **/etc/aa-offline_fs_kbc-keys.json** 和 **/etc/aa-offline_fs_kbc-resources.json** 两个文件中读取键值对。这里我们仅使用 **/etc/aa-offline_fs_kbc-resources.json**。

首先，构建 CDH。为了加快构建速度，禁用所有 KMS provider，仅启用 KBS 资源提供方：

```shell
$ make KMS_PROVIDER=none
```

创建资源文件（**/etc/aa-offline_fs_kbc-resources.json**）并添加 **default/key/1** 这个键（其值应以 base64 编码）：

```json
{
  "default/key/1": "HUlOu8NWz8si11OZUzUJMnjiq/iZyHBJZMSD3BaqgMc="
}
```

创建 CDH 配置文件（**cdh_conf.toml**）：

```toml
socket = "unix:///run/confidential-containers/cdh.sock"

[kbc]
name = "offline_fs_kbc"
url = ""
kbs_cert = ""
```

在后台启动 CDH：

```shell
$ sudo ../target/x86_64-unknown-linux-gnu/release/confidential-data-hub -c cdh_conf.toml &
```

接着，构建并启动 API 服务：

```shell
$ make -C ../api-server-rest
$ sudo ../target/x86_64-unknown-linux-gnu/release/api-server-rest --features=resource &
```

最后，我们可以从 CDH 获取资源 **default/key/1** 这个键：

```shell
$ key=$(curl -s http://127.0.0.1:8006/cdh/resource/default/key/1 | base64)
root_path /cdh, url_path /resource/default/key/1
[2024-03-22T14:43:55Z INFO  confidential_data_hub::hub] get resource called: kbs:///default/key/1
$ echo $key
HUlOu8NWz8si11OZUzUJMnjiq/iZyHBJZMSD3BaqgMc=
```

注意上面输出中，服务返回的是原始密钥值，即它已经做了 base64 解码。
