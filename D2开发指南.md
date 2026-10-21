# guest-components · D2 开发指南（申许涛）

> 本文件是 D2（申许涛）在本 fork 上的**个人开发规范**，非上游文档。
> 用途：记录仓库来源、分支策略、remote 与日常 git 操作，供本人及 CodeBuddy 开发时参考。

---

## 1. 项目定位

- 这是 `confidential-containers/guest-components` 的**个人 GitHub fork**，仅用于 D2 本地开发。
- **不提 PR 回上游、不影响官方**——所有改动只推到自己的 fork。
- **D2 主责组件**（你真正要写/改代码的）：
  - `attestation-agent`（AA）—— 含海光 **csv attester**（`attester/src/csv/`，M1 证据采集端）
  - `confidential-data-hub`（CDH）—— 含 **sealed secret** 密封卷机制（`docs/SEALED_SECRET.md`，S3 依赖）
  - 还有 `image-rs`、`ocicrypt-rs`、`coco-keyprovider`
- **相关但不在此改**：
  - `kbs-types` —— 是 `guest-components` 的**外部依赖 crate，用不是改**（C1 契约；改字段须与 D4 协调）
  - `trustee` / `kata-containers` —— 联调对象与运行载体，**对接不是维护**

---

## 2. 仓库 Remote

| remote | 地址 | 用途 |
|--------|------|------|
| `origin` | https://github.com/shenxutao/guest-components.git | 你的 fork（**可写**） |
| `upstream` | https://github.com/confidential-containers/guest-components | 官方（**只读**，用于同步） |

查看：`git remote -v`

---

## 3. 分支

- `main` —— 跟踪 `origin/main`（与官方 fork 点一致，**不要在其上直接改**）
- **`2026-10-21-dev`** —— **你的开发分支**，已基于 `upstream/main` 建立
  - ⚠️ 已**解除对 `upstream/main` 的跟踪**（防止裸 `git push` 误推官方）

---

## 4. 日常操作

```bash
cd /Users/shenxutao/MyWorkspace/Docs/机密计算/开发/guest-components

# ① 改代码后提交（始终在 2026-10-21-dev 上）
git add -A && git commit -m "你的改动说明"

# ② 想跟官方最新同步时
git fetch upstream && git rebase upstream/main

# ③ 推到你自己的 fork（需先配 GitHub 凭据，见第 5 节）
git push origin 2026-10-21-dev          # 首次：git push -u origin 2026-10-21-dev
```

---

## 5. 推送到 fork 的凭据

当前环境曾因**无 GitHub 凭据**导致 `git push` 失败（`could not read Username`）。GitHub 已不支持密码推送，需用 **Personal Access Token (PAT)**：

```bash
# 方式 A（推荐）：macOS 钥匙串存凭据，一次配置后免输
git config --global credential.helper osxkeychain
git push -u origin 2026-10-21-dev       # 首次会提示输入 用户名 + PAT

# 方式 B：临时用 PAT 直推
git push https://<你的PAT>@github.com/shenxutao/guest-components.git 2026-10-21-dev
```

> PAT 申请：GitHub → Settings → Developer settings → Personal access tokens，勾 `repo` 权限。

---

## 6. 纪律（务必遵守）

- 永远 `git push origin 2026-10-21-dev`，**不要裸 `git push`**（虽已解除官方跟踪，显式写 origin 更稳）。
- **绝不 push 到 `upstream`**（官方仓库）。
- `源码/guest-components` 是**只读参考副本**，不要在其中开发；真正开发只在 `开发/guest-components`。
- 改动只涉及 D2 主责组件；契约字段（`kbs-types`）如需改，须先与 D4 协调。

---

## 7. 环境提示（Agent 用）

- 本机 Bash 的 sandbox 代理会挡 GitHub（`CONNECT tunnel failed, response 502`）。
- 通过该 agent 执行 git 网络操作时，需**放开沙箱直连**（执行时带 `dangerouslyDisableSandbox: true`）才能连通。
- 用户本机终端若有同样 502，需先配置 git 代理或网络。
