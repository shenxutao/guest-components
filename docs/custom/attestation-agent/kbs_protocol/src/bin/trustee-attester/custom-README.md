# Trustee attester（Trustee 证明器）

一个用于向 Trustee 进行证明（attest）并获取密钥的工具。

Trustee attester 是 [confidential-containers](https://github.com/confidential-containers) 的 [guest-components](https://github.com/confidential-containers/guest-components) 项目的一部分，但也可以用于机密虚拟机。

Trustee attester 使用 attestation-agent 的 kbs_protocol 客户端和 attesters 来收集基于硬件的机密计算证据，并将其发送给 Trustee。

在 trustee-attester 运行之前，必须将一个路径完全相同的资源上传到 Trustee。

## 构建

```bash
cargo build -p kbs_protocol --bin trustee-attester --no-default-features
--features "background_check,passport,bin,<attesters-list>"
```

## 运行

```bash
$ trustee-attester --url <Trustee-URL> [--cert-file <path>] get-resource --path <resource-path> [--initdata <initdata>]
```

## 示例

```bash
$ trustee-attester --url http://localhost:50000 get-resource --path default/keys/dummy
```
