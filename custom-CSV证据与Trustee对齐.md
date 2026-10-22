# CSV 证据格式与 Trustee verifier 的 kbs-types 对齐（D2 ↔ D4 跨仓协调）

> 本文是 `custom-真机CSV部署.md` 第 0 节「前置 5」的**字段级展开**：D2（guest-components，CSV attester）产出的证据，要被 D4（Trustee 仓库）的 CSV verifier 正确验明，两端必须对齐的协议点都在这里。属 D2 收尾的跨仓协调项。
> 所有字段以 guest-components 当前源码为准；标注「（确认）」的来自外部 `kbs-types = "0.18.0"` / `csv_rs`，以该版本实际定义为准。

## 1. 证据从哪来（CSV attester 输出）

实现见 `attestation-agent/attester/src/csv/mod.rs`。

### 1.1 `CsvEvidence` 结构（序列化为 `TeeEvidence = serde_json::Value`）

```text
CsvEvidence {
  attestation_report: AttestationReportWrapper   # csv_rs 的硬件报告封装
  cert_chain: CertificateChain {
    hsk_cek: Option<HskCek { hsk, cek }>         # 仅当 CSV_INCLUDE_CERT_CHAIN_ENV=true
    pek: csv::Certificate                        # 报告签名者 PEK 证书（必含）
  }
  serial_number: Vec<u8>                         # base64 编码的 CSV 序列号 = 海光 chip_id
  cc_eventlog: Option<String>                    # CCEL / AAEL（TCG2 编码）base64，可选
}
```

- `serial_number` 用于标识海光芯片，也是去 KDS 取 HSK/CEK 的索引（`?snumber=`）。
- `cc_eventlog` 来自 `read_eventlog()`（CCEL 表 / AAEL），供 verifier 校验度量日志。

### 1.2 `get_evidence(report_data)` 契约

- 入参 `report_data` **必须 ≤ 64 字节**，否则 `bail!`（`csv/mod.rs:97-99`）；内部 `resize(64, 0)` 后写入 `CsvGuest::get_report_ext(...)`。
- 这条 `report_data` 就是 **verifier 下发的挑战（challenge / nonce）**，会被海光硬件写进 `AttestationReport` 并由 PEK 签名 → 实现**抗重放 + 会话绑定**。verifier 必须校验报告里的 `report_data` 与下发的挑战一致。
- 这是 RCAR 握手的核心：challenge 由 Trustee 生成，evidence 回带被签名的 challenge。

### 1.3 证书链来源约定（`CSV_INCLUDE_CERT_CHAIN_ENV`）

- 默认（env ≠ "true"）：`cert_chain` 只含 `pek`；**HSK/CEK 由 verifier 自行从 KDS 拉取**：
  `https://cert.hygon.cn/hsk_cek?snumber=<chip_id>`（`csv/mod.rs:67-92`）。
- 设 `CSV_INCLUDE_CERT_CHAIN_ENV=true`：attester 主动把 HSK/CEK 下载并内嵌进 `hsk_cek`。
- **两端必须就「谁去取 HSK/CEK」达成一致**：若 verifier 不连 KDS 又没内嵌，验签链断裂。

### 1.4 RTMR / 度量寄存器

- `supports_runtime_measurement() -> true`：支持运行时度量扩展（`extend_runtime_measurement`）与读取（`get_runtime_measurement`）。
- `pcr_to_ccmr` 映射（`:167-175`）：PCR0→CCMR0；PCR1/7→CCMR1；PCR2–6→CCMR2；PCR8–15→CCMR3；其余→CCMR4。
- `ccel_hash_algorithm() -> HashAlgorithm::Sm3`（`:177-179`）：CCEL / eventlog 的哈希用 **SM3**，verifier 须用 SM3 重建并比对 CCMR。

## 2. 跨仓共享的 kbs-types 类型（桥）

`kbs-types = "0.18.0"` 是 workspace 固定依赖（`Cargo.toml:49`），guest-components 与 Trustee **必须版本兼容**，否则下列类型字段漂移。

| 类型 / 字段 | 在 guest 侧用途 | 对齐要求 |
|---|---|---|
| `kbs_types::Tee::Csv` | AA `Tee` 派发标签（lib.rs 用 `Tee::Tdx` 等同款）；verifier 据此选 CSV 分支 | 两端共用同一 `Tee::Csv` 变体，作为 CSV 证据的识别标签 |
| `kbs_types::HashAlgorithm::Sm3` | CSV 的 CCEL 哈希算法（`csv/mod.rs:177`） | verifier 重建 CCEL 哈希时用 `Sm3`，不能用 SHA |
| `kbs_types::Response` / `Challenge` | RCAR 信封：`Response{ tee, tee-pubkey, tee-evidence, runtime-data }` 包住证据与挑战（**确认**：以 0.18.0 实际定义为准） | 信封字段名/结构两端一致；`tee-evidence` 装的就是上面的 `CsvEvidence` JSON |

> 注意：`CsvEvidence`、`AttestationReportWrapper`、`csv::Certificate` 这些**不在 kbs-types 里**——它们定义在 guest-components（或 `csv_rs`）。`kbs-types` 只桥接 `Tee` / `HashAlgorithm` / `Response` / `Challenge` 等通用信封。**真正的证据 JSON 形状是 D2↔D4 的隐式契约**，改字段名/结构须双向通知。

