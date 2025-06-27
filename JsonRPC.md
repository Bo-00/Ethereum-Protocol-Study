# JSON-RPC 学习笔记

## 概述

JSON-RPC 是一个无状态、轻量级的远程过程调用（RPC）协议。它定义了一些数据结构及其处理规则。JSON-RPC 是传输无关的，可以在同一进程内、sockets、HTTP 或多种消息传递环境中使用。

在以太坊生态中，JSON-RPC 是客户端与节点通信的标准协议，为 DApp 提供了访问区块链数据和操作的统一接口。

## JSON-RPC 2.0 协议规范

### 基本概念

- **无状态**: 每个请求都包含执行所需的全部信息
- **传输无关**: 可以使用 HTTP、WebSocket、IPC 等传输
- **基于 JSON**: 使用 JSON 格式进行数据交换

### 消息格式

#### 请求格式

```json
{
  "jsonrpc": "2.0",
  "method": "subtract",
  "params": [42, 23],
  "id": 1
}
```

#### 响应格式

```json
{
  "jsonrpc": "2.0",
  "result": 19,
  "id": 1
}
```

#### 错误响应

```json
{
  "jsonrpc": "2.0",
  "error": {
    "code": -32602,
    "message": "Invalid params"
  },
  "id": 1
}
```

### 批量请求

```json
[
  { "jsonrpc": "2.0", "method": "sum", "params": [1, 2, 4], "id": "1" },
  { "jsonrpc": "2.0", "method": "notify_hello", "params": [7] },
  { "jsonrpc": "2.0", "method": "subtract", "params": [42, 23], "id": "2" }
]
```

## go-ethereum 中的 JSON-RPC 实现

### 整体架构

go-ethereum 的 RPC 包实现了完整的 JSON-RPC 2.0 协议，具有以下特点：

- **多传输支持**: HTTP、WebSocket、IPC、In-Process
- **服务注册**: 基于反射的服务自动注册
- **订阅支持**: pub/sub 模式的实时通知
- **双向通信**: 支持反向调用
- **并发安全**: 支持多 goroutine 并发处理

### 核心组件

#### 1. Server 组件

```go:59:94:go-ethereum/rpc/server.go
// NewServer creates a new server instance with no registered handlers.
func NewServer() *Server {
	server := &Server{
		idgen:         randomIDGenerator(),
		codecs:        make(map[ServerCodec]struct{}),
		httpBodyLimit: defaultBodyLimit,
	}
	server.run.Store(true)
	// Register the default service providing meta information about the RPC service such
	// as the services and methods it offers.
	rpcService := &RPCService{server}
	server.RegisterName(MetadataApi, rpcService)
	return server
}
```

**Server 特点**:

- 管理多个 `ServerCodec` 连接
- 提供服务注册机制
- 支持批量请求限制
- 自动注册元信息服务（`rpc_modules`）

#### 2. Client 组件

```go:163:201:go-ethereum/rpc/client.go
// DialOptions creates a new RPC client for the given URL. You can supply any of the
// pre-defined client options to configure the underlying transport.
//
// The context is used to cancel or time out the initial connection establishment. It does
// not affect subsequent interactions with the client.
//
// The client reconnects automatically when the connection is lost.
func DialOptions(ctx context.Context, rawurl string, options ...ClientOption) (*Client, error) {
	u, err := url.Parse(rawurl)
	if err != nil {
		return nil, err
	}

	cfg := new(clientConfig)
	for _, opt := range options {
		opt.applyOption(cfg)
	}

	var reconnect reconnectFunc
	switch u.Scheme {
	case "http", "https":
		reconnect = newClientTransportHTTP(rawurl, cfg)
	case "ws", "wss":
		rc, err := newClientTransportWS(rawurl, cfg)
		if err != nil {
			return nil, err
		}
		reconnect = rc
	case "stdio":
		reconnect = newClientTransportIO(os.Stdin, os.Stdout)
	case "":
		reconnect = newClientTransportIPC(rawurl)
	default:
		return nil, fmt.Errorf("no known transport for URL scheme %q", u.Scheme)
	}

	return newClient(ctx, cfg, reconnect)
}
```

