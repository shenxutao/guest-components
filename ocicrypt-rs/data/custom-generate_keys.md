## 为单元测试与集成测试生成密钥对

### 生成 PEM 私钥
openssl genrsa -out private_key.pem

### 由 PEM 私钥生成 DER 私钥
openssl rsa -inform pem -outform der -in private_key.pem -out private_key.der

### 由 PEM 私钥生成 PKCS8 PEM 私钥
openssl pkcs8 -topk8 -nocrypt -inform pem -outform pem -in private_key.pem -out private_key8.pem

### 由 PEM 私钥生成 PKCS8 DER 私钥
openssl pkcs8 -topk8 -nocrypt -inform pem -outform der -in private_key.pem -out private_key8.der

### 由 PEM 私钥生成 PEM 公钥
openssl rsa -inform pem -outform pem -pubout -in private_key.pem -out public_key.pem

### 生成 DER EC 私钥
openssl ecparam -genkey -out private_key_ec.der -outform der -name secp521r1

### 生成 DER EC 公钥
openssl ec -in private_key_ec.der -inform der -pubout -outform der -out public_key_ec.der

### 生成自签名根证书
openssl req -x509 -newkey rsa:2048 -keyout certificate_key.pem -out certificate.pem -days 365 -nodes -subj '/CN=localhost'

### 由已有 PEM 私钥生成证书签名请求（CSR）
openssl req -new -key private_key.pem -out private_csr.csr -subj '/CN=bar/'

### 由根证书与 CSR 生成客户端证书
openssl x509 -req -in private_csr.csr -CA certificate.pem  -CAkey certificate_key.pem -CAcreateserial -out public_certificate.pem -days 100 -sha256

### 生成口令文件
echo -n "123456" > passwordfile
