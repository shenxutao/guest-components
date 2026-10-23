# 真海光 CSV 服务器部署指南（D2 收尾 / 生产验明）

> 本文是 `custom-D2连调runbook.md` **步骤 8** 的展开。runbook 在腾讯云普通 VM 上验证过的编译 / 启动 / 管道逻辑**全部复用**——本文只写真机专属部分，避免与测试 VM 文档重复。
> 适用：在海光 CSV 机密 VM 内部署 guest 组件（AA / CDH / ASR），用 `csv` attester 出真证据，经 Trustee/KBS 验明，并接 kata-runtime。

## 0. 适用范围与前置

**目标**：把 D2 在测试 VM 上跑通的集成管道，搬到真海光 CSV 环境，达成**真实机密证明**（非桩）。

**前置（测试 VM 没有，需先具备）**：

1. **海光 CSV 硬件** + 支持 CSV 的内核，guest 内存在 `/dev/csv-guest`（CSV attester 的度量读取入口）。
2. 已构建的**静态二进制**：`make build TEE_PLATFORM=csv LIBC=musl`。
3. 真 **Trustee / KBS** 服务（`https://<kbs>`），支持 RCAR / Passport 验明。
4. **kata-runtime**（vsock + gRPC，非 HTTP）打通 guest 内 AA/CDH 与宿主 Trustee。
5. CSV attester 与 Trustee verifier 的 **`kbs-types` 协议字段对齐**（跨仓协调，属 D2 收尾项；字段级对齐清单见 `custom-CSV证据与Trustee对齐.md`）。

## 1. 系统准备（复用测试 VM）

- 同 runbook 步骤 0：`bash scripts/setup-server.sh`（Ubuntu x86_64，装 Rust 工具链 + 编译依赖）。
- 区别：真机是**机密 VM**，OS 已由 CSV 镜像提供，通常只需装工具链与编译依赖（脚本同样适用），无需重装系统。
- 确认 CSV 设备存在：
  ```bash
  ls -l /dev/csv-guest          # 应存在；不存在说明内核/硬件未启 CSV
  ```

## 2. 构建（真机口径）

```bash
# 静态、只编 CSV attester（csv-attester 已接入 Makefile :34-37，D2-M1 完成）
make build TEE_PLATFORM=csv LIBC=musl
# 产物：./target/x86_64-unknown-linux-musl/release/{confidential-data-hub,attestation-agent,api-server-rest}
```

与测试 VM（`TEE_PLATFORM=all LIBC=gnu`）的差异只有两点：**attester 选 `csv`**，链接用 **musl 静态**（便于打进 guest 镜像）。

## 3. KBC 指向真 KBS

```bash
# 走真 HTTP(S) KBS（RCAR 挑战-应答），替换测试 VM 的 offline_fs_kbc::null
export AA_KBC_PARAMS="cc_kbc::https://<真KBS地址>"

# 若 Trustee 同时提供 offline_fs 形态的资源端点，也可：
# export AA_KBC_PARAMS="offline_fs_kbc::https://<kbs>/resource"
```

对应 runbook 步骤 4 的替换项；`cc_kbc` 的客户端 HTTP 行为可在测试 VM 用 mock KBS（runbook 步骤 7）提前验证。

## 4. sealed secret 密钥预置（机密 VM 内）

- 验签公钥**不再手搓本地文件**，而由**机密 VM 启动时**预置到 `SIGNING_CREDENTIALS_PATH = /run/confidential-containers/cdh/sealed-secret/<kid>`（机制见 `custom-CDH-SealedSecret.md`）。
- `kid` 可改为 **KBS URI**（`kbs:///...`），此时 `get_kid` 经 KMS getter 从 Trustee 取公钥——这是跨仓 `kbs-types` 对齐的关键点之一。
- 信封格式、Vault / Envelope 类型、解封逻辑与测试 VM **完全一致**，无需改动代码。

## 5. CSV 证据链路（核心差异）

- AA 用 `csv` attester 打开 `/dev/csv-guest`，读取 CSV 度量报告（含 launch measurement 与签名）。
- 流程：客户端请求 `AA evidence` → AA 返回 CSV 报告 → 经 **RCAR 挑战-应答**由 Trustee verifier 验明。
- 验证：
  ```bash
  curl -s "http://127.0.0.1:8006/aa/evidence?runtime_data=test"
  # 应返回真实 CSV 报告（非桩）；Trustee 侧验明通过
  ```
- 对应 runbook 6.4 的「桩」在此变为**真值**。

## 6. kata-runtime 接入

- kata-runtime 以 **vsock + gRPC**（非 HTTP）连接 guest 内 AA/CDH 与宿主 Trustee——这是测试 VM 验不了、真机必须的一环。
- 拉起机密容器，确认 guest 内组件与宿主 Trustee 经 vsock 互通，资源 / 证据请求可达。

## 7. 端到端验证检查表

- [ ] `/dev/csv-guest` 可读，AA `csv` attester 能产出报告。
- [ ] `make build TEE_PLATFORM=csv LIBC=musl` 静态产物就绪。
- [ ] `AA_KBC_PARAMS=cc_kbc::https://<kbs>` 下，资源经真 KBS 取回（对应 runbook 6.1 / 6.2）。
- [ ] sealed secret 公钥预置到位，解封成功（对应 runbook 6.3）。
- [ ] Trustee verifier 对 CSV 证据验明通过（RCAR 端到端）。
- [ ] kata-runtime 拉起机密容器，vsock 互通。
- [ ] ASR `/info` 显示 `tee=csv`、feature 含 `csv-attester`。

## 8. 与 D2 其余部分的关系

- CSV attester 源码（guest 侧）在 `attestation-agent/attester/csv/`；Makefile 映射已打通（D2-M1 完成），可直接 `TEE_PLATFORM=csv`。
- 真验明依赖 **Trustee 仓库（D4）** 的 CSV verifier + `kbs-types` 对齐，属跨仓协调，列为第 0 节前置。
- 本地测试 VM 上跑通的一切（runbook 步骤 0–7）是真机部署的**前置演练**，逻辑直接复用，无需重写。

## 参考文件

- `custom-D2连调runbook.md`（测试 VM 全流程；步骤 8 迁移映射表）
- `custom-CDH-SealedSecret.md`（信封格式与 `secret` 工具）
- `Makefile`（`:34-37` `csv → csv-attester` 映射）
- `attestation-agent/attester/csv/mod.rs`（CSV attester 实现）
- `attestation-agent/attestation-agent/src/config/aa_kbc_params.rs`（KBC 参数解析）
- `confidential-data-hub/hub/src/secret/mod.rs`（sealed secret 验签与 `kid` 寻址）