**Client 特点**:

- 自动重连机制
- 支持多种传输协议
- 批量调用支持
- 订阅功能

#### 3. 服务注册机制

```go:58:85:go-ethereum/rpc/service.go
func (r *serviceRegistry) registerName(name string, rcvr interface{}) error {
	rcvrVal := reflect.ValueOf(rcvr)
	if name == "" {
		return fmt.Errorf("no service name for type %s", rcvrVal.Type().String())
	}
	callbacks := suitableCallbacks(rcvrVal)
	if len(callbacks) == 0 {
		return fmt.Errorf("service %T doesn't have any suitable methods/subscriptions to expose", rcvr)
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if r.services == nil {
		r.services = make(map[string]service)
	}
	svc, ok := r.services[name]
	if !ok {
		svc = service{
			name:          name,
			callbacks:     make(map[string]*callback),
			subscriptions: make(map[string]*callback),
		}
		r.services[name] = svc
	}
	for name, cb := range callbacks {
		if cb.isSubscribe {
			svc.subscriptions[name] = cb
		} else {
			svc.callbacks[name] = cb
		}
	}
	return nil
}
```

**RPC 方法的条件**:

- 方法必须是导出的（首字母大写）
- 返回值必须是 0、1（响应或错误）或 2（响应和错误）个值
- 支持可选参数（指针类型）

### 传输层实现

#### 1. HTTP 传输

```go:126:163:go-ethereum/rpc/http.go
func newClientTransportHTTP(endpoint string, cfg *clientConfig) reconnectFunc {
	headers := make(http.Header, 2+len(cfg.httpHeaders))
	headers.Set("accept", contentType)
	headers.Set("content-type", contentType)
	for key, values := range cfg.httpHeaders {
		headers[key] = values
	}

	client := cfg.httpClient
	if client == nil {
		client = new(http.Client)
	}

	hc := &httpConn{
		client:  client,
		headers: headers,
		url:     endpoint,
		auth:    cfg.httpAuth,
		closeCh: make(chan interface{}),
	}

	return func(ctx context.Context) (ServerCodec, error) {
		return hc, nil
	}
}
```

**HTTP 传输特点**:

- 每个请求都是独立的 HTTP 连接
- 支持 POST 方法，Content-Type 为 `application/json`
- 支持 HTTP 认证
- 不支持订阅功能

#### 2. WebSocket 传输

```go:44:63:go-ethereum/rpc/websocket.go
// WebsocketHandler returns a handler that serves JSON-RPC to WebSocket connections.
//
// allowedOrigins should be a comma-separated list of allowed origin URLs.
// To allow connections with any origin, pass "*".
func (s *Server) WebsocketHandler(allowedOrigins []string) http.Handler {
	var upgrader = websocket.Upgrader{
		ReadBufferSize:  wsReadBuffer,
		WriteBufferSize: wsWriteBuffer,
		WriteBufferPool: wsBufferPool,
		CheckOrigin:     wsHandshakeValidator(allowedOrigins),
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Debug("WebSocket upgrade failed", "err", err)
			return
		}
		codec := newWebsocketCodec(conn, r.Host, r.Header, wsDefaultReadLimit)
		s.ServeCodec(codec, 0)
	})
}
```

**WebSocket 传输特点**:

- 持久连接，支持双向通信
- 支持订阅和推送通知
- Origin 验证机制
- 心跳检测（ping/pong）

#### 3. IPC 传输