## 3. Trustee verifier 必须实现的校验（对齐清单）

逐项即 D4 侧 CSV verifier 的责任，也是 D2 这边要保证「产出的东西可被这样验」：

- [ ] 按 `tee == Tee::Csv` 派发到 CSV 验证分支，反序列化 `CsvEvidence`（字段同 §1.1）。
- [ ] 证书链：从 `pek` 起，向上到 HSK/CEK（内嵌或经 KDS `cert.hygon.cn`），再到海光根 CA；校验 PEK 证书链与签名。
- [ ] **挑战绑定**：报告中的 `report_data` 必须等于本会话下发的 challenge（防重放）。
- [ ] 报告完整性 / 签名由硬件 PEK 验过（`AttestationReportWrapper` 解析由 `csv_rs` 提供，两端须用兼容的 `csv_rs`）。
- [ ] CCEL / eventlog（`cc_eventlog`）用 **SM3** 重建哈希，与报告/CCMR 中的度量值比对。
- [ ] 若 guest 侧用 `extend_runtime_measurement` 扩展了运行时度量，verifier 须按 **§1.4 的 `pcr_to_ccmr` 映射** 比对对应 CCMR 值。
- [ ]（若启用）`CSV_INCLUDE_CERT_CHAIN_ENV` 的取值两端一致，避免「verifier 等内嵌却只收到 pek」或反之。

## 4. 协调风险与变更控制（C1 契约）

- **`kbs-types` 字段变更**：必须**先与 D4 协调**（见 `custom-项目理解.md` 第 32、440 行）——它跨项目共享，版本 `0.18.0`，任意一侧改 `Tee` / `HashAlgorithm` / `Response` / `Challenge` 都会让另一端验明失败。
- **`CsvEvidence` 隐式契约**：虽不经过 kbs-types，但 verifier 依赖其字段；D2 改 `csv/mod.rs` 的 `CsvEvidence` 须同步通知 D4。
- **`csv_rs` 报告格式**：`AttestationReportWrapper` / `AttestationReport` 由海光 `csv_rs` 定义，Trustee 侧解析须用兼容版本（否则报告解不开）。
- 建议：在 `Tee::Csv` 分支一旦定稿，把 `CsvEvidence` 的 JSON schema 作为 D2/D4 共同文档固化（即本文 §1.1），变更走评审。

## 5. 本地（测试 VM）能核对什么、不能核对什么

- 能：确认 `Tee::Csv` / `HashAlgorithm::Sm3` 在 `kbs-types` 0.18.0 中存在、CSV attester 代码路径、字段命名、`CSV_INCLUDE_CERT_CHAIN_ENV` 行为、`pcr_to_ccmr` 映射——这些都**不依赖硬件**，可静态核对。
- 不能：真 CSV 报告/签名、KDS 取链、SM3 度量比对——这些要海光硬件 + 真 Trustee（见 `custom-真机CSV部署.md`）。
- 排查入口：`/dev/csv-guest` 存在性（`detect_platform()`，`csv/mod.rs:30-32`）→ 不存在则 attester 直接失败。

## 6. 补充：CSV 平台易错点（与 `D2-任务与交付参考.md` §6.1 对齐）

这些是从实码核对出的细节，attester 与 verifier 两端都容易踩坑，列在此统一口径：

- **两套哈希各管一段**：RCAR 的 `runtime_data` 摘要用 **Challenge 选定的算法（默认 SHA384）**；而 CSV 的 CC Eventlog（CCEL/AAEL）哈希用 **SM3**（见 §1.4）。联调时 KBS/AS 侧 `selected-hash-algorithm` 与 verifier 的 SM3 重放校验都要成立，**别把两种哈希混为一谈**。
- **initdata 不受支持**：trustee 的 CSV verifier 明确 `warn!("CSV does not support init data hash mechanism. skip.")`——想绑定 initdata，只能靠 `report_data`/RTMR 间接绑，不能指望 AS 校验 initdata 哈希。
- **报告版本决定能验什么**：`AttestationReport::V1`（CSV/CSV2）只有 `measure`，**没有 RTMR/eventlog**；`V2`（CSV3）才有 `rtmr0–rtmr4` 并对 CCEL 做 SM3 重放。**M1 押 CSV3 才有运行期度量可验**。
- **证书链本地优先**：verifier 优先读 `/opt/hygon/csv/hsk_cek/<chip_id>/hsk_cek.cert`，否则访问 `https://cert.hygon.cn`——内网/离线环境必须预置证书，否则证据验证直接失败（D5 导出 + D3 预置）。

## 参考文件

- `attestation-agent/attester/src/csv/mod.rs`（CsvEvidence、get_evidence、CSV_INCLUDE_CERT_CHAIN_ENV、pcr_to_ccmr、Sm3）
- `attestation-agent/attester/src/lib.rs`（`TeeEvidence = serde_json::Value :210`；`Attester` trait `:217`）
- `attestation-agent/attestation-agent/src/lib.rs`（AA `Tee` 派发、`get_evidence(runtime_data)`）
- `Cargo.toml`（workspace `kbs-types = "0.18.0" :49`）
- `custom-真机CSV部署.md`（真机部署前置与验证）
- `custom-项目理解.md`（kbs-types 为外部依赖、C1 契约、变更须与 D4 协调）
