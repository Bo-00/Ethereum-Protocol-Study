# Engine API 学习笔记

## 概述

Engine API 是以太坊执行层客户端（如 Geth）与共识层客户端（如 Prysm、Lighthouse）之间通信的核心接口。自以太坊合并（The Merge）以来，Engine API 成为了以太坊架构中的关键组件，负责协调区块验证、区块提议等重要任务。

## 架构作用

```
                    共识层 (Consensus Layer)
                           |
                    Engine API (gRPC/HTTP)
                           |
                    执行层 (Execution Layer)
```

- **共识层**: 负责 PoS 共识、区块验证、验证者管理
- **执行层**: 负责交易执行、状态管理、EVM 运行
- **Engine API**: 两层之间的桥梁，提供标准化通信协议

## 核心方法

### 1. ForkchoiceUpdated 系列

#### `engine_forkchoiceUpdatedV1/V2/V3`

**作用**: 更新执行层的分叉选择，通知当前的头区块、安全区块和最终区块

**关键参数**:

- `ForkchoiceStateV1`: 包含头区块、安全区块、最终区块的哈希
- `PayloadAttributes`: 可选，用于启动区块构建过程

**go-ethereum 实现关键代码**:

```go:206:259:go-ethereum/eth/catalyst/api.go
func (api *ConsensusAPI) ForkchoiceUpdatedV1(update engine.ForkchoiceStateV1, payloadAttributes *engine.PayloadAttributes) (engine.ForkChoiceResponse, error) {
	if payloadAttributes != nil {
		switch {
		case payloadAttributes.Withdrawals != nil || payloadAttributes.BeaconRoot != nil:
			return engine.STATUS_INVALID, paramsErr("withdrawals and beacon root not supported in V1")
		case !api.checkFork(payloadAttributes.Timestamp, forks.Paris, forks.Shanghai):
			return engine.STATUS_INVALID, paramsErr("fcuV1 called post-shanghai")
		}
	}
	return api.forkchoiceUpdated(update, payloadAttributes, engine.PayloadV1, false)
}
```

**核心逻辑**:

1. 验证新的头区块是否存在
2. 检查是否需要同步
3. 设置规范链头部
4. 设置最终区块和安全区块
5. 如果提供了 PayloadAttributes，启动区块构建

### 2. NewPayload 系列

#### `engine_newPayloadV1/V2/V3/V4`

**作用**: 接收共识层发送的新区块载荷，执行层验证并导入区块

**关键参数**:

- `ExecutableData`: 包含区块的所有执行数据
- `versionedHashes`: Blob 交易的版本化哈希（V3+）
- `beaconRoot`: 信标根（V3+）

**go-ethereum 实现关键代码**:

```go:660:777:go-ethereum/eth/catalyst/api.go
func (api *ConsensusAPI) newPayload(params engine.ExecutableData, versionedHashes []common.Hash, beaconRoot *common.Hash, requests [][]byte, witness bool) (engine.PayloadStatusV1, error) {
	// 加锁防止并发处理相同载荷
	api.newPayloadLock.Lock()
	defer api.newPayloadLock.Unlock()

	// 转换为区块对象
	block, err := engine.ExecutableDataToBlock(params, versionedHashes, beaconRoot, requests)
	if err != nil {
		return api.invalid(err, nil), nil
	}

	// 检查是否已经存在
	if block := api.eth.BlockChain().GetBlockByHash(params.BlockHash); block != nil {
		hash := block.Hash()
		return engine.PayloadStatusV1{Status: engine.VALID, LatestValidHash: &hash}, nil
	}

	// 检查父区块
	parent := api.eth.BlockChain().GetBlock(block.ParentHash(), block.NumberU64()-1)
	if parent == nil {
		return api.delayPayloadImport(block), nil
	}

	// 插入区块（不设置为头部）
	proofs, err := api.eth.BlockChain().InsertBlockWithoutSetHead(block, witness)
	if err != nil {
		return api.invalid(err, parent.Header()), nil
	}

	hash := block.Hash()
	return engine.PayloadStatusV1{Status: engine.VALID, LatestValidHash: &hash}, nil
}
```

### 3. GetPayload 系列

#### `engine_getPayloadV1/V2/V3/V4/V5`

**作用**: 获取之前 ForkchoiceUpdated 调用构建的载荷

**关键参数**:

- `PayloadID`: 载荷标识符

**返回数据**:

- `ExecutionPayload`: 区块执行数据
- `BlockValue`: 区块价值（V2+）
- `BlobsBundle`: Blob 数据包（V3+）

### 4. 其他重要方法

- `engine_exchangeCapabilities`: 交换客户端支持的方法列表
- `engine_getPayloadBodiesByHash/Range`: 按哈希或范围获取区块体
- `engine_getClientVersionV1`: 获取客户端版本信息

## 状态类型

Engine API 定义了几种关键状态：

