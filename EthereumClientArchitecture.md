# Ethereum 客户端架构

## 节点架构

### 基础组成

- **执行层客户端**：Geth、Nethermind、Erigon、Reth、Besu
- **共识层客户端**：Lighthouse、Prysm、Teku、Nimbus
- **Engine API**：连接两层的通信接口

### 为什么必须同时运行两个客户端？

**执行层单独运行的问题**：

- 无法确定正确的链头
- 缺少分叉选择能力
- 无法获得最终确定性

**共识层单独运行的问题**：

- 无法执行交易（没有 EVM）
- 无法维护状态数据
- 无法验证交易有效性

### Validator 为什么是可选的？

- **基础节点**：执行层 + 共识层 = 完整网络参与
- **验证者节点**：需要额外质押 32 ETH + Validator 客户端
- **职责区别**：普通节点验证网络，验证者节点参与共识

## 节点类型

### 全节点 (Full Node)

- 存储所有区块头和区块体
- 维护完整状态数据
- 独立验证所有交易

### 轻节点 (Light Node)

- 仅存储区块头
- 依赖全节点获取数据
- 适合资源受限设备

### 归档节点 (Archive Node)

- 存储所有历史状态
- 支持任意时刻状态查询
- 存储需求最大（~12TB）

## Validator 验证者

### 基本要求

- 质押 32 ETH
- 运行独立的 Validator 客户端
- 生成验证者密钥和提取密钥

### 收益与风险

- **收益**：年化 3-5%（共识奖励 + 交易费）
- **职责**：投票验证、区块提议、保持在线
- **惩罚**：离线扣款、恶意行为 Slashing

### 生命周期

1. **Pending**：等待激活
2. **Active**：正常验证
3. **Exiting**：申请退出
4. **Exited**：资金可提取

## 层架构详解

### 执行层

- **EVM**：执行智能合约
- **State**：维护账户状态
- **TXs Pool**：管理交易队列
- **API**：JSON-RPC 接口

### 共识层

- **LMD-GHOST**：分叉选择算法
- **RANDAO**：随机数生成
- **Beacon APIs**：验证者接口

### 通信机制

共识层产生区块 → Engine API → 执行层执行 → 返回结果 → 共识层确认

## 实际运行

### 启动步骤

1. 先启动共识层客户端
2. 再启动执行层客户端
3. （可选）启动 Validator 客户端

### 端口配置

- 共识层：9000
- 执行层：30303

### 硬件要求

- **CPU**：4+ 核心
- **内存**：16GB+
- **存储**：全节点 1TB，归档节点 12TB
- **网络**：25 Mbps+

---

## 参考资料

- [如何跑起以太坊執行層與共識層客戶端](https://medium.com/swf-lab/%E5%A6%82%E4%BD%95%E8%B7%91%E8%B5%B7%E4%BB%A5%E5%A4%AA%E5%9D%8A%E5%9F%B7%E8%A1%8C%E5%B1%A4%E8%88%87%E5%85%B1%E8%AD%98%E5%B1%A4%E5%AE%A2%E6%88%B6%E7%AB%AF-54d0b472e7ac)
- [Run execution client without consensus client?](https://ethereum.stackexchange.com/questions/148559/run-execution-client-without-consensus-client)
- [Nodes and clients | ethereum.org](https://ethereum.org/en/developers/docs/nodes-and-clients/)
- [Running Ethereum on ARM Documentation](https://ethereum-on-arm-documentation.readthedocs.io/en/latest/quick-guide/running-ethereum.html)

_基于架构图的 Ethereum 协议学习整理_
