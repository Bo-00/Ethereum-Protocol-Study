# 以太坊状态存储：MPT 与 LevelDB 深度解析

## 1. 核心概念

### 1.1 什么是世界状态 (World State)

**世界状态**是以太坊的"硬盘"，存储了所有账户的状态信息。它是地址到账户状态的映射，包含：

- 所有外部账户(EOA)的余额、nonce
- 所有合约账户的代码、存储数据
- 所有账户的状态信息

### 1.2 MPT 与 LevelDB 的关系

```
应用层：StateDB (状态管理)
     ↓
逻辑层：MPT树 (数据组织，计算哈希)
     ↓
存储层：LevelDB (物理存储k-v数据)
```

- **MPT**：负责数据的逻辑组织和哈希计算
- **LevelDB**：负责物理存储 MPT 节点数据
- **关系**：MPT 节点序列化后以 key-value 形式存储在 LevelDB 中

## 2. 四种关键的 MPT 树

### 2.1 世界状态树 (World State Trie)

```go
// 存储：地址 -> 账户状态
Key:   account_address (20字节)
Value: RLP([nonce, balance, storageRoot, codeHash])
```

**用途**：存储所有账户的状态信息

### 2.2 账户存储树 (Account Storage Trie)

```go
// 存储：存储槽位 -> 存储值
Key:   storage_key (32字节)
Value: storage_value (32字节)
```

**用途**：存储智能合约的状态变量

### 2.3 交易树 (Transaction Trie)

```go
// 存储：交易索引 -> 交易数据
Key:   transaction_index
Value: RLP(transaction_data)
```

**用途**：存储区块中的所有交易

### 2.4 收据树 (Receipt Trie)

```go
// 存储：交易索引 -> 交易收据
Key:   transaction_index
Value: RLP(receipt_data)
```

**用途**：存储交易执行结果

## 3. 完整的数据流转过程

### 3.1 接收新区块的处理流程

```
1. 验证节点接收到新区块
       ↓
2. 验证区块头和交易合法性
       ↓
3. 执行区块中的每个交易
       ↓
4. 更新账户状态和存储状态
       ↓
5. 重新计算世界状态树根哈希
       ↓
6. 验证状态根哈希是否匹配
       ↓
7. 提交新状态到LevelDB
```

### 3.2 交易执行过程

```go
// 伪代码展示交易执行流程
func ExecuteTransaction(tx *Transaction, state *StateDB) {
    // 1. 获取发送者账户
    sender := state.GetAccount(tx.From)

    // 2. 验证nonce和余额
    if sender.Nonce != tx.Nonce || sender.Balance < tx.Value + tx.Gas*tx.GasPrice {
        return ErrInvalidTx
    }

    // 3. 扣除gas费用
    sender.Balance -= tx.Gas * tx.GasPrice
    sender.Nonce++

    // 4. 执行交易逻辑
    if tx.To == nil {
        // 合约创建
        contractAddr := CreateContract(tx.Data, state)
    } else {
        // 转账或合约调用
        recipient := state.GetAccount(tx.To)
        recipient.Balance += tx.Value

        if len(tx.Data) > 0 {
            // 调用合约
            ExecuteContract(tx.To, tx.Data, state)
        }
    }

    // 5. 更新状态树
    state.UpdateTrie()
}
```

### 3.3 状态持久化过程

```go
// 完整的状态提交流程
func CommitState(stateDB *StateDB, trieDB *triedb.Database) common.Hash {
    // 1. 收集所有脏状态对象
    for addr, stateObj := range stateDB.stateObjects {
        if stateObj.dirty {
            // 更新账户存储树
            storageRoot := stateObj.CommitTrie(trieDB)

            // 更新账户状态
            account := Account{
                Nonce:       stateObj.nonce,
                Balance:     stateObj.balance,
                StorageRoot: storageRoot,
                CodeHash:    stateObj.codeHash,
            }

            // 写入世界状态树
            stateDB.trie.Update(addr.Bytes(), rlp.Encode(account))
        }
    }

    // 2. 提交世界状态树
    root, nodes := stateDB.trie.Commit(true)

    // 3. 将节点写入数据库
    if nodes != nil {
        trieDB.Update(root, common.Hash{}, 0, nodes, nil)
        trieDB.Commit(root, false)
    }

    return root
}
```

## 4. LevelDB 存储细节

### 4.1 存储格式

LevelDB 中存储的数据格式：

```go
// MPT节点存储
Key:   节点的SHA3哈希值 (32字节)
Value: RLP编码的节点内容

// 状态根存储
Key:   "stateRoot:" + 区块号
Value: 世界状态树根哈希

// 代码存储
Key:   "code:" + 代码哈希
Value: 合约字节码
```

### 4.2 数据查询过程

