# 机密容器工具与组件

[![FOSSA 状态](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fconfidential-containers%2Fimage-rs.svg?type=shield)](https://app.fossa.com/projects/git%2Bgithub.com%2Fconfidential-containers%2Fimage-rs?ref=badge_shield)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/confidential-containers/guest-components/badge)](https://scorecard.dev/viewer/?uri=github.com/confidential-containers/guest-components)

本仓库包含用于机密容器镜像的工具与组件。

## 组件（Components）

[Attestation Agent（证明代理）](attestation-agent)
用于支撑远程证明协议的代理。
可作为库构建以在基于进程的机密沙箱中运行，也可作为进程构建并运行在机密虚拟机内部。

[image-rs](image-rs)
容器镜像管理库的 Rust 实现。

[ocicrypt-rs](ocicrypt-rs)
OCI 镜像加密库的 Rust 实现。

[api-server-rest](api-server-rest)
CoCo（Confidential Containers）RESTful API 服务。

[confidential-data-hub（机密数据中枢）](confidential-data-hub)
Confidential Data Hub（CDH）。

[coco-keyprovider](attestation-agent/coco_keyprovider/)
CoCo 密钥提供器。用于加密容器镜像。

## 工具（Tools）

[secret-cli](confidential-data-hub/docs/SEALED_SECRET.md)
用于密封（seal）与解封（unseal）sealed secret 的工具。

[CDH Client](confidential-data-hub/README.md#client-tool)
用于调用 CDH 端点的工具。

[CDH（One Shot）](confidential-data-hub)
CDH 的单次运行（One Shot）版本。

[CoCo Keyprovider](attestation-agent/coco_keyprovider)
用于加密镜像的密钥提供器端点。

## 构建（Build）

仓库提供了 `Makefile`，可针对指定平台快速构建 Attestation Agent / Api Server Rest / Confidential Data Hub。

```shell
make build TEE_PLATFORM=$(TEE_PLATFORM)
make install DESTDIR=/usr/local/bin
```

`TEE_PLATFORM` 参数可取以下值：
- `none`：用于非机密 guest 的测试
- `all`：涵盖以下所有平台
- `fs`：使用加密根文件系统的平台（如 s390x）
- `tdx`：Intel TDX
- `az-tdx-vtpm`：使用 Azure vTPM 的 Intel TDX
- `snp` / `amd`：AMD SEV-SNP
- `az-snp-vtpm`：使用 Azure vTPM 的 AMD SEV-SNP
- `se`：IBM Secure Execution（SE）

默认情况下，Confidential Data Hub 会启用 `kbs` 特性（`cc_kbc` / CoCo KBS）。`offline_fs_kbc` 始终会被构建。若要在不启用 `cc_kbc` 的情况下构建，可设置 `ENABLE_KBS=false`：

```shell
make build TEE_PLATFORM=$(TEE_PLATFORM) ENABLE_KBS=false
```

### 可选构建参数

ttRPC 与 gRPC 的 protobuf 代码可通过以下命令重新生成：

```shell
make build-protos
```

## 许可证（License）

[![FOSSA 状态](https://app.fossa.com/api/projects/git%2Bgithub.com%2Fconfidential-containers%2Fimage-rs.svg?type=large)](https://app.fossa.com/projects/git%2Bgithub.com%2Fconfidential-containers%2Fimage-rs?ref=badge_large)