```go:51:85:go-ethereum/beacon/engine/errors.go
var (
	// VALID: 载荷有效且已执行
	VALID = "VALID"

	// INVALID: 载荷无效，执行失败
	INVALID = "INVALID"

	// SYNCING: 客户端正在同步，暂时无法处理
	SYNCING = "SYNCING"

	// ACCEPTED: 载荷被接受但未处理（侧链）
	ACCEPTED = "ACCEPTED"
)
```

## 核心数据结构

### PayloadAttributes

```go:42:49:go-ethereum/beacon/engine/types.go
type PayloadAttributes struct {
	Timestamp             uint64              `json:"timestamp"`
	Random                common.Hash         `json:"prevRandao"`
	SuggestedFeeRecipient common.Address      `json:"suggestedFeeRecipient"`
	Withdrawals           []*types.Withdrawal `json:"withdrawals"`
	BeaconRoot            *common.Hash        `json:"parentBeaconBlockRoot"`
}
```

### ExecutableData

```go:54:76:go-ethereum/beacon/engine/types.go
type ExecutableData struct {
	ParentHash       common.Hash             `json:"parentHash"`
	FeeRecipient     common.Address          `json:"feeRecipient"`
	StateRoot        common.Hash             `json:"stateRoot"`
	ReceiptsRoot     common.Hash             `json:"receiptsRoot"`
	LogsBloom        []byte                  `json:"logsBloom"`
	Random           common.Hash             `json:"prevRandao"`
	Number           uint64                  `json:"blockNumber"`
	GasLimit         uint64                  `json:"gasLimit"`
	GasUsed          uint64                  `json:"gasUsed"`
	Timestamp        uint64                  `json:"timestamp"`
	ExtraData        []byte                  `json:"extraData"`
	BaseFeePerGas    *big.Int                `json:"baseFeePerGas"`
	BlockHash        common.Hash             `json:"blockHash"`
	Transactions     [][]byte                `json:"transactions"`
	Withdrawals      []*types.Withdrawal     `json:"withdrawals"`
	BlobGasUsed      *uint64                 `json:"blobGasUsed"`
	ExcessBlobGas    *uint64                 `json:"excessBlobGas"`
	ExecutionWitness *types.ExecutionWitness `json:"executionWitness,omitempty"`
}
```

## 典型工作流程

### 1. 节点启动流程

```
CL -> EL: engine_exchangeCapabilities()
EL -> CL: [支持的方法列表]

CL -> EL: engine_forkchoiceUpdatedV2(ForkchoiceState, null)
EL -> CL: {status: SYNCING/VALID, payloadId: null}
```

### 2. 区块构建流程

```
验证者被选中提议区块
↓
CL -> EL: engine_forkchoiceUpdatedV2(ForkchoiceState, PayloadAttributes)
EL -> CL: {status: VALID, payloadId: buildProcessId}
↓
EL 开始构建执行载荷
↓
CL -> EL: engine_getPayloadV2(PayloadId)
EL -> CL: {executionPayload, blockValue}
↓
CL 完成信标区块并传播
```

### 3. 区块验证流程

```
接收新的信标区块
↓
提取 ExecutionPayload
↓
CL -> EL: engine_newPayloadV2(ExecutionPayload)
EL -> CL: {status: VALID/INVALID/SYNCING/ACCEPTED}
↓
如果 VALID，调用 forkchoiceUpdated 更新头部
```

## 完整工作流程（包含边界情况）

### 4. 节点启动详细流程

```
启动阶段 - EL 可能正在同步
CL -> EL: engine_exchangeCapabilities()
EL -> CL: [支持的方法列表]

CL -> EL: engine_forkchoiceUpdatedV2(ForkchoiceState, null)
情况A: EL同步中
EL -> CL: {status: SYNCING, payloadId: null}
等待...

情况B: EL同步完成
EL -> CL: {status: VALID, payloadId: null}
```

### 5. 区块构建完整流程

```
验证者被选中 → 开始构建
CL -> EL: engine_forkchoiceUpdatedV2(ForkchoiceState, PayloadAttributes)

成功情况:
EL -> CL: {status: VALID, payloadId: buildProcessId}
EL 后台构建载荷...

错误情况A - 无效的 PayloadAttributes:
EL -> CL: {status: INVALID} + 错误详情

错误情况B - HeadBlockHash 未知:
EL -> CL: {status: SYNCING} + 开始同步

获取载荷:
CL -> EL: engine_getPayloadV2(PayloadId)

成功:
EL -> CL: {executionPayload, blockValue, blobsBundle}

失败:
EL -> CL: Error: Unknown payload ID
```

### 6. 区块验证完整流程

```
接收信标区块 → 验证载荷
CL -> EL: engine_newPayloadV2(ExecutionPayload)

情况A - 载荷有效:
EL -> CL: {status: VALID, latestValidHash: blockHash}

情况B - 载荷无效:
EL -> CL: {status: INVALID, latestValidHash: parentHash}

情况C - 父区块缺失:
EL -> CL: {status: SYNCING}
EL 缓存载荷，等待 FCU

情况D - 浅状态客户端:
EL -> CL: {status: ACCEPTED}  // 非规范链载荷

情况E - EL 同步中:
EL -> CL: {status: SYNCING}

后续分叉选择更新:
CL -> EL: engine_forkchoiceUpdatedV2(newHead, null)
EL 处理链重组并设置新头部
```