```go:27:40:go-ethereum/rpc/ipc.go
// ServeListener accepts connections on l, serving JSON-RPC on them.
func (s *Server) ServeListener(l net.Listener) error {
	for {
		conn, err := l.Accept()
		if netutil.IsTemporaryError(err) {
			log.Warn("RPC accept error", "err", err)
			continue
		} else if err != nil {
			return err
		}
		log.Trace("Accepted RPC connection", "conn", conn.RemoteAddr())
		go s.ServeCodec(NewCodec(conn), 0)
	}
}
```

**IPC 传输特点**:

- Unix Domain Socket（Unix/Linux）或 Named Pipe（Windows）
- 本地进程间通信，性能最高
- 支持所有功能包括订阅

## 以太坊 JSON-RPC API

### API 命名空间

go-ethereum 将 API 按功能分为不同的命名空间：

```go:99:126:go-ethereum/internal/ethapi/backend.go
func GetAPIs(apiBackend Backend) []rpc.API {
	nonceLock := new(AddrLocker)
	return []rpc.API{
		{
			Namespace: "eth",
			Service:   NewEthereumAPI(apiBackend),
		}, {
			Namespace: "eth",
			Service:   NewBlockChainAPI(apiBackend),
		}, {
			Namespace: "eth",
			Service:   NewTransactionAPI(apiBackend, nonceLock),
		}, {
			Namespace: "txpool",
			Service:   NewTxPoolAPI(apiBackend),
		}, {
			Namespace: "debug",
			Service:   NewDebugAPI(apiBackend),
		}, {
			Namespace: "eth",
			Service:   NewEthereumAccountAPI(apiBackend.AccountManager()),
		},
	}
}
```

#### 1. eth 命名空间

- **区块操作**: `eth_getBlockByNumber`, `eth_getBlockByHash`
- **交易操作**: `eth_sendTransaction`, `eth_getTransaction`
- **账户操作**: `eth_getBalance`, `eth_getTransactionCount`
- **状态查询**: `eth_call`, `eth_estimateGas`
- **过滤器**: `eth_newFilter`, `eth_getFilterChanges`

#### 2. admin 命名空间

```go:35:48:go-ethereum/node/api.go
// apis returns the collection of built-in RPC APIs.
func (n *Node) apis() []rpc.API {
	return []rpc.API{
		{
			Namespace: "admin",
			Service:   &adminAPI{n},
		}, {
			Namespace: "debug",
			Service:   debug.Handler,
		}, {
			Namespace: "debug",
			Service:   &p2pDebugAPI{n},
		}, {
			Namespace: "web3",
			Service:   &web3API{n},
		},
	}
}
```

- **节点管理**: `admin_nodeInfo`, `admin_peers`
- **网络管理**: `admin_addPeer`, `admin_removePeer`
- **RPC 管理**: `admin_startHTTP`, `admin_stopHTTP`

#### 3. txpool 命名空间

```go:175:187:go-ethereum/internal/ethapi/api.go
// NewTxPoolAPI creates a new tx pool service that gives information about the transaction pool.
func NewTxPoolAPI(b Backend) *TxPoolAPI {
	return &TxPoolAPI{b}
}
```

- **内存池状态**: `txpool_status`, `txpool_inspect`
- **内容查看**: `txpool_content`, `txpool_contentFrom`

#### 4. debug 命名空间

- **调试工具**: `debug_traceTransaction`, `debug_dumpBlock`
- **存储操作**: `debug_storageRangeAt`
- **性能分析**: `debug_startCPUProfile`, `debug_stopCPUProfile`

### 订阅机制

```go:23:40:go-ethereum/rpc/doc.go
// # Subscriptions
//
// The package also supports the publish subscribe pattern through the use of subscriptions.
// A method that is considered eligible for notifications must satisfy the following
// criteria:
//
//   - method must be exported
//   - first method argument type must be context.Context
//   - method must have return types (rpc.Subscription, error)
//
// An example method:
//
//	func (s *BlockChainService) NewBlocks(ctx context.Context) (rpc.Subscription, error) {
//		...
//	}
//
// When the service containing the subscription method is registered to the server, for
// example under the "blockchain" namespace, a subscription is created by calling the
// "blockchain_subscribe" method.
```

