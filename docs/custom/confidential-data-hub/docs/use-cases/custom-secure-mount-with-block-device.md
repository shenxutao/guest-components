# 使用块设备进行安全挂载

本指南帮助用户使用机密数据中枢在 TEE 环境内进行安全挂载。

## 准备工作

- 确保已安装 `cryptsetup` 以用于 **LUKS2** 模式。
- 确保已安装 `zfsutils-linux` 且已启用 ZFS 内核模块以用于 **ZFS** 模式。

块设备插件支持两种安全挂载模式：**LUKS2**（`encryptionType: "luks2"`）和 **ZFS**（`encryptionType: "zfs"`）。下面的 [配置](../../../../../confidential-data-hub/docs/use-cases#配置) 章节汇总了通用选项和模式特定选项；随后 [最佳实践](../../../../../confidential-data-hub/docs/use-cases#最佳实践) 涵盖了 loop 设备的准备，以及 LUKS2 和 ZFS 的端到端流程。

## 配置

CDH 的 `secure_mount` API 期望一个类似于本文档示例的 JSON 载荷，其顶层结构如下：

```json
{
  "volume_type": "block-device",
  "options": {
    "...": "..."
  },
  "flags": [],
  "mount_point": "/mnt/your-path"
}
```

### 通用选项

**LUKS2 和 ZFS 两种模式**都使用的通用字段：

| 名称              | 位置     | 类型 / 值                                      | 必需 | 说明 |
| ----------------- | ----------- | -------------------------------------------------- | -------- | ----------- |
| `volume_type`     | 顶层   | `"block-device"`                                  | 是      | 选择块设备插件。本指南中必须为 `"block-device"`。 |
| `options.devicePath`      | `options`   | 字符串路径（例如 `/dev/loop0`）                   | `devicePath` 或 `deviceId` 二选一 | 后端块设备的路径。如果 `devicePath` 和 `deviceId` 都设置，以 `deviceId` 为准。 |
| `options.deviceId`        | `options`   | 字符串 `"MAJ:MIN"`（例如 `"7:0"`）                 | `devicePath` 或 `deviceId` 二选一 | 内核主/次设备号（major/minor）。CDH 会在内部将其解析为设备路径。 |
| `options.sourceType`      | `options`   | `"empty"` \| `"encrypted"`                        | 是      | `"empty"` 表示设备将被初始化并加密；`"encrypted"` 表示设备已被加密，应当被打开。 |
| `options.encryptionType`  | `options`   | `"luks2"` \| `"zfs"`                              | 是      | 选择加密模式。LUKS2 使用 dm-crypt；ZFS 使用 ZFS 原生加密。 |
| `options.key`             | `options`   | URI：`sealed.*`、`kbs://…` 或 `file://…`         | 否       | 从何处获取加密密钥。如果省略，CDH 会生成一个随机密钥（临时存储）。 |
| `mount_point`     | 顶层   | 字符串路径（例如 `/mnt/my-path`）                 | 是      | guest 内部明文设备或文件系统变得可见的挂载路径。 |

### LUKS2 特定选项

除了上述通用字段外，LUKS2 模式还支持以下选项：

| 名称               | 类型 / 值                                | 必需 | 最佳实践用法 |
| ------------------ | -------------------------------------------- | -------- | ------------------- |
| `options.targetType`       | `"device"` \| `"fileSystem"`                 | 是      | 当你想要一个明文块设备（例如用于自行管理文件系统的数据库）时使用 `"device"`；当你想让 CDH 为你挂载一个文件系统时，使用 `"fileSystem"`。 |
| `options.filesystemType`   | `"ext4"`（默认）及其他文件系统类型        | 当 `targetType` 为 `"fileSystem"` 时必需 | 大多数工作负载设为 `"ext4"`。当 `sourceType` 为 `"encrypted"` 时必须与现有文件系统匹配。此时，需确保已安装 `mkfs.ext4`。 |
| `options.mkfsOpts`         | 传给 `mkfs.<fs>` 的额外参数字符串          | 否       | 仅当 `sourceType` 为 `"empty"` 且需要调优文件系统创建时使用（例如 `"-E lazy_journal_init=1"`）。留空则使用合理的默认值。 |
| `options.dataIntegrity`    | 布尔值（`true` / `false`）                   | 否（默认 `false`） | 设为 `true` 可开启 dm-integrity 以获得更强的完整性保证；预计会有 >30% 的 IO 性能开销。对性能敏感的临时存储请保持 `false`。 |
| `options.mapperName`       | 字符串（例如 `"my-mapped-device"`)           | 否       | 当你需要一个稳定的 `/dev/mapper/<name>` 用于监控或调试时设置。省略时，CDH 会生成一个基于 UUID 的名称。 |

