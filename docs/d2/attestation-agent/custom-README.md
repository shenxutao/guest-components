# 证明代理（Attestation Agent）

证明代理（简称 AA）是机密容器（Confidential Containers）中用于证明（attestation）流程的一组服务功能。它提供多种与证明相关的服务 API。

AA 当前的消费者包括：

- [confidential-data-hub](../../../confidential-data-hub)（其 `cc_kbc` KBC 插件使用 AA 来执行证明并获取 token；随后它用该 token 直接调用 KBS 的 `GetResource` API）

AA 不再直接对接 `ocicrypt-rs`/`image-rs` 进行镜像解密；该流程现在由 `confidential-data-hub` 处理。详见 [IMAGE_ENCRYPTION.md](../../../attestation-agent/docs/IMAGE_ENCRYPTION.md) 和 [IMPLEMENTATION.md](../../../attestation-agent/docs/IMPLEMENTATION.md)。

## 组件

AA 的主体是一个 Rust 库（library）crate，其中包含用于生成 TEE 证据（evidence）并与 KBS 协商证明 token 的 attester 模块。此外，本项目还提供一个 gRPC/ttRPC 服务应用，允许调用方（例如 `confidential-data-hub`）调用 AA 提供的服务。

## 库 crate

在你的项目 `Cargo.toml` 中引入 AA，并支持全部平台：

```toml
attestation-agent = { git = "https://github.com/confidential-containers/guest-components", features = ["all-attesters"] }
```

**注意**：待版本稳定后，我们会在 https://crate.io 上发布 AA。

## 服务应用

### ttRPC（默认）

#### 构建

使用默认 attester 构建并安装：

```shell
git clone https://github.com/confidential-containers/guest-components
cd guest-components/attestation-agent
make && make install
```

或者显式指定平台。以 `tdx` 为例：

```shell
make ATTESTER=tdx-attester
```

不依赖任何平台支持：

```shell
make ATTESTER=none
```

使用 `all-attesters` 特性集：

```shell
make ATTESTER=all-attesters
```

#### Musl

使用 musl 构建并安装：

```shell
make LIBC=musl && make install LIBC=musl
```

#### 运行

查看帮助信息：

```shell
attestation-agent --help
```

ttRPC 版 AA 仅支持 Unix 套接字，例如：

```shell
attestation-agent --attestation_sock unix:///tmp/attestation.sock
```

查看运行时日志：

```shell
RUST_LOG=attestation_agent attestation-agent --attestation_sock unix:///tmp/attestation.sock
```

### gRPC

构建并安装 gRPC 版的证明代理：

```shell
make ttrpc=false && make install
```

使用 TCP 端点运行：

```shell
attestation-agent --attestation_sock 127.0.0.1:50002
```

### 支持的平台

AA 支持多种硬件 TEE attester，目前包括：
| Attester 名称      |           说明              |
| ------------------- | --------------------------  |
| tdx-attester        | Intel TDX                   |
| tdx-attester-libtdx | Intel TDX（针对某些非上游的 Linux `ioctl()` 使用 libtdx-attest）。默认禁用。 |
| sgx-attester        | Intel SGX DCAP              |
| snp-attester        | AMD SEV-SNP                 |
| az-snp-vtpm-attester| Azure SEV-SNP CVM           |
| az-tdx-vtpm-attester| Azure TDX CVM               |
| cca-attester        | Arm 机密计算架构（CCA）  |
| se-attester         | IBM Secure Execution (SE)   |

要构建并安装包含所有可用 attester 的 AA，使用
```shell
make ATTESTER=all-attesters && make install
```