**订阅方法**:

- `eth_subscribe`: 创建订阅
- `eth_unsubscribe`: 取消订阅

**订阅类型**:

- `newHeads`: 新区块头
- `logs`: 日志事件
- `newPendingTransactions`: 新的待处理交易
- `syncing`: 同步状态变化

## 高级特性

### 1. 批量请求

```go:394:434:go-ethereum/rpc/client.go
// BatchCallContext sends all given requests as a single batch and waits for the server
// to return a response for all of them. The wait duration is bounded by the
// context's deadline.
//
// In contrast to CallContext, BatchCallContext only returns errors that have occurred
// while sending the request. Any error specific to a request is reported through the
// Error field of the corresponding BatchElem.
//
// Note that batch calls may not be executed atomically on the server side.
func (c *Client) BatchCallContext(ctx context.Context, b []BatchElem) error {
	var (
		msgs = make([]*jsonrpcMessage, len(b))
		byID = make(map[string]int, len(b))
	)
	op := &requestOp{
		ids:  make([]json.RawMessage, len(b)),
		resp: make(chan []*jsonrpcMessage, 1),
	}
	for i, elem := range b {
		msg, err := c.newMessage(elem.Method, elem.Args...)
		if err != nil {
			return err
		}
		msgs[i] = msg
		op.ids[i] = msg.ID
		byID[string(msg.ID)] = i
	}

	var err error
	if c.isHTTP {
		err = c.sendBatchHTTP(ctx, op, msgs)
	} else {
		err = c.send(ctx, op, msgs)
	}
	if err != nil {
		return err
	}

	batchresp, err := op.wait(ctx, c)
	if err != nil {
		return err
	}

	// Wait for all responses to come back.
	for n := 0; n < len(batchresp); n++ {
		resp := batchresp[n]
		if resp == nil {
			// Ignore null responses. These can happen for batches sent via HTTP.
			continue
		}

		// Find the element corresponding to this response.
		index, ok := byID[string(resp.ID)]
		if !ok {
			continue
		}
		delete(byID, string(resp.ID))

		// Assign result and error.
		elem := &b[index]
		switch {
		case resp.Error != nil:
			elem.Error = resp.Error
		case resp.Result == nil:
			elem.Error = ErrNoResult
		default:
			elem.Error = json.Unmarshal(resp.Result, elem.Result)
		}
	}

	// Check that all expected responses have been received.
	for _, index := range byID {
		elem := &b[index]
		elem.Error = ErrMissingBatchResponse
	}

	return err
}
```

### 2. 安全机制

#### 身份验证

- HTTP Bearer Token 认证
- JWT Token 支持
- Origin 验证（WebSocket）

#### 限制机制

- 批量请求数量限制
- 响应大小限制
- HTTP Body 大小限制

```go:76:88:go-ethereum/rpc/server.go
// SetBatchLimits sets limits applied to batch requests. There are two limits: 'itemLimit'
// is the maximum number of items in a batch. 'maxResponseSize' is the maximum number of
// response bytes across all requests in a batch.
//
// This method should be called before processing any requests via ServeCodec, ServeHTTP,
// ServeListener etc.
func (s *Server) SetBatchLimits(itemLimit, maxResponseSize int) {
	s.batchItemLimit = itemLimit
	s.batchResponseLimit = maxResponseSize
}
```

### 3. 错误处理

```go:127:149:go-ethereum/rpc/json.go
func errorMessage(err error) *jsonrpcMessage {
	msg := &jsonrpcMessage{Version: vsn, ID: null, Error: &jsonError{
		Code:    errcodeDefault,
		Message: err.Error(),
	}}
	ec, ok := err.(Error)
	if ok {
		msg.Error.Code = ec.ErrorCode()
	}
	de, ok := err.(DataError)
	if ok {
		msg.Error.Data = de.ErrorData()
	}
	return msg
}
```