当 `encryptionType` 为 `"luks2"`、`targetType` 为 `"fileSystem"`、`filesystemType` 为 `"ext4"` 且 `dataIntegrity` 为 `true` 时，CDH 会用 `lazy_itable_init=0` 来格式化 ext4，除非调用方在 `mkfsOpts` 中显式提供了 `lazy_itable_init` 设置。这可以避免之后在无擦除（no-wipe）的 dm-integrity 设备上因惰性 inode 表初始化而产生 I/O 错误。

### ZFS 特定选项

除了上述通用字段外，ZFS 模式还支持以下选项：

| 名称              | 类型 / 值                     | 必需 | 最佳实践用法 |
| ----------------- | --------------------------------- | -------- | ------------------- |
| `options.pool`            | 字符串（例如 `"pool1"`)           | 否（默认 `"zpool"`） | 为每个设备或集群选择一个有意义的存储池名称（例如 `"pool-ml-models"`）。重新导入已有设备时，复用相同的名称。 |
| `options.dataset`         | 字符串（例如 `"dataset1"`)        | 否（默认 `"zdataset"`） | 根据工作负载为数据集命名（例如 `"models"`、`"snapshots"`）。当 `sourceType` 为 `"encrypted"` 时必须与现有数据集名称匹配。 |

注意事项与最佳实践：

- ZFS **始终**以文件系统形式在 `mount_point` 挂载一个加密数据集；当前实现忽略 `targetType`，但你仍应将其设为 `"fileSystem"` 以保持清晰。
- 对于全新设备上的**首次挂载**，使用 `sourceType: "empty"` 配合一个强 `key` 以及显式的 `pool` / `dataset` 名称；CDH 将为你创建存储池和加密数据集。
- 对于已加密设备上的**重新挂载**，使用 `sourceType: "encrypted"` 配合相同的 `pool`、`dataset` 和 `key`；CDH 将导入存储池、加载密钥并挂载数据集。

---

## 最佳实践

### 创建 loop 设备

准备一个块设备（例如一个文件支持的 loop 设备），它将用于下面 LUKS2 和 ZFS 两个示例。

```bash
device_file="/tmp/test.img"
sudo dd if=/dev/zero of=$device_file bs=1M count=1000
sudo losetup -fP $device_file
device=$(sudo losetup -j $device_file | awk -F'[: ]' '{print $1}')
echo $device
# 输出应当类似 /dev/loop0
device_num=$(sudo lsblk -no MAJ:MIN $device)
echo $device_num
# 输出应当类似 7:0
```

在后续章节的请求 JSON 中，使用 `$device`（例如 `/dev/loop0`）或 `$device_num`（例如 `7:0`）作为 `devicePath` 或 `deviceId`。

---

### LUKS2 最佳实践

使用 **LUKS2** 安全挂载（`encryptionType: "luks2"`）时的命令、步骤与预期行为。

### 前置条件

