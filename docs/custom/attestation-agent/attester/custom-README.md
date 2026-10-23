# Attester 插件

本 crate 为不同平台提供 attester 插件。一个 [attester](https://www.rfc-editor.org/rfc/rfc9334.html#section-7.2) 插件可以提供以下能力：

- 获取远程证明证据（remote attestation evidence）。
- 扩展运行时度量（extend runtime measurement）。
- 检查 initdata 绑定。

## 证据获取工具（Evidence Getter Tool）

本 crate 提供了一个简单工具，用于检测当前平台类型并根据给定的 report data 获取对应的 quote。

使用默认特性或指定某个 TEE attester 支持（例如 `tdx-attester`）来构建二进制：
```shell
git clone https://github.com/confidential-containers/guest-components.git
cd guest-components/attestation-agent/attester

cargo build --features=bin --bin evidence_getter --release

cargo build --no-default-features --features bin,tdx-attester --bin evidence_getter --release
```

获取证据
```shell
echo $EVIDENCE_STRING | ../../target/release/evidence_getter stdio
```

这里的 `$EVIDENCE_STRING` 是一段最多 64 字节的字符串/字节。
（某些平台可能对证据有平台特定的长度限制）

## 为证据添加 TPM quote

通过以下命令搭建一个 TPM 模拟器：

```sh
sudo modprobe tpm_vtpm_proxy
mkdir -p /tmp/tpmdir

swtpm_setup --tpm2 \
            --tpmstate /tmp/tpmdir \
            --createek --decryption \
            --create-ek-cert \
            --create-platform-cert \
            --pcr-banks - \
            --display

swtpm chardev --tpm2 \
              --tpmstate dir=/tmp/tpmdir \
              --vtpm-proxy \
              --daemon \
              --log file=/tmp/tpmdir/tpm.log,level=20 \
              --flags not-need-init
```

这会创建一个 tpm 设备，例如 `/dev/tpm0`

注意：如果 TPM 设备不是 `/dev/tpm0`，你需要在运行 tpm 命令时通过添加以下参数显式指定设备 `-T device:/dev/tpmN`

### TPM 证明密钥（AK）配置

TPM attester 需要在持久的句柄（persistent handle）上预置一个证明密钥（AK）。默认情况下，attester 在句柄 `0x81010002` 处查找 AK。

要在默认句柄上配置 AK：

```sh
# 使用位于 0x81010001 的 EK 上下文创建 AK
tpm2_createak -C 0x81010001 -c ak.ctx -G rsa -g sha256 -s rsassa -u ak.pub -f pem
# 将 AK 持久化到句柄 0x81010002
tpm2_evictcontrol -c ak.ctx 0x81010002
```

你可以通过设置 `AA_TPM_AK_HANDLE` 环境变量，让 attester 使用不同的 AK 句柄：

```sh
export AA_TPM_AK_HANDLE=0x81010003
```

如果你想读取并扩展示例 PCR 用于测试，可以使用以下命令：

```sh
# 读取所有 PCR
tpm2_pcrread

# 读取指定的 PCR（例如 11）
tpm2_pcrread sha256:11

# 扩展 PCR 11
tpm2_pcrextend 11:sha256=6ea40aa7267bb71251c1de1c3605a3df759b86b22fa9f62aa298d4197cd88a3
```

获取 TPM quote，运行以下命令：

```sh
../../target/release/evidence_getter commandline 12345678
```