### 7. 错误恢复流程

```
处理无效祖先区块:
1. EL 检测到坏区块
2. 标记所有后续区块为无效
3. 返回最后有效区块哈希
4. CL 回退到安全状态

分叉切换:
1. CL 检测到更强分叉
2. 发送新的 ForkchoiceUpdated
3. EL 执行链重组
4. 更新规范链头部
```

### 8. 验证者完整生命周期

```
完整时间轴流程:

节点启动:
CL -> EL: engine_exchangeCapabilities()
CL -> EL: engine_forkchoiceUpdatedV2(初始状态, null)

正常运行 - 非提议时段:
接收区块 -> NewPayload -> ForkchoiceUpdated(更新头部, null)

验证者被选中:
提前构建 -> ForkchoiceUpdated(当前头部, PayloadAttributes)
等待时机 -> GetPayload(获取构建好的载荷)
提交区块 -> 广播到网络

其他验证者验证:
接收区块 -> NewPayload(验证载荷)
-> ForkchoiceUpdated(更新分叉选择)

异常处理:
同步状态 -> 延迟处理载荷
无效载荷 -> 回退到安全状态
网络分叉 -> 重组选择最强链
```

### 9. 同步状态处理

```
初始同步:
EL 状态: SYNCING
- 所有 ForkchoiceUpdated 返回 SYNCING
- NewPayload 缓存但不执行
- 等待同步完成

同步完成:
EL 状态: SYNCED
- 开始正常处理 API 调用
- 执行缓存的载荷
- 恢复区块构建能力

同步中断恢复:
- 检测到缺失的父区块
- 自动触发 BeaconSync
- 从已知点继续同步
```

### 10. 特殊客户端处理

```
浅状态客户端 (如 Erigon):
规范链载荷:
NewPayload -> 立即验证 -> VALID/INVALID

非规范链载荷:
NewPayload -> 无法验证完整状态 -> ACCEPTED
等待 ForkchoiceUpdated 切换到该链后再验证

全节点客户端:
所有载荷都能完整验证
返回明确的 VALID/INVALID 状态
```

## go-ethereum 中的实现架构

### ConsensusAPI 结构

```go:131:165:go-ethereum/eth/catalyst/api.go
type ConsensusAPI struct {
	eth *eth.Ethereum

	remoteBlocks *headerQueue  // 缓存接收到的远程载荷
	localBlocks  *payloadQueue // 缓存本地生成的载荷

	// 无效区块跟踪机制
	invalidBlocksHits map[common.Hash]int
	invalidTipsets    map[common.Hash]*types.Header
	invalidLock       sync.Mutex

	// 心跳检测机制
	lastTransitionUpdate atomic.Int64
	lastForkchoiceUpdate atomic.Int64
	lastNewPayloadUpdate atomic.Int64

	forkchoiceLock sync.Mutex // ForkchoiceUpdated 方法锁
	newPayloadLock sync.Mutex // NewPayload 方法锁
}
```

### API 注册

```go:49:58:go-ethereum/eth/catalyst/api.go
func Register(stack *node.Node, backend *eth.Ethereum) error {
	log.Warn("Engine API enabled", "protocol", "eth")
	stack.RegisterAPIs([]rpc.API{
		{
			Namespace:     "engine",
			Service:       NewConsensusAPI(backend),
			Authenticated: true, // 需要认证
		},
	})
	return nil
}
```

## 版本演进

- **V1**: 基础 Engine API，支持 Paris 硬分叉
- **V2**: 增加提款支持（Shanghai 硬分叉）
- **V3**: 增加 Blob 交易和信标根支持（Cancun 硬分叉）
- **V4**: 增加执行请求支持（Prague 硬分叉）

## 安全考量

1. **身份验证**: Engine API 使用 JWT token 进行身份验证
2. **端口隔离**: 通常运行在单独的认证端口（默认 8551）
3. **错误处理**: 严格的参数验证和错误返回
4. **同步状态**: 处理客户端同步状态的各种边界情况

## 实际应用场景

1. **节点同步**: 新节点加入网络时的同步过程
2. **区块验证**: 验证者验证接收到的区块
3. **区块构建**: 验证者被选中时构建新区块
4. **分叉处理**: 处理链重组和分叉选择

## 参考资源

- [官方 Engine API 规范](https://github.com/ethereum/execution-apis/blob/main/src/engine)
- [Engine API 可视化指南](https://hackmd.io/@danielrachi/engine_api)
- [以太坊合并文档](https://ethereum.org/en/upgrades/merge/)
- go-ethereum 源码: `eth/catalyst/` 和 `beacon/engine/` 包

## 总结

Engine API 是以太坊 PoS 架构的核心，它实现了执行层和共识层的解耦，使得客户端多样性成为可能。理解 Engine API 对于深入理解以太坊的工作原理，以及开发相关工具都具有重要意义。其设计充分考虑了安全性、可扩展性和向后兼容性，为以太坊的未来发展奠定了坚实基础。
