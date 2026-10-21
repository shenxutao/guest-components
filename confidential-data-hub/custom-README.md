# 机密数据中枢（Confidential Data Hub）

机密数据中枢（`CDH`）是一个运行在 guest 内部、提供资源相关 API 的服务。

### API

API 定义在 [proto 文件](../protos/protos/confidential-data-hub) 中。

注意，CDH 支持对加密镜像进行解密。当 `OCICRYPT_KEYPROVIDER_CONFIG` 未设置时，CDH 会写入一份默认的 ocicrypt keyprovider 配置，将 `attestation-agent` provider 映射到 CDH 自己的套接字（来自 CDH 配置）。运维人员仍然可以通过把 `OCICRYPT_KEYPROVIDER_CONFIG` 指向自定义文件来覆盖，例如：

```shell
OCICRYPT_KEYPROVIDER_CONFIG=<path-to-ocicrypt_config.json> confidential-data-hub
```

一份示例配置文件位于 [hub/src/image/ocicrypt_config.json](./hub/src/image/ocicrypt_config.json)。

### 构建

使用默认特性构建并安装：

```shell
git clone https://github.com/confidential-containers/guest-components
cd guest-components/confidential-data-hub
make
```
这会构建启用了 `kbs` 且 `KMS_PROVIDER=aliyun` 的 CDH。

你可以在构建时显式指定 KMS_PROVIDER 插件。例如，如果你只想包含 `aliyun` 这一个 KMS_PROVIDER：

```shell
make KMS_PROVIDER=aliyun
```

如果你想不引入任何 KMS_PROVIDER（仍然保留 `cc_kbc` / CoCo KBS）：
```shell
make KMS_PROVIDER=none
```

如果你只想要内置的 `offline_fs_kbc`（不带 `cc_kbc`）：
```shell
make ENABLE_KBS=false
```

默认的 CDH 作为一个服务守护进程运行。如果你想把 CDH 构建成一个一次性（one-shot）二进制（运行一次即退出），使用参数 `ONE_SHOT=true`
```shell
make ONE_SHOT=true
```

可选项请参考 [支持的特性](#支持的特性)。

### 支持的特性

CoCo KBS / `cc_kbc`（参数 `ENABLE_KBS`）

| 取值  | 说明                                                                 |
| ------ | -------------------------------------------------------------------- |
| true   | 启用 cargo 特性 `kbs`（使用 KBS 证明协议的 `cc_kbc`）。默认值。 |
| false  | 不构建 `cc_kbc`。`offline_fs_kbc` 仍然可用。         |

注意：
- 省略 `ENABLE_KBS` 即保持默认（`true`）。仅在需要禁用时才设置它。

KMS_PROVIDER 插件（参数 `KMS_PROVIDER`）

| 特性名 | 说明                                                        |
| ------------ | ----------------------------------------------------------- |
| aliyun       | 使用阿里云 KMS 来密封（seal）与解封（unseal）密钥。           |
| aws          | 使用 AWS KMS 和 Secrets Manager 处理机密密钥。   |

注意：
- 如果没有给出 `KMS_PROVIDER` 参数，默认启用 `aliyun`。

RPC 插件（参数 `RPC`）
| 特性名        |           说明                                                     |
| ------------------- | -----------------------------------------------------------------  |
| grpc                | 使用 grpc API 提供服务（TCP/IP 套接字）。                |
| ttrpc               | 使用 ttrpc API 提供服务（Unix 套接字）。                 |

安全挂载（Secure mount）插件（参数 `STORAGE`）

注意：
- 如果没有给出 `STORAGE` 参数，则默认启用所有 STORAGE 插件。

### 配置文件

CDH 通过配置文件启动：
```shell
confidential-data-hub -c <path-to-config>
```

更多细节请参见 [toml](./example.config.toml) 或 [json](./example.config.json) 格式的示例配置文件。

不过，如果没有通过 **-c** 传入文件，则会按以下顺序搜索配置（依次）：

* **/etc/confidential-data-hub.conf**
* **AA_KBC_PARAMS** 环境变量
* 内核命令行（`/proc/cmdline`）中的 **agent.aa_kbc_params** 参数

有一个特殊情况：当从 [peer pods](https://github.com/confidential-containers/cloud-api-adaptor) 运行时，会在查找 `aa_kbc_params` 之前，先尝试从 kata-agent 文件（**/etc/agent-config.toml** 或 **KATA_AGENT_CONFIG_PATH** 环境变量）读取。

最后，在完全没有配置的情况下，CDH 会以 `offline_fs_kbc` 密钥代理客户端（KBC）进行配置。

### 客户端工具

提供了一个与 CDH 交互的客户端工具。

#### ttRPC 客户端工具

运行以下命令构建
```shell
git clone https://github.com/confidential-containers/guest-components
cd guest-components/confidential-data-hub/hub
cargo build --bin ttrpc-cdh-tool --features bin,ttrpc
```

安装
```shell
install -D -m0755 ../../target/x86_64-unknown-linux-gnu/release/ttrpc-cdh-tool /usr/local/bin/ttrpc-cdh-tool
```

#### gRPC 客户端工具

运行以下命令构建
```shell
git clone https://github.com/confidential-containers/guest-components
cd guest-components/confidential-data-hub/hub
cargo build --bin grpc-cdh-tool --features bin,grpc
```

安装
```shell
install -D -m0755 ../../target/x86_64-unknown-linux-gnu/release/grpc-cdh-tool /usr/local/bin/grpc-cdh-tool
```
