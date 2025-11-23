#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# 验证 Upgradeable 合约栈功能
# ==========================================

echo "=========================================="
echo "🔍 验证 Upgradeable 合约栈"
echo "=========================================="

# 环境检查
if [ -z "${ETH_RPC_URL:-}" ]; then
    ETH_RPC_URL=$(kurtosis port print cdk proxyd-001 rpc 2>/dev/null || echo "")
    if [ -z "$ETH_RPC_URL" ]; then
        ETH_RPC_URL="http://127.0.0.1:1043"
    fi
fi

if [ -z "${ADMIN_ADDR:-}" ]; then
    echo "❌ 错误: 未设置 ADMIN_ADDR 环境变量"
    exit 1
fi

if [ -z "${KYC_REGISTRY_PROXY_ADDR:-}" ] || \
   [ -z "${ACCESS_CONTROLLER_PROXY_ADDR:-}" ] || \
   [ -z "${LIMIT_CONTROLLER_PROXY_ADDR:-}" ] || \
   [ -z "${KYC_GUARDED_TOKEN_PROXY_ADDR:-}" ]; then
    echo "❌ 错误: 未设置所有必需的合约地址环境变量"
    exit 1
fi

export ETH_RPC_URL

echo "环境参数："
echo "  ADMIN_ADDR: $ADMIN_ADDR"
echo "  ETH_RPC_URL: $ETH_RPC_URL"
echo "  KYCRegistry: $KYC_REGISTRY_PROXY_ADDR"
echo "  AccessController: $ACCESS_CONTROLLER_PROXY_ADDR"
echo "  LimitController: $LIMIT_CONTROLLER_PROXY_ADDR"
echo "  KYCGuardedToken: $KYC_GUARDED_TOKEN_PROXY_ADDR"

# 1. 验证合约存在
echo ""
echo "📋 步骤 1: 验证合约存在..."
for addr in "$KYC_REGISTRY_PROXY_ADDR" "$ACCESS_CONTROLLER_PROXY_ADDR" "$LIMIT_CONTROLLER_PROXY_ADDR" "$KYC_GUARDED_TOKEN_PROXY_ADDR"; do
    CODE=$(cast code "$addr" --rpc-url "$ETH_RPC_URL" || echo "")
    if [ -z "$CODE" ] || [ "$CODE" = "0x" ]; then
        echo "  ❌ $addr: 无代码"
    else
        echo "  ✅ $addr: 合约存在"
    fi
done

# 2. 验证 AccessController 配置
echo ""
echo "📋 步骤 2: 验证 AccessController 配置..."
KYC_REG_FROM_AC=$(cast call "$ACCESS_CONTROLLER_PROXY_ADDR" "kycRegistry()(address)" --rpc-url "$ETH_RPC_URL" || echo "")
if [ "$KYC_REG_FROM_AC" = "$(cast --to-checksum-address "$KYC_REGISTRY_PROXY_ADDR")" ]; then
    echo "  ✅ AccessController.kycRegistry 配置正确"
else
    echo "  ⚠️  AccessController.kycRegistry 不匹配: $KYC_REG_FROM_AC"
fi

# 3. 验证 LimitController 配置
echo ""
echo "📋 步骤 3: 验证 LimitController 配置..."
KYC_REG_FROM_LC=$(cast call "$LIMIT_CONTROLLER_PROXY_ADDR" "kycRegistry()(address)" --rpc-url "$ETH_RPC_URL" || echo "")
if [ "$KYC_REG_FROM_LC" = "$(cast --to-checksum-address "$KYC_REGISTRY_PROXY_ADDR")" ]; then
    echo "  ✅ LimitController.kycRegistry 配置正确"
else
    echo "  ⚠️  LimitController.kycRegistry 不匹配: $KYC_REG_FROM_LC"
fi

# 4. 验证 KYCGuardedToken 配置
echo ""
echo "📋 步骤 4: 验证 KYCGuardedToken 配置..."
AC_FROM_TOKEN=$(cast call "$KYC_GUARDED_TOKEN_PROXY_ADDR" "accessController()(address)" --rpc-url "$ETH_RPC_URL" || echo "")
if [ "$AC_FROM_TOKEN" = "$(cast --to-checksum-address "$ACCESS_CONTROLLER_PROXY_ADDR")" ]; then
    echo "  ✅ KYCGuardedToken.accessController 配置正确"
else
    echo "  ⚠️  KYCGuardedToken.accessController 不匹配: $AC_FROM_TOKEN"
fi

LC_FROM_TOKEN=$(cast call "$KYC_GUARDED_TOKEN_PROXY_ADDR" "limitController()(address)" --rpc-url "$ETH_RPC_URL" || echo "")
if [ -n "$LC_FROM_TOKEN" ] && [ "$LC_FROM_TOKEN" != "0x0000000000000000000000000000000000000000" ]; then
    echo "  ✅ KYCGuardedToken.limitController 已设置: $LC_FROM_TOKEN"
else
    echo "  ⚠️  KYCGuardedToken.limitController 未设置"
fi

# 5. 测试基本功能
echo ""
echo "📋 步骤 5: 测试基本功能..."

# 创建测试用户地址
TEST_USER=$(cast wallet address --mnemonic-derivation-path "m/44'/60'/0'/0/0" "test test test test test test test test test test test junk" || echo "")
if [ -z "$TEST_USER" ]; then
    TEST_USER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"  # anvil 默认账户 1
fi

echo "  测试用户: $TEST_USER"

# 设置 KYC 状态
echo "  设置测试用户 KYC 状态..."
cast send "$KYC_REGISTRY_PROXY_ADDR" \
    "setKYCStatus(address,uint8,uint8,uint256,bytes32)" \
    "$TEST_USER" \
    "2" \
    "1" \
    "$(cast --to-uint256 $(($(date +%s) + 365 * 86400)))" \
    "$(cast --to-bytes32 "provider-test")" \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "${ADMIN_KEY:-}" \
    --legacy || echo "  ⚠️  设置 KYC 失败（可能需要 ADMIN_KEY）"

# 验证 KYC 状态
IS_APPROVED=$(cast call "$KYC_REGISTRY_PROXY_ADDR" "isKYCApproved(address)(bool)" "$TEST_USER" --rpc-url "$ETH_RPC_URL" || echo "false")
if [ "$IS_APPROVED" = "true" ]; then
    echo "  ✅ 测试用户 KYC 已批准"
else
    echo "  ⚠️  测试用户 KYC 未批准"
fi

# 验证 canMint
CAN_MINT=$(cast call "$ACCESS_CONTROLLER_PROXY_ADDR" "canMint(address)(bool)" "$TEST_USER" --rpc-url "$ETH_RPC_URL" || echo "false")
if [ "$CAN_MINT" = "true" ]; then
    echo "  ✅ AccessController.canMint 返回 true"
else
    echo "  ⚠️  AccessController.canMint 返回 false"
fi

echo ""
echo "=========================================="
echo "✅ 验证完成！"
echo "=========================================="