- 构建 CDH 和客户端工具：参见 [CDH README](../../../../../confidential-data-hub/README.md#confidential-data-hub) 和 [客户端工具 README](../../../../../confidential-data-hub/README.md#client-tool)。
- 安装 `cryptsetup` CLI

```bash
sudo apt install -y cryptsetup
```

### 步骤 1：启动 CDH

```shell
$ confidential-data-hub
```

让它保持运行（或在后台运行）。后续步骤使用另一个终端。

### 场景

选择以下场景之一。

#### 场景 1：使用 LUKS2 的临时存储

临时存储是一种非持久化的存储。

1. 挂载一个块设备文件，使用 `luks2` 配合临时密钥对其进行加密，并将明文设备以设备文件形式挂载到 `/mnt/dev-path`。

```json
{
    "volume_type": "block-device",
    "options": {
        "devicePath": "/dev/loop0",
        "sourceType": "empty",
        "targetType": "device",
        "encryptionType": "luks2"
    },
    "flags": [],
    "mount_point": "/mnt/dev-path"
}
```

2. 挂载一个块设备文件，使用 `luks2` 配合临时密钥对其进行加密，并将明文设备文件格式化为 `ext4` 文件系统，以目录形式将明文挂载到 `/mnt/directory-path`。

```json
{
    "volume_type": "block-device",
    "options": {
        "devicePath": "/dev/loop0",
        "sourceType": "empty",
        "targetType": "fileSystem",
        "encryptionType": "luks2",
        "filesystemType": "ext4"
    },
    "flags": [],
    "mount_point": "/mnt/directory-path"
}
```

#### 场景 2：使用 LUKS2 的持久化存储

1. 挂载一个 `luks2` 加密的块设备文件，返回明文设备路径，以设备文件形式将明文挂载到 `/mnt/dev-path`。解密密钥可以从 KBS 获取，也可以从本地文件系统获取。

我们可以在挂载之前准备一个加密的块设备文件。使用 `"passphrase"` 作为密码，用 luks2 对块设备文件进行加密。

```bash
storage_key_path="/tmp/encryption_key"
echo "passphrase" > "$storage_key_path"

cryptsetup --batch-mode luksFormat --type luks2 "$device_file" --sector-size 4096 \
	--cipher aes-xts-plain64 "$storage_key_path"
```

然后使用该 json 载荷

```json
{
    "volume_type": "block-device",
    "options": {
        "devicePath": "/dev/loop0",
        "sourceType": "encrypted",
        "targetType": "device",
        "encryptionType": "luks2",
        "key": "file:///tmp/encryption_key"
    },
    "flags": [],
    "mount_point": "/mnt/dev-path"
}
```

2. 挂载一个 `luks2` 加密的块设备文件，解密并以 `ext4` 文件系统形式挂载，以目录形式将明文挂载到 `/mnt/directory-path`。`luks2` 解密密钥从 KBS 获取。

我们可以在挂载之前准备一个加密的块设备文件。使用 `"passphrase"` 作为密码，用 `luks2` 对块设备文件进行加密。

```bash
storage_key_path="/tmp/encryption_key"
opened_device_name="test-name"
mount_dir="/mnt/luks2ext4-cdh-test"

echo "passphrase" > "$storage_key_path"

cryptsetup --batch-mode luksFormat --type luks2 "$device_file" --sector-size 4096 \
	--cipher aes-xts-plain64 "$storage_key_path"

cryptsetup luksOpen -d "$storage_key_path" "$device_file" "$opened_device_name"
mkfs.ext4 "/dev/mapper/$opened_device_name"
mkdir -p "${mount_dir}"
mount "/dev/mapper/$opened_device_name" "${mount_dir}"
echo "some-data" > "${mount_dir}/confidential-data-file"

sync

umount "${mount_dir}"
cryptsetup luksClose "$opened_device_name"
```

然后你可以使用以下 `secure_mount` 请求，将加密的块设备挂载到目标路径。

```json
{
    "volume_type": "block-device",
    "options": {
        "devicePath": "/dev/loop0",
        "sourceType": "encrypted",
        "targetType": "fileSystem",
        "encryptionType": "luks2",
        "key": "file:///tmp/encryption_key",
        "filesystemType": "ext4"
    },
    "flags": [],
    "mount_point": "/mnt/luks2ext4-cdh-test"
}
```

然后你可以读取明文文件。
```shell
$ cat /mnt/luks2ext4-cdh-test/confidential-data-file
some-data
```

---

### ZFS 最佳实践

使用 **ZFS** 安全挂载（`encryptionType: "zfs"`）时的命令、步骤与预期行为。

### 前置条件

- 安装 ZFS 用户态工具并确保已加载 ZFS 内核模块：

```bash
sudo apt install -y zfsutils-linux
# 如果需要，加载模块：
sudo modprobe zfs
```

- 构建 CDH 和客户端工具（与 LUKS2 相同）。在调用 secure-mount 之前启动 CDH（例如 `confidential-data-hub`）。

### 步骤 1：准备加密密钥文件

ZFS 模式需要一个密钥（例如密码文件）用于加密数据集。

```bash
zfs_key_path="/tmp/zfs_encryption_key"
echo "your-passphrase" > "$zfs_key_path"
```

在请求中使用此路径，即 `"key": "file:///tmp/zfs_encryption_key"`。

### 步骤 2：首次挂载（空设备 → 创建 zpool + 加密数据集）

**命令：** 创建挂载点并准备请求 JSON。将 `devicePath` 替换为你的块设备（例如 “创建 loop 设备” 中的 `$device`）。

保存为 `storage-zfs.json`：

```json
{
    "volume_type": "block-device",
    "options": {
        "devicePath": "/dev/loop0",
        "sourceType": "empty",
        "targetType": "fileSystem",
        "encryptionType": "zfs",
        "key": "file:///tmp/zfs_encryption_key",
        "pool": "pool1",
        "dataset": "dataset1"
    },
    "flags": [],
    "mount_point": "/mnt/zfs-dataset"
}
```

```shell
$ ttrpc-cdh-tool secure-mount --storage-path storage-zfs.json
```

**预期现象：**

- 命令成功退出。
- 一个新的 zpool 和加密数据集已存在；该数据集被挂载到给定路径：

```shell
$ zpool list
NAME    SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
pool1   960M   266K   960M        -         -     0%     0%  1.00x    ONLINE  -

$ zfs list
NAME             USED  AVAIL  REFER  MOUNTPOINT
pool1            266K   832M    24K  /pool1
pool1/dataset1    98K   832M    98K  /mnt/zfs-dataset

$ mount | grep zfs
pool1 on /pool1 type zfs (rw,relatime,xattr,noacl,casesensitive)
pool1/dataset1 on /mnt/zfs-dataset type zfs (rw,relatime,xattr,noacl,casesensitive)
```

- 你可以在挂载点下读写文件：

```shell
$ echo "secret" > /mnt/zfs-dataset/confidential.txt
$ cat /mnt/zfs-dataset/confidential.txt
secret
```

### 步骤 3：卸载并重新挂载（已加密数据集，相同密钥）

卸载（例如通过 `zpool export pool1`）之后，zpool 被导出。要再次使用同一设备，用 `sourceType: "encrypted"` 导入并挂载。

**命令：** 使用相同的 `pool` 和 `dataset` 名称以及密钥。保存为 `storage-zfs-encrypted.json`：

```json
{
    "volume_type": "block-device",
    "options": {
        "devicePath": "/dev/loop0",
        "sourceType": "encrypted",
        "targetType": "fileSystem",
        "encryptionType": "zfs",
        "key": "file:///tmp/zfs_encryption_key",
        "pool": "pool1",
        "dataset": "dataset1"
    },
    "flags": [],
    "mount_point": "/mnt/zfs-dataset"
}
```

```shell
$ ttrpc-cdh-tool secure-mount --storage-path storage-zfs-encrypted.json
```

**预期现象：**

- Zpool 被导入，数据集被挂载到 `/mnt/zfs-dataset`。
- 之前写入的数据仍然存在：

```shell
$ cat /mnt/zfs-dataset/confidential.txt
secret
```

- `zpool list` 和 `zfs list` 再次显示 `pool1` 和 `pool1/dataset1`，挂载点为 `/mnt/zfs-dataset`。

> [!INFO]
> - 对于 ZFS，CDH 始终创建文件系统风格的挂载。
> - `pool` 和 `dataset` 必须与设备首次格式化（`sourceType: "empty"`）时使用的相匹配；否则导入或挂载可能会失败。
> - 卸载后，该设备可以移动到另一台机器；在那里使用相同的 `pool`、`dataset` 和密钥来重新挂载。
