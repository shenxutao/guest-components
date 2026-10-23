## 为单元与集成测试生成密钥对和容器镜像

### 创建 PEM 私钥
```shell
$ openssl genrsa -out private_key_for_tests.pem
```

### 从 PEM 私钥创建 PEM 公钥
```shell
$ openssl rsa -inform pem -outform pem -pubout -in private_key_for_tests.pem -out public_key_for_tests.pem
```

### 创建 gzip 压缩的容器镜像
```shell
$ buildctl build --frontend dockerfile.v0 --output type=image,name=ghcr.io/confidential-containers/test-container-image-rs:busybox-gzip,push=true,compression=gzip,compression-level=8,force-compression=true,oci-mediatypes=true --local dockerfile=. --local context=.
```

### 创建 zstd 压缩的容器镜像
```shell
$ buildctl build --frontend dockerfile.v0 --output type=image,name=ghcr.io/confidential-containers/test-container-image-rs:busybox-zstd,push=true,compression=zstd,compression-level=12,force-compression=true,oci-mediatypes=true --local dockerfile=. --local context=.
```

### 创建 JWE 加密的容器镜像
```shell
$ skopeo copy --encryption-key jwe:public_key_for_tests.pem docker://busybox:latest docker://user/busybox_encrypted
```

### 创建 CoCo-Keyprovider 加密的容器镜像
遵循 [README](https://github.com/confidential-containers/guest-components/blob/main/attestation-agent/coco_keyprovider/README.md)
