# image-rs

容器镜像的 Rust Crate。

## 文档

[设计文档](../../../image-rs/docs/design.md)

[镜像安全设计文档](../../../image-rs/docs/ccv1_image_security_design.md)

关于镜像加密/解密注解格式与协议，请参见
[IMAGE_ENCRYPTION.md](../../../attestation-agent/docs/IMAGE_ENCRYPTION.md) 和
[IMPLEMENTATION.md](../../../attestation-agent/docs/IMPLEMENTATION.md)。

## 性能测试

本 crate 包含基准测试，用于测量镜像拉取吞吐量与内存消耗。我们使用 [cargo bench](https://doc.rust-lang.org/cargo/commands/cargo-bench.html) 测试镜像拉取吞吐量，使用 [heaptrack](https://github.com/KDE/heaptrack) 分析内存消耗。

### 运行基准测试

#### 前置条件

安装 heaptrack 以分析内存消耗：

```bash
sudo apt install heaptrack -y
```

#### 运行基准测试

运行镜像拉取基准测试：

```bash
heaptrack cargo bench -p image-rs --bench image-pull
```

该基准测试测量：
- 镜像拉取时间
- 吞吐量（MiB 每秒）

#### 理解测试结果

**吞吐量结果**

详细的性能指标与可视化图表会生成在 `target/criterion/` 目录下。同时，终端会显示一份摘要：

```
image-pull/ghcr.io/confidential-containers/test-container:unencrypted
                        time:   [2.3829 s 2.4001 s 2.4197 s]
                        thrpt:  [3.5598 MiB/s 3.5889 MiB/s 3.6148 MiB/s]
                 change:
                        time:   [−3.7930% −0.9001% +1.3846%] (p = 0.61 > 0.05)
                        thrpt:  [−1.3657% +0.9083% +3.9425%]
                        未检测到性能变化。
```

**内存消耗报告**

基准测试完成后，heaptrack 会显示一条用于分析内存数据的命令：

```
Heaptrack finished! Now run the following to investigate the data:

  heaptrack --analyze "xxxx/heaptrack.cargo.3133205.zst"
```

运行该命令生成内存消耗报告：

```bash
heaptrack --analyze "xxxx/heaptrack.cargo.3133205.zst"
```

报告包含如下指标：

```
总分配字节数（忽略释放）： 51.85MB (328.14MB/s)
分配函数调用次数： 237333 (1502107/s)
临时内存分配次数： 89438 (566063/s)
堆内存峰值消耗： 14.17MB
RSS 峰值（含 heaptrack 开销）： 126.19MB
总内存泄漏： 1.14MB
```
