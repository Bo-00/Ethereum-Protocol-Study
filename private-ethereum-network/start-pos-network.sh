#!/bin/bash

# Ethereum PoS 私有网络启动脚本
# 使用最新的 ethereum-package

echo "🚀 启动 Ethereum PoS 私有网络..."

# 检查 Kurtosis 是否安装
if ! command -v kurtosis &> /dev/null; then
    echo "❌ Kurtosis 未安装"
    echo "请先安装 Kurtosis："
    echo "brew install kurtosis-tech/tap/kurtosis-cli"
    exit 1
fi

# 检查 Docker 是否运行
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker 未运行，请先启动 Docker"
    exit 1
fi

echo "📋 网络配置："
echo "- 执行层：Geth"
echo "- 共识层：Lighthouse"  
echo "- 节点数：2个节点对"
echo "- 验证器：每个节点 64 个验证器"
echo "- 网络 ID：12345"
echo "- 包含区块浏览器 (Dora) 和监控服务 (Prometheus/Grafana)"
echo "- 基于最新的 ethereum-package"
echo ""

# 检查是否有旧的网络在运行
echo "🔍 检查现有网络..."
EXISTING_ENCLAVES=$(kurtosis enclave ls 2>/dev/null | grep -v "Name" | awk '{print $1}' | wc -l)
if [ "$EXISTING_ENCLAVES" -gt 0 ]; then
    echo "⚠️  检测到现有网络，正在清理..."
    kurtosis clean -a
fi

# 启动网络
echo "🔄 启动 PoS 网络..."
kurtosis run github.com/ethpandaops/ethereum-package \
    --args-file ./kurtosis-setup.yaml \
    --image-download always

# 检查启动状态
if [ $? -eq 0 ]; then
    echo ""
    echo "✅ PoS 私有网络启动成功！"
    echo ""
    
    # 获取网络名称
    ENCLAVE_NAME=$(kurtosis enclave ls | grep -v "Name" | head -1 | awk '{print $1}')
    
    if [ ! -z "$ENCLAVE_NAME" ]; then
        echo "🌐 网络名称：$ENCLAVE_NAME"
        echo ""
        echo "📊 服务访问："
        echo "获取端口信息：kurtosis port list $ENCLAVE_NAME"
        echo ""
        kurtosis port list $ENCLAVE_NAME 2>/dev/null || echo "正在启动服务，请稍后查看端口..."
    fi
    
    echo ""
    echo "🔧 管理命令："
    echo "- 查看所有网络：kurtosis enclave ls"
    echo "- 查看端口映射：kurtosis port list $ENCLAVE_NAME"
    echo "- 查看服务：kurtosis service ls $ENCLAVE_NAME"
    echo "- 查看日志：kurtosis service logs $ENCLAVE_NAME [service-name]"
    echo "- 进入服务：kurtosis service shell $ENCLAVE_NAME [service-name]"
    echo "- 停止网络：kurtosis enclave stop $ENCLAVE_NAME"
    echo "- 删除网络：kurtosis enclave rm $ENCLAVE_NAME"
    echo "- 清理所有：kurtosis clean -a"
    echo ""
    echo "📖 更多信息请查看：https://github.com/ethpandaops/ethereum-package"
    echo ""
    echo "🎯 预置账户信息可以在以下链接找到："
    echo "https://github.com/ethpandaops/ethereum-package#pre-funded-accounts-at-genesis"
else
    echo "❌ 网络启动失败，请检查错误信息"
    echo "💡 尝试运行 'kurtosis clean -a' 清理后重试"
    exit 1
fi 