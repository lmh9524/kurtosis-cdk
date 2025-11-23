#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# 部署完整 Upgradeable 合约栈到 EC2 Kurtosis CDK 环境
# ==========================================

echo "=========================================="
echo "🚀 部署完整 Upgradeable 合约栈"
echo "=========================================="

# 环境检查
if [ -z "${ETH_RPC_URL:-}" ]; then
    ETH_RPC_URL=$(kurtosis port print cdk proxyd-001 rpc 2>/dev/null || echo "")
    if [ -z "$ETH_RPC_URL" ]; then
        ETH_RPC_URL="http://127.0.0.1:1043"
        echo "⚠️  无法从 Kurtosis 获取 RPC URL，使用默认: $ETH_RPC_URL"
    fi
fi

if [ -z "${ADMIN_ADDR:-}" ]; then
    echo "❌ 错误: 未设置 ADMIN_ADDR 环境变量"
    exit 1
fi

if [ -z "${ADMIN_KEY:-}" ]; then
    echo "❌ 错误: 未设置 ADMIN_KEY 环境变量"
    exit 1
fi

export ETH_RPC_URL
export PRIVATE_KEY="$ADMIN_KEY"

echo "环境参数："
echo "  ADMIN_ADDR: $ADMIN_ADDR"
echo "  ETH_RPC_URL: $ETH_RPC_URL"
echo "  项目根目录: $(pwd)"

# 检查 Foundry
if ! command -v forge &> /dev/null; then
    echo "❌ 错误: 未找到 forge 命令"
    exit 1
fi

echo ""
echo "✅ Foundry 版本信息："
forge --version

# 编译合约
echo ""
echo "📦 编译 VeilChain 合约..."
forge build

# 1. 部署 KYCRegistryUpgradeable（如果还没有）
if [ -z "${KYC_REGISTRY_PROXY_ADDR:-}" ]; then
    echo ""
    echo "📋 步骤 1: 部署 KYCRegistryUpgradeable..."
    export ADMIN_ADDRESS="$ADMIN_ADDR"
    forge script script/DeployKYCRegistryUpgradeable.s.sol:DeployKYCRegistryUpgradeable \
        --rpc-url "$ETH_RPC_URL" \
        --private-key "$ADMIN_KEY" \
        --broadcast \
        --legacy
    
    # 从输出中提取地址（需要手动设置或从 broadcast 文件读取）
    echo "⚠️  请从输出中提取 KYCRegistry Proxy 地址，并设置 KYC_REGISTRY_PROXY_ADDR 环境变量"
    read -p "请输入 KYCRegistry Proxy 地址: " KYC_REGISTRY_PROXY_ADDR
    export KYC_REGISTRY_PROXY_ADDR
else
    echo "✅ KYCRegistry 已部署: $KYC_REGISTRY_PROXY_ADDR"
fi

# 2. 部署 AccessControllerUpgradeable
echo ""
echo "📋 步骤 2: 部署 AccessControllerUpgradeable..."
export KYC_REGISTRY_ADDR="$KYC_REGISTRY_PROXY_ADDR"
forge script script/DeployAccessControllerUpgradeable.s.sol:DeployAccessControllerUpgradeable \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy

# 从 broadcast 文件提取地址（简化版，实际应该解析 JSON）
echo "⚠️  请从输出中提取 AccessController Proxy 地址"
read -p "请输入 AccessController Proxy 地址: " ACCESS_CONTROLLER_PROXY_ADDR
export ACCESS_CONTROLLER_PROXY_ADDR

# 3. 部署 LimitControllerUpgradeable
echo ""
echo "📋 步骤 3: 部署 LimitControllerUpgradeable..."
export KYC_REGISTRY_ADDR="$KYC_REGISTRY_PROXY_ADDR"
forge script script/DeployLimitControllerUpgradeable.s.sol:DeployLimitControllerUpgradeable \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy

echo "⚠️  请从输出中提取 LimitController Proxy 地址"
read -p "请输入 LimitController Proxy 地址: " LIMIT_CONTROLLER_PROXY_ADDR
export LIMIT_CONTROLLER_PROXY_ADDR

# 4. 部署 KYCGuardedTokenUpgradeable
echo ""
echo "📋 步骤 4: 部署 KYCGuardedTokenUpgradeable..."
export ACCESS_CONTROLLER_ADDR="$ACCESS_CONTROLLER_PROXY_ADDR"
export TOKEN_NAME="KYC Guarded Token"
export TOKEN_SYMBOL="KGT"
forge script script/DeployKYCGuardedTokenUpgradeable.s.sol:DeployKYCGuardedTokenUpgradeable \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy

echo "⚠️  请从输出中提取 KYCGuardedToken Proxy 地址"
read -p "请输入 KYCGuardedToken Proxy 地址: " KYC_GUARDED_TOKEN_PROXY_ADDR
export KYC_GUARDED_TOKEN_PROXY_ADDR

# 5. 部署 AssetRegistryUpgradeable
echo ""
echo "📋 步骤 5: 部署 AssetRegistryUpgradeable..."
forge script script/DeployAssetRegistryUpgradeable.s.sol:DeployAssetRegistryUpgradeable \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy

echo "⚠️  请从输出中提取 AssetRegistry Proxy 地址"
read -p "请输入 AssetRegistry Proxy 地址: " ASSET_REGISTRY_PROXY_ADDR
export ASSET_REGISTRY_PROXY_ADDR

# 6. 配置合约间引用
echo ""
echo "📋 步骤 6: 配置合约间引用..."

# 在 KYCGuardedToken 上设置 LimitController（如果需要）
if [ -n "${LIMIT_CONTROLLER_PROXY_ADDR:-}" ]; then
    echo "  设置 KYCGuardedToken.limitController = $LIMIT_CONTROLLER_PROXY_ADDR"
    cast send "$KYC_GUARDED_TOKEN_PROXY_ADDR" \
        "setLimitController(address)" "$LIMIT_CONTROLLER_PROXY_ADDR" \
        --rpc-url "$ETH_RPC_URL" \
        --private-key "$ADMIN_KEY" \
        --legacy
    
    # 授予 KYCGuardedToken CALLER_ROLE
    echo "  授予 KYCGuardedToken CALLER_ROLE..."
    CALLER_ROLE=$(cast call "$LIMIT_CONTROLLER_PROXY_ADDR" "CALLER_ROLE()(bytes32)" --rpc-url "$ETH_RPC_URL" || echo "")
    if [ -n "$CALLER_ROLE" ]; then
        cast send "$LIMIT_CONTROLLER_PROXY_ADDR" \
            "grantRole(bytes32,address)" "$CALLER_ROLE" "$KYC_GUARDED_TOKEN_PROXY_ADDR" \
            --rpc-url "$ETH_RPC_URL" \
            --private-key "$ADMIN_KEY" \
            --legacy
    fi
fi

echo ""
echo "=========================================="
echo "✅ 部署完成！"
echo "=========================================="
echo "合约地址："
echo "  KYCRegistry Proxy: $KYC_REGISTRY_PROXY_ADDR"
echo "  AccessController Proxy: $ACCESS_CONTROLLER_PROXY_ADDR"
echo "  LimitController Proxy: $LIMIT_CONTROLLER_PROXY_ADDR"
echo "  KYCGuardedToken Proxy: $KYC_GUARDED_TOKEN_PROXY_ADDR"
echo "  AssetRegistry Proxy: $ASSET_REGISTRY_PROXY_ADDR"
echo ""
echo "请保存这些地址用于后续测试和验证！"
echo "=========================================="

