# D2 腾讯云 Ubuntu 连调 Runbook（草稿）

> 目标：在普通 Linux x86_64（腾讯云轻量 Ubuntu，**非机密 VM**）上，把 D2 涉及的 guest 组件跑起来，完成「自己的服务部署 + 依赖桩」的连调，验证集成管道。
> 能力边界：无 TEE → 无真硬件证据；用 `none` attester 桩；用 `offline_fs_kbc` 替代外部 KBS（**无需 Beeceptor**）。真 CSV 证明仍需海光硬件 + Trustee 真部署 + kata-runtime。
> 说明：以下命令为连调草案，bin 名 / 配置文件路径以各 crate 的 `src/bin`、`src/config` 实际产物为准，启动前先 `cargo build` 看真实产物。

## 0. 环境准备（腾讯云 Ubuntu x86_64）

- 装 rustup 并拉 1.95.0：仓库 `rust-toolchain.toml` 已锁版本，`cd` 进仓库会自动生效；如未自动，`rustup toolchain install 1.95.0`。
- **本地连调不需要 musl**：直接 `cargo build`（native glibc）即可。musl 静态链接仅用于最终打包进 guest 镜像，开发期可跳过，省去 musl 交叉工具链。
- 编译期系统依赖：`build-essential`、`pkg-config`、`libssl-dev`（OpenSSL 为固定后端）、`protobuf-compiler`（protos 生成 ttrpc/grpc 代码）。
- 运行期：部分 CDH 测试 / sealed secret 需 root；建议直接在 root 或 `sudo` 下跑守护进程。

## 1. 构建

- 默认 feature = `all-attesters`（含 `csv-attester`，见 `attestation-agent/attester/Cargo.toml:72-87`）。普通 `cargo build` 会编进所有 attester（慢但全）。
- 想快一点，只编 D2 相关包：
  `cargo build -p attestation-agent -p confidential-data-hub -p api-server-rest`
- 产出二进制（名字以实际为准，常见：`attestation-agent`、`confidential-data-hub`、`api-server-rest`）在 `target/debug/`。

## 2. 关键配置：用 offline_fs_kbc 替代外部 KBS（核心，免 Beeceptor）

- AA/CDH 通过 KBC 取资源/密钥。**默认就是 `offline_fs_kbc`**（`attestation-agent/attestation-agent/src/config/aa_kbc_params.rs:23`，取不到时回退 `offline_fs_kbc::null` `:63`）。→ 本地连调默认就不需要 Beeceptor / 真 Trustee。
- 配置入口：`AA_KBC_PARAMS` 环境变量，格式 `KBC_NAME::KBS_URI`。
  - 开发桩：`AA_KBC_PARAMS=offline_fs_kbc::null`
  - 若要接真/模拟 KBS：`AA_KBC_PARAMS=cc_kbc::https://<host>`（见第 6 节 mock）
  - 另外也读内核 cmdline `agent.aa_kbc_params=`；peer-pods 场景读 kata-agent 配置。
- 资源从本地 JSON 提供（见 `confidential-data-hub/kms/src/plugins/kbs/offline_fs.rs:19-24`）：
  - 默认文件：`/etc/aa-offline_fs_kbc-resources.json`、`/etc/aa-offline_fs_kbc-keys.json`
  - 或设 `OFFLINE_FS_KBC_EXTRA_FILE_PATH=<path>` 指向一个 resources JSON，免改 `/etc`
  - 生成方式：仓库脚本 `image-rs/scripts/install_offline_fs_kbc_files.sh`，或参考其输出手动写
  - 格式：resource_path → base64(value) 的映射

## 3. attester 选择（非 TEE 机器必须用 none）

- 非机密 VM 跑不了 tdx/snp/csv 的真证据。开发用 **`none` attester**（Makefile：`none`/`fs` → `none`，无硬件依赖）。
- 在 AA 配置里把 `attester` 设成 `none`（配置文件/字段以 `attestation-agent/attestation-agent/src/config/` 为准；**部署到真机密 VM 时再切回 `csv`**）。
- 说明：用 `none` 时 evidence 是桩，AA 与 KBS 的 RCAR 真握手不会成功——这正是「验不了真机密行为」的体现；但 ttrpc/REST 接口、资源取回、密钥解封等**管道可完整验证**。

## 4. 启动三个守护进程

- 先建运行时目录（socket/凭据路径，遵循仓库约定）：`mkdir -p /run/confidential-containers`
- 启动顺序建议：**CDH → AA → ASR**（ASR 是 REST 网关，依赖后两者）。
- 示例（开发用，关掉生产加固）：
  ```
  # CDH
  AA_KBC_PARAMS=offline_fs_kbc::null \
  OFFLINE_FS_KBC_EXTRA_FILE_PATH=./dev-resources.json \
  cargo run -p confidential-data-hub --bin confidential-data-hub

  # AA
  AA_KBC_PARAMS=offline_fs_kbc::null cargo run -p attestation-agent

  # ASR
  cargo run -p api-server-rest
  ```
