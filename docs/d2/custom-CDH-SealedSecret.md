# CDH Sealed Secret 信封格式与 secret_cli 用法（D2 重点）

> 来源：`confidential-data-hub/hub/src/secret/`（`mod.rs`、`layout/envelope.rs`、`layout/vault.rs`）、`hub/src/bin/secret_cli.rs`、`hub/src/hub.rs:9`。
> 作用：CDH 的「密封密钥 / 凭据」机制——把敏感数据用**数字信封 + JWS 签名**封装，运行时再解封。这是 D2 主责（CDH sealed secret）的核心。

## 1. 总览：两层结构

一个 sealed secret 字符串 = **外层 JWS 签名** + **内层 JSON 负载**。

```
sealed.<header_b64>.<payload_b64>.<signature_b64>
```

- 外层是 **JWS Flattened**（JSON Web Signature），算法固定 **ES256（P-256 EC）**（`secret/mod.rs:12, 104-106, 210-217`）。
- 内层 `payload` 经 base64url（URL_SAFE_NO_PAD）解码后是 **`Secret` JSON**（`mod.rs:109-136`），再按 `type` 字段分派为 `Envelope` 或 `Vault`。
- 前缀 `sealed.` 在解析时会被 `trim_start_matches` 去掉（`mod.rs:77`）。

## 2. 外层：签名与 kid 寻址

签名校验在 `Secret::from_signed_base64_string`（`mod.rs:71-139`）：

- 取 JWS 头里的 `kid`（密钥 ID）和 `alg`（必须 ES256）。
- 用 `Secret::get_kid(kid)`（`mod.rs:145-170`）找**验签公钥**：
  - 若 `kid` 是 **KBS 资源 URI**（如 `kbs:///...`）→ 通过 `kms::new_getter("kbs", ...)` 从 KBS 取公钥。
  - 否则当作**本地凭据文件名**，从 `SIGNING_CREDENTIALS_PATH` 读取。
- 验签用 ES256：`signing_input = "<header_b64>.<payload_b64>"`，对 `signature_b64` 验（`mod.rs:172-191`）。

**关键路径**（`mod.rs:23,29`、`hub.rs:9`）：

```rust
CDH_BASE_DIR = "/run/confidential-containers/cdh"
SIGNING_CREDENTIALS_PATH = "/run/confidential-containers/cdh/sealed-secret"
```

即：验签公钥文件放在 `/run/confidential-containers/cdh/sealed-secret/<kid>`，内容为 JWK（含 `x`/`y`/`crv` 的公钥，或含 `d` 的私钥均可提取公钥）。

**跳过验签**（仅开发用）：设 `SKIP_SEALED_SECRET_VERIFICATION=true`（`mod.rs:52-53`），此时直接按 `sealed.h.p.s` 四段拆分取第 3 段 base64 解码（`mod.rs:113-129`）。

## 3. 内层：两种 Secret 类型

`Secret` 结构（`mod.rs:31-46`）：

```json
{ "version": "0.1.0", "type": "<envelope|vault>", ... }
```

`version` 必须 `"0.1.0"`（`VERSION`，`mod.rs:46`；不符报 `VersionError`）。`type` 由 serde `#[serde(tag="type", rename_all="lowercase")]` 决定。

### 3.1 Envelope（数字信封）— `envelope-1.json` 样例

```json
{
  "version": "0.1.0",
  "type": "envelope",
  "key_id": "xxx",
  "encrypted_key": "yyy",
  "encrypted_data": "zzz",
  "wrap_type": "A256GCM",
  "iv": "www",
  "provider": "aliyun",
  "provider_settings": {},
  "annotations": {}
}
```

语义（`envelope.rs:37-70, 73-112`），即 `{Enc(KMS, DEK), Enc(DEK, secret)}`：

- `encrypted_key`：用 **KMS 里的 KEK** 加密过的 **DEK**（数据加密密钥），base64(STANDARD) 编码。
- `encrypted_data`：用 **DEK** 以 `wrap_type`（样例是 `A256GCM` = AES-256-GCM）加密的**明文秘密**，base64 编码。
- `iv`：GCM 的 12 字节 IV，base64 编码。
- `provider`：KMS 驱动（`aliyun`/`aws`），解封时 `kms::new_decryptor(provider, provider_settings)` 拿到解密器，`decrypt(encrypted_key, key_id, annotations)` 解出 DEK，再用 DEK 解密 `encrypted_data`。
- `key_id` / `annotations`：在 KMS 中定位 KEK。

### 3.2 Vault（引用型）— `vault-1.json` 样例

```json
{
  "version": "0.1.0",
  "type": "vault",
  "name": "xxx",
  "provider": "aliyun",
  "provider_settings": {},
  "annotations": {}
}
```

语义（`vault.rs:24-58`）：**不内嵌密文**，只引用一个资源名 `name`（常是 `kbs:///...` URI）。解封时 `kms::new_getter(provider, provider_settings).get_secret(name, annotations)` 直接取回明文（`mod.rs:67` 分派）。

> 对 D2 本地联调，**Vault + `provider=kbs`** 是最实用的：秘密直接存在 KBS（offline_fs_kbc 本地文件），无需云 KMS。

## 4. secret_cli 工具（二进制名是 `secret`）

> `hub/Cargo.toml:30-32`：`[[bin]] name = "secret", path = "src/bin/secret_cli.rs"`。
> 调用：**`cargo run -p confidential-data-hub --bin secret -- <子命令>`**（注意 `--` 分隔 cargo 与 binary 参数）。

三个子命令（`secret_cli.rs:35-44`）：

### 4.1 `secret keygen` — 生成 P-256 签名密钥对（JWK）

