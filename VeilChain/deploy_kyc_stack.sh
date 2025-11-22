#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "部署 KYC + AccessController + KYCGuardedToken 到 L2（Polygon CDK devnet）"
echo "=========================================="

# 1. 基本参数（如有需要，可在运行前导出同名环境变量覆盖）
: "${ADMIN_KEY:=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
: "${ADMIN_ADDR:=0xE34aaF64b29273B7D567FCFc40544c014EEe9970}"
: "${ETH_RPC_URL:=http://127.0.0.1:32824}"   # 当前 Kurtosis proxyd-001 L2 RPC
: "${L1_RPC_URL:=http://127.0.0.1:32773}"

export ADMIN_KEY
export ADMIN_ADDR
export ETH_RPC_URL
export L1_RPC_URL
export PRIVATE_KEY="$ADMIN_KEY"

# 2. 定位 Foundry 项目根目录（VeilChain）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo "项目根目录: $PROJECT_ROOT"
cd "$PROJECT_ROOT"

# 3. 确保本地有 VeilChain 的 foundry.toml（我们刚刚在仓库里已经写好）
if [ ! -f "foundry.toml" ]; then
  echo "❌ 未找到 foundry.toml，请确认在 rwa-kyc/VeilChain 目录下运行。"
  exit 1
fi

echo ""
echo "✅ Foundry 版本信息："
forge --version
cast --version

# 4. 编译合约
echo ""
echo "🔨 编译 VeilChain 合约..."
forge build

# 5. 部署 KYCRegistry
echo ""
echo "🚀 部署 KYCRegistry..."
KYC_OUTPUT=$(forge script script/DeployKYC.s.sol:DeployKYCRegistry \
  --rpc-url "$ETH_RPC_URL" \
  --broadcast \
  --legacy 2>&1)

echo "$KYC_OUTPUT"

KYC_REGISTRY_ADDR=$(echo "$KYC_OUTPUT" | grep -oP 'KYCRegistry deployed at:\s*\K0x[a-fA-F0-9]{40}' | head -1 || true)

if [ -z "$KYC_REGISTRY_ADDR" ]; then
  echo "❌ 未能从输出中解析 KYCRegistry 地址，请在上面日志中手动查找 'KYCRegistry deployed at:'。"
  exit 1
fi

export KYC_REGISTRY_ADDR

echo "KYCRegistry 地址: $KYC_REGISTRY_ADDR"

echo "" 
echo "🚀 部署 AccessController..."
AC_OUTPUT=$(forge script script/DeployAccessController.s.sol:DeployAccessController \
  --rpc-url "$ETH_RPC_URL" \
  --broadcast \
  --legacy 2>&1)

echo "$AC_OUTPUT"

ACCESS_CONTROLLER_ADDR=$(echo "$AC_OUTPUT" | grep -oP 'AccessController deployed at:\s*\K0x[a-fA-F0-9]{40}' | head -1 || true)

if [ -z "$ACCESS_CONTROLLER_ADDR" ]; then
  echo "❌ 未能从输出中解析 AccessController 地址，请在上面日志中手动查找 'AccessController deployed at:'。"
  exit 1
fi

export ACCESS_CONTROLLER_ADDR

echo "AccessController 地址: $ACCESS_CONTROLLER_ADDR"

# 7. 部署 KYCGuardedToken
echo "" 
echo "🚀 部署 KYCGuardedToken..."
TOKEN_OUTPUT=$(forge script script/DeployKYCGuardedToken.s.sol:DeployKYCGuardedToken \
  --rpc-url "$ETH_RPC_URL" \
  --broadcast \
  --legacy 2>&1)

echo "$TOKEN_OUTPUT"

KGT_ADDR=$(echo "$TOKEN_OUTPUT" | grep -oP 'KYCGuardedToken deployed at:\s*\K0x[a-fA-F0-9]{40}' | head -1 || true)

if [ -z "$KGT_ADDR" ]; then
  echo "❌ 未能从输出中解析 KYCGuardedToken 地址，请在上面日志中手动查找 'KYCGuardedToken deployed at:'。"
  exit 1
fi

echo "KYCGuardedToken 地址: $KGT_ADDR"

# 8. 简单验证：设置一个地址为 Approved 并尝试铸币 / 转账，可以后续补充

echo ""
echo "=========================================="
echo "✅ 部署完成总结"
echo "=========================================="
echo "Admin 地址:           $ADMIN_ADDR"
echo "KYCRegistry 地址:     $KYC_REGISTRY_ADDR"
echo "AccessController 地址: $ACCESS_CONTROLLER_ADDR"
echo "KYCGuardedToken 地址:  $KGT_ADDR"
echo "L2 RPC:               $ETH_RPC_URL"
echo "=========================================="
echo "下一步建议："
echo "1) 使用 cast 与 KYCRegistry 交互，设置某个地址为 Approved；"
echo "2) 使用 KYCGuardedToken 进行一次成功转账和一次被拦截的转账，用于文档中的“已实施 & 已验证”用例。"

