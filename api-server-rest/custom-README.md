# CoCo RESTful API 服务

CoCo guest components（机密容器 guest 组件）使用轻量级的 ttRPC 进行内部通信，以减少内存占用和依赖。但容器内也经常需要用到一些内部服务，例如 `get_resource`、`get_evidence` 和 `get_token`，因此我们用 RESTful API 把这些服务暴露出来，这样 CoCo 容器就能用 HTTP 客户端轻松调用这些 API 了。以下是一些示例，详细信息请参考 [REST API 定义](./openapi/api.json)。

```bash
$ ./api-server-rest --features=all
Starting API server on 127.0.0.1:8006
API Server listening on http://127.0.0.1:8006

$ curl http://127.0.0.1:8006/cdh/resource/default/key/1
12345678901234567890123456xxxx

$ curl http://127.0.0.1:8006/aa/evidence\?runtime_data\=xxxx
{"svn":"1","report_data":"eHh4eA=="}

# 当 runtime_data 是 URL 安全的 base64 时，传入 encoding=base64
$ curl "http://127.0.0.1:8006/aa/evidence?runtime_data=eHh4eA&encoding=base64"
{"svn":"1","report_data":"eHh4eA=="}

$ curl http://127.0.0.1:8006/aa/additional-evidence\?runtime_data\=xxxx
{"nvidia":"..."}

$ curl "http://127.0.0.1:8006/aa/additional-evidence?runtime_data=eHh4eA&encoding=base64"
{"nvidia":"..."}

$ curl http://127.0.0.1:8006/aa/token\?token_type\=kbs
{"token":"eyJhbGciOiJFi...","tee_keypair":"-----BEGIN... "}

$ curl http://127.0.0.1:8006/info
{"version":"v1.0.0","tee":"tdx","additional_tees":[]}

$ curl -X POST http://127.0.0.1:8006/aa/aael \
     -H "Content-Type: application/json" \
     -d '{"domain":"test","operation":"test","content":"test"}'

```

## 事件日志域（Event log domains）

`/aa/aael` 允许容器向 Attestation Agent 的事件日志（Event Log）追加一条记录，该记录会被度量（measured）进 TEE，随后被依赖方（relying party）读取。由于这些记录不带生产者身份标识，`github.com/confidential-containers` 域及其子路径被保留给 guest components 自身记录的事件（例如 CDH 的 `PullImage` 事件），在本端点会被以 `403` 拒绝。容器应当在自己拥有的域下记录日志。

`domain` 和 `operation` 必须是非空、且不含空白字符和控制字符；`content` 必须不包含控制字符，这样一条记录编码后才不会被误认为是另一条不同的记录。