- 端口/socket：
  - CDH 监听 `unix:///run/confidential-containers/cdh.sock`（image-rs 客户端约定，见 `image-rs/src/resource/kbs/ttrpc.rs:16`）
  - ASR 监听 `127.0.0.1:8006`（loopback，非 loopback 访问 403）
- ⚠️ 具体 bin 名、配置文件路径以各 crate 的 `src/bin` 与 `src/config` 为准，启动前 `cargo build` 看实际产物名。

## 5. 验证（连调检查表）

- **ASR REST（loopback）**：
  - `curl http://127.0.0.1:8006/info` → 应返回 `VersionInfo`
  - `curl http://127.0.0.1:8006/cdh/resource/default/key/test` → 应能经 CDH 取回你在 `dev-resources.json` 里放的资源
- **image-rs 直连 CDH**：用 image-rs 的 ttrpc 客户端（或 `confidential-data-hub/hub/src/bin/ttrpc-cdh-tool.rs`）连 `cdh.sock` 取资源，验证 `kbs://` → `offline_fs_kbc` 通路。
- **sealed secret（D2 重点）**：用 `confidential-data-hub/hub/src/bin/secret_cli.rs` 的 `secret_cli` 跑密封/解封样例，理顺 `/run/confidential-containers/cdh/sealed-secret` 凭据与签名校验。
- **AA token/evidence**：调 ASR `/aa/evidence`、`/aa/token` 看 `none` attester 下的返回（桩数据）。

## 6. （可选）最小 mock KBS —— 仅在要测 cc_kbc 真 HTTP 路径时用

- 若想验证 `cc_kbc::https://<mock>` 这条「AA→真 KBS 形态」的客户端，可用 Beeceptor 或自起一个最小 KBS HTTP 服务返回固定资源。**仅验证请求/响应形状，不做真证明。**
- 最小 Rust 草图（用 workspace 已有的 hyper，仅示意资源端点；真实 KBS 还有 RCAR challenge/response，这里不实现）：
  ```rust
  use hyper::{Body, Request, Response, Server, service::{make_service_fn, service_fn}};

  async fn handle(_req: Request<Body>) -> Result<Response<Body>, hyper::Error> {
      // 真实 KBS: GET /kbs/v0/resource/<path> 返回 base64 资源；此处返回固定桩
      Ok(Response::new(Body::from("base64-encoded-secret")))
  }

  #[tokio::main]
  async fn main() {
      let addr = ([0, 0, 0, 0], 8080).into();
      Server::bind(&addr)
          .serve(make_service_fn(|_| async {
              Ok::<_, hyper::Error>(service_fn(handle))
          }))
          .await
          .unwrap();
  }
  ```
- 然后 `AA_KBC_PARAMS=cc_kbc::http://<mock-host>:8080` 让 AA/CDH 走这个桩。

## 7. 边界与下一步

- ✅ 本 runbook 能验：组件编译/启动/互通、接口、资源取回、密钥解封管道。
- ❌ 验不了：真机密证明（需 TEE）、kata-runtime 接入（vsock/gRPC，非 HTTP）。
- 下一步（真机阶段）：海光 CSV 硬件 + 把 `attester` 切回 `csv`（并补 `Makefile` 的 `csv → csv-attester` 映射，见 `Makefile:37` TODO）+ 部署真 Trustee/KBS + 接 kata-runtime，做 RCAR 端到端验明。

## 参考文件

- `Makefile`（TEE_PLATFORM→ATTESTER 映射；CSV TODO 在 `:37`）
- `attestation-agent/attester/Cargo.toml`（feature 定义，`:72-117`）
- `attestation-agent/attestation-agent/src/config/aa_kbc_params.rs`（AA_KBC_PARAMS 解析，`:23`/`:63`）
- `confidential-data-hub/kms/src/plugins/kbs/offline_fs.rs`（offline_fs_kbc 资源文件，`:19-24`）
- `image-rs/scripts/install_offline_fs_kbc_files.sh`（生成 resources JSON）
- `confidential-data-hub/hub/src/bin/secret_cli.rs`（sealed secret 样例）
- `image-rs/src/resource/kbs/ttrpc.rs`（cdh.sock 约定，`:16`）
- 仓库已翻译文档：`confidential-data-hub/custom-README.md`、`attestation-agent/docs/custom-IMPLEMENTATION.md`