**标准错误码**:

- `-32700`: Parse error
- `-32600`: Invalid Request
- `-32601`: Method not found
- `-32602`: Invalid params
- `-32603`: Internal error

## 性能优化

### 1. 连接池管理

- 复用 HTTP 连接
- WebSocket 连接保持
- 合理的超时设置

### 2. 批量处理

- 批量请求减少网络往返
- 批量响应优化内存使用

### 3. 异步处理

- 非阻塞 I/O
- Goroutine 并发处理
- 管道化请求处理

## 实际应用示例

### 客户端使用示例

```go
// 连接到节点
client, err := rpc.Dial("http://localhost:8545")
if err != nil {
    log.Fatal(err)
}
defer client.Close()

// 单个调用
var result hexutil.Big
err = client.Call(&result, "eth_getBalance", "0x...", "latest")

// 批量调用
batch := []rpc.BatchElem{
    {Method: "eth_getBalance", Args: []interface{}{"0x...", "latest"}, Result: &result1},
    {Method: "eth_getBlockByNumber", Args: []interface{}{"latest", false}, Result: &result2},
}
err = client.BatchCall(batch)

// 订阅
ch := make(chan json.RawMessage)
sub, err := client.EthSubscribe(context.Background(), ch, "newHeads")
```

### 服务端注册示例

```go
// 定义服务
type CalculatorService struct{}

func (s *CalculatorService) Add(a, b int) int {
    return a + b
}

func (s *CalculatorService) Divide(a, b int) (int, error) {
    if b == 0 {
        return 0, errors.New("division by zero")
    }
    return a / b, nil
}

// 注册服务
server := rpc.NewServer()
server.RegisterName("calculator", new(CalculatorService))

// 启动 HTTP 服务
http.Handle("/", server)
http.ListenAndServe(":8080", nil)
```

## 调试和监控

### 1. 日志系统

- 请求/响应日志记录
- 性能指标统计
- 错误率监控

### 2. 指标收集

- 请求计数
- 响应时间
- 错误分布

### 3. 工具链

- `geth attach`: 交互式控制台
- `web3.js`: JavaScript 客户端库
- `ethers.js`: 现代 JavaScript 库

## 最佳实践

### 1. 客户端设计

- 实现重试机制
- 使用连接池
- 合理设置超时
- 错误处理和恢复

### 2. 服务端优化

- 限制并发连接数
- 实现请求限流
- 监控资源使用
- 定期清理过期连接

### 3. 安全考虑

- 启用身份验证
- 限制暴露的方法
- 使用 HTTPS/WSS
- 验证输入参数

## 总结

JSON-RPC 是以太坊生态中的核心通信协议，go-ethereum 的实现提供了：

1. **完整的协议支持**: 严格遵循 JSON-RPC 2.0 规范
2. **多传输层支持**: HTTP、WebSocket、IPC 等
3. **高性能设计**: 并发处理、批量请求、连接复用
4. **安全机制**: 认证、限流、验证等
5. **易用的 API**: 基于反射的服务注册，简化开发

理解 JSON-RPC 的设计和实现对于：

- 开发以太坊 DApp
- 构建节点监控工具
- 实现自定义 RPC 服务
- 优化网络通信性能

都具有重要意义。这为后续开发 MEV 检测工具提供了强大的技术基础。

## 参考资源

- [JSON-RPC 2.0 规范](https://www.jsonrpc.org/specification)
- [以太坊 JSON-RPC API](https://ethereum.org/en/developers/docs/apis/json-rpc/)
- [Go-Ethereum RPC 包文档](https://pkg.go.dev/github.com/ethereum/go-ethereum/rpc)
- go-ethereum 源码: `rpc/`、`internal/ethapi/`、`node/` 包