```bash
cargo run -p confidential-data-hub --bin secret -- keygen \
  --kid my-key --output_dir /tmp/secrets
# 产出：/tmp/secrets/my-key-private.json（含 d）和 my-key-public.json（仅 x/y）
```

### 4.2 `secret seal` — 密封

**Vault 型**（推荐本地路径）：

```bash
cargo run -p confidential-data-hub --bin secret -- seal --type vault \
  --resource_uri "kbs:///default/key/1" \
  --provider kbs \
  --signing_kid my-key \
  --signing_jwk_path /tmp/secrets/my-key-private.json
# 输出一行 sealed.<h>.<p>.<s> 字符串，保存到文件即可
```

**Envelope 型**（需 aliyun/aws KMS 凭据，默认仅 aliyun 特性开启）：

```bash
cargo run -p confidential-data-hub --bin secret -- seal --type envelope aliyun \
  --key_id <KMS_KEY_ID> --file_path /tmp/plain.txt \
  --signing_kid my-key --signing_jwk_path /tmp/secrets/my-key-private.json \
  --password_file_path <pw> --cert_path <ca.pem> \
  --kms_instance_id <id> --client_key_file_path <client_key>
```

### 4.3 `secret unseal` — 解封

```bash
cargo run -p confidential-data-hub --bin secret -- unseal \
  --file_path /tmp/sealed-secret.txt \
  --aa_kbc_params "offline_fs_kbc::null" \   # provider=kbs 时必填
  [--skip_verification]                        # 可选：跳过 ES256 验签
# 成功后在同目录生成 /tmp/sealed-secret.txt.unsealed（明文）
```

`unseal` 内部（`secret_cli.rs:201-258`）：
- 按 `provider` 设环境变量：`kbs`→`AA_KBC_PARAMS`；`aliyun`→`ALIYUN_IN_GUEST_KEY_PATH`；`aws`→`AWS_IN_GUEST_KEY_PATH`。
- 调用 `Secret::unseal` 解封，写出 `<file>.unsealed`。

## 5. 本地端到端联调配方（Vault + offline_fs_kbc + 真签名校验）

演示「签名密封 → KBS 取密 → 解封」全链路，且**走真实 ES256 验签**（不用 skip）：

```bash
# 0) 准备 offline_fs_kbc 资源（已是 runbook 步骤 3 的产物）
#    /tmp/dev-resources.json 含 {"default/key/1": "<base64(my-dev-secret-key-001)>"}
export OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json"

# 1) 生成密钥对
cargo run -p confidential-data-hub --bin secret -- keygen \
  --kid my-key --output_dir /tmp/secrets

# 2) 放验签公钥到 SIGNING_CREDENTIALS_PATH（需 root，因在 /run 下）
sudo mkdir -p /run/confidential-containers/cdh/sealed-secret
sudo cp /tmp/secrets/my-key-public.json \
        /run/confidential-containers/cdh/sealed-secret/my-key

# 3) 密封一个指向 KBS 资源的 Vault secret
cargo run -p confidential-data-hub --bin secret -- seal --type vault \
  --resource_uri "kbs:///default/key/1" --provider kbs \
  --signing_kid my-key --signing_jwk_path /tmp/secrets/my-key-private.json \
  | tee /tmp/sealed-secret.txt

# 4) 解封（provides AA_KBC_PARAMS 让 kbs provider 走 offline_fs_kbc）
AA_KBC_PARAMS="offline_fs_kbc::null" \
OFFLINE_FS_KBC_EXTRA_FILE_PATH="/tmp/dev-resources.json" \
cargo run -p confidential-data-hub --bin secret -- unseal \
  --file_path /tmp/sealed-secret.txt --aa_kbc_params "offline_fs_kbc::null"

# 5) 查看明文（应等于 my-dev-secret-key-001）
cat /tmp/sealed-secret.txt.unsealed
```

**失败排查**：
- 验签报错 → 确认第 2 步公钥文件存在且 `kid` 与 `--signing_kid` 一致；或临时加 `--skip_verification` 先绕过。
- `kbs` 取不到资源 → 确认 `OFFLINE_FS_KBC_EXTRA_FILE_PATH` 指向的 JSON 含对应 `default/key/1`，且 `AA_KBC_PARAMS` 设成 `offline_fs_kbc::null`。
- 无权限写 `/run/...` → 用 `sudo` 建目录；或把 `CDH_BASE_DIR` 改到可写路径需重新编译（hub.rs:9）。

## 6. 与 D2 的关系

- D2 主责之一是 **CDH sealed secret**：理解上述信封/签名机制是改代码与接入 CSV 场景的前提。
- 真机阶段：签名密钥由**机密 VM 内的 CDH 在启动时预置**到 `SIGNING_CREDENTIALS_PATH`；`kid` 可改为 **KBS URI** 由 Trustee 托管公钥（跨仓 `kbs-types` 协议对齐）。
- 本地（腾讯云普通 VM）只能验证**管道与逻辑**（如上配方），无法验证机密 VM 内的真实密钥预置与 TEE 绑定——那需海光 CSV 硬件。

## 参考文件

- `confidential-data-hub/hub/src/secret/mod.rs`（JWS 封装/验签、`get_kid`、路径常量）
- `confidential-data-hub/hub/src/secret/layout/envelope.rs`（数字信封解密）
- `confidential-data-hub/hub/src/secret/layout/vault.rs`（引用型解封）
- `confidential-data-hub/hub/src/bin/secret_cli.rs`（`keygen`/`seal`/`unseal` CLI）
- `confidential-data-hub/hub/src/hub.rs:9`（`CDH_BASE_DIR`）
- `confidential-data-hub/hub/src/secret/tests/{envelope-1,vault-1}.json`（样例）
- `confidential-data-hub/hub/Cargo.toml:30-32,95-101`（bin 名 `secret`、默认特性含 `aliyun`）
