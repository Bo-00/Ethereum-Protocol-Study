# Ethereum 私有网络 - 多节点部署

## 🎯 项目概述

本项目提供了两种以太坊私有网络部署方案：

1. **简化的 PoA 多节点网络** (docker-compose) - 适合学习和开发
2. **完整的 PoS 网络** (Kurtosis) - 模拟真实主网环境

## 🚀 方案一：简化 PoA 多节点网络 (推荐学习)

### 特点

- ✅ **纯 Geth 节点**：3 个 Geth 节点，无需额外客户端
- ✅ **PoA 共识**：Clique 共识算法，低资源消耗
- ✅ **一键启动**：自动处理节点发现和连接
- ✅ **学习友好**：配置简单，便于理解

### 网络架构

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Geth Node1    │    │   Geth Node2    │    │   Geth Node3    │
│  (引导节点)      │◄──►│   (普通节点)     │◄──►│   (普通节点)     │
│   签名者/挖矿    │    │                 │    │                 │
│  :8545 :30303   │    │  :8547 :30304   │    │  :8549 :30305   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### 快速启动

```bash
# 1. 启动网络
./start-geth-network.sh

# 2. 查看网络状态
docker-compose ps

# 3. 查看日志
docker-compose logs -f geth-node1
```

### 连接测试

```bash
# 检查区块高度
curl -X POST -H "Content-Type: application/json" \
  --data '{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"2.0"}' \
  http://localhost:8545

# 查看账户余额
curl -X POST -H "Content-Type: application/json" \
  --data '{"method":"eth_getBalance","params":["0x123463a4b065722e99115d6c222f267d9cabb524","latest"],"id":1,"jsonrpc":"2.0"}' \
  http://localhost:8545
```

### 进入 Geth 控制台

```bash
# Node1 控制台
docker exec -it geth-node1 geth attach --datadir /data

# Node2 控制台
docker exec -it geth-node2 geth attach --datadir /data

# 在控制台中执行
> net.peerCount        # 查看连接的节点数
> eth.blockNumber      # 查看当前区块高度
> eth.accounts         # 查看账户列表
> admin.peers          # 查看连接的节点详情
```

### 停止网络

```bash
docker-compose down -v
```

---

## 🔥 方案二：完整 PoS 网络 (Kurtosis)

### 特点

- ✅ **真实 PoS**：完整的执行层 + 共识层架构
- ✅ **多客户端**：Geth + Lighthouse
- ✅ **验证器**：真实的验证器节点
- ✅ **监控工具**：内置区块浏览器和监控

### 快速启动

```bash
# 1. 安装 Kurtosis
curl -fsSL https://docs.kurtosis.com/install.sh | bash

# 2. 启动 PoS 网络
./start-pos-network.sh

# 3. 查看服务
kurtosis enclave ls
kurtosis port list <enclave-name>
```

## 📊 两种方案对比

| 特性     | PoA 多节点 | PoS 网络      |
| -------- | ---------- | ------------- |
| 复杂度   | 简单       | 复杂          |
| 启动时间 | 快 (30 秒) | 慢 (2-3 分钟) |
| 资源消耗 | 低         | 中等          |
| 学习价值 | Geth 基础  | 现代以太坊    |
| 适用场景 | 开发测试   | 生产模拟      |

## 🛠️ 开发测试

### MetaMask 配置

**PoA 网络配置：**

- 网络名称: `Geth PoA Private`
- RPC URL: `http://localhost:8545`
- 链 ID: `12345`
- 货币符号: `ETH`

### 预置账户

- **签名者账户**: `0x123463a4b065722e99115d6c222f267d9cabb524`
- **密码**: `testpassword123`
- **预置余额**: 很多 ETH

### 发送交易示例

```javascript
// 使用 ethers.js
const { ethers } = require("ethers");

const provider = new ethers.JsonRpcProvider("http://localhost:8545");
const wallet = new ethers.Wallet("您的私钥", provider);

// 发送交易
const tx = await wallet.sendTransaction({
  to: "0x456789a4b065722e99115d6c222f267d9cabb999",
  value: ethers.parseEther("1.0"),
});

console.log("交易哈希:", tx.hash);
```

## 🔍 故障排除

### 常见问题

1. **端口被占用**

   ```bash
   # 检查端口使用情况
   lsof -i :8545

   # 停止占用端口的进程
   docker-compose down
   ```

2. **节点无法连接**

   ```bash
   # 查看节点日志
   docker-compose logs geth-node1

   # 重启网络
   ./start-geth-network.sh
   ```

3. **Docker 相关问题**

   ```bash
   # 清理 Docker 资源
   docker system prune -f

   # 重新拉取镜像
   docker-compose pull
   ```

## 📁 文件结构

```
private-ethereum-network/
├── config/                      # 网络配置文件
│   ├── genesis.json            # PoA 创世配置
│   ├── password.txt            # 账户密码
│   └── keystore/               # 签名者账户
├── docker-compose.yml          # Docker 编排文件
├── start-geth-network.sh       # PoA 网络启动脚本
├── start-pos-network.sh        # PoS 网络启动脚本
├── kurtosis-setup.yaml         # Kurtosis 配置
├── README-PoS.md              # PoS 详细说明
└── README.md                   # 本文件
```

## 🎯 学习路径建议

1. **初学者**：从 PoA 多节点网络开始，理解 Geth 基础概念
2. **进阶者**：尝试 PoS 网络，体验现代以太坊架构
3. **开发者**：使用两种网络进行 DApp 开发和测试

## 📚 参考资料

- [Geth 官方文档](https://geth.ethereum.org/docs/)
- [以太坊 PoA 规范](https://eips.ethereum.org/EIPS/eip-225)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [Kurtosis 文档](https://docs.kurtosis.com/)