```go
// 查询账户余额的完整过程
func GetBalance(addr common.Address, stateRoot common.Hash, db *leveldb.DB) *big.Int {
    // 1. 创建世界状态树
    stateTrie := trie.New(stateRoot, triedb.NewDatabase(db))

    // 2. 从世界状态树查询账户
    accountData := stateTrie.Get(addr.Bytes())
    if accountData == nil {
        return big.NewInt(0)
    }

    // 3. 解码账户状态
    var account Account
    rlp.Decode(bytes.NewReader(accountData), &account)

    return account.Balance
}
```

## 5. 关键问题解答

### 5.1 为什么需要 MPT 而不直接用 LevelDB？

1. **默克尔证明**：MPT 提供高效的状态证明，轻客户端可以验证状态
2. **状态完整性**：根哈希可以验证整个状态的完整性
3. **历史追溯**：通过根哈希可以访问历史状态
4. **结构化组织**：MPT 提供了有序的数据组织方式

### 5.2 状态同步如何工作？

```go
// 快速同步状态的过程
func FastSync(targetStateRoot common.Hash, db *leveldb.DB) {
    // 1. 请求目标状态的所有节点
    missingNodes := []common.Hash{targetStateRoot}

    for len(missingNodes) > 0 {
        // 2. 从其他节点请求缺失的节点
        nodes := RequestNodes(missingNodes)

        // 3. 验证并存储节点
        for hash, nodeData := range nodes {
            if verifyNode(hash, nodeData) {
                db.Put(hash.Bytes(), nodeData)
            }
        }

        // 4. 找出还需要的子节点
        missingNodes = findMissingChildren(nodes)
    }
}
```

## 6. 性能优化

### 6.1 缓存机制

```go
type StateDB struct {
    trie              Trie                    // 世界状态树
    stateObjects      map[common.Address]*stateObject  // 第一级缓存
    stateObjectsDirty map[common.Address]struct{}      // 脏状态标记

    // 快照缓存
    snap snapshot.Snapshot

    // 预取机制
    prefetcher *triePrefetcher
}
```

### 6.2 批量操作

```go
// 批量提交优化
func BatchCommit(updates map[common.Hash][]byte, db *leveldb.DB) {
    batch := db.NewBatch()

    for hash, data := range updates {
        batch.Put(hash.Bytes(), data)
    }

    // 一次性写入所有更新
    return batch.Write()
}
```

## 7. 实际应用示例

### 7.1 简单转账交易的完整流程

```go
func TransferETH(from, to common.Address, amount *big.Int, state *StateDB) {
    // 1. 获取发送方状态
    fromAccount := state.GetOrNewStateObject(from)
    fromAccount.Balance = new(big.Int).Sub(fromAccount.Balance, amount)
    fromAccount.Nonce++

    // 2. 更新接收方状态
    toAccount := state.GetOrNewStateObject(to)
    toAccount.Balance = new(big.Int).Add(toAccount.Balance, amount)

    // 3. 标记状态对象为脏
    state.stateObjectsDirty[from] = struct{}{}
    state.stateObjectsDirty[to] = struct{}{}

    // 4. 最终提交时这些更改会写入MPT和LevelDB
}
```

### 7.2 合约调用的状态变更

```go
func CallContract(contractAddr common.Address, input []byte, state *StateDB) {
    // 1. 获取合约账户
    contract := state.GetStateObject(contractAddr)

    // 2. 执行合约代码
    ret, err := evm.Call(contract, input)

    // 3. 合约执行过程中的存储变更会自动更新Storage Trie
    // 4. 所有变更最终在区块提交时写入LevelDB
}
```

## 8. 总结

### 8.1 关键要点

1. **世界状态**是以太坊的全局状态，包含所有账户信息
2. **MPT 提供逻辑组织**，LevelDB 提供物理存储
3. **四种树各司其职**：状态树、存储树、交易树、收据树
4. **完整流程**：交易执行 → 状态更新 → MPT 重计算 → LevelDB 持久化

### 8.2 数据流总览

```
用户交易 → StateDB → MPT节点更新 → 序列化 → LevelDB存储
   ↑                                              ↓
区块验证 ← 状态根哈希 ← MPT根节点 ← 反序列化 ← LevelDB查询
```

### 8.3 参考资料

- [以太坊黄皮书](https://ethereum.github.io/yellowpaper/paper.pdf)
- [Go-Ethereum 源码](https://github.com/ethereum/go-ethereum)
- [MPT 详细解释](https://medium.com/@eiki1212/ethereum-state-trie-architecture-explained-a30237009d4e)
- [以太坊世界状态解析](https://mirror.xyz/iamdk.eth/wpSkFjfJFhtOWW6nWXPPk0kU4V6gZHifSGKd-O-1Xd0)
