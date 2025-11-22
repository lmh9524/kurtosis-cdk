#!/usr/bin/env bash
set -euo pipefail

################################################################################
# deploy_kyc_stack_with_limits.sh
#
# 一键部署完整的 KYC 栈 + LimitController，专门对应三周计划 Week 2 Day 14
# "L1↔L2 桥接与限额控制" 中的业务层限额部分。
#
# 功能：
#   1. 部署 KYCRegistry
#   2. 部署 AccessController（绑定 KYCRegistry）
#   3. 部署 KYCGuardedToken（绑定 AccessController，包含 limitController 集成）
#   4. 部署 LimitController（绑定 KYCRegistry）
#   5. 为 KYC level 1 配置示例限额（单笔 1000 KGT，日累计 10000 KGT）
#   6. 授予 KYCGuardedToken 为 CALLER_ROLE
#   7. 在 KYCGuardedToken 上设置 limitController 地址
#   8. 验证配置是否生效
#   9. 端到端测试：设置 ADMIN_ADDR 为 KYC Approved，mint 代币，测试限额
#
# 使用方式（在 EC2 上）：
#   cd ~/VeilChain/rwa-kyc/VeilChain
#   chmod +x deploy_kyc_stack_with_limits.sh
#   ./deploy_kyc_stack_with_limits.sh
################################################################################

echo "=========================================="
echo "🚀 部署完整 KYC 栈 + LimitController"
echo "=========================================="

# ============ 环境变量配置 ============
: "${ADMIN_KEY:=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
: "${ADMIN_ADDR:=0xE34aaF64b29273B7D567FCFc40544c014EEe9970}"
: "${ETH_RPC_URL:=http://127.0.0.1:32824}"

export ADMIN_KEY
export ADMIN_ADDR
export ETH_RPC_URL
export PRIVATE_KEY="$ADMIN_KEY"

# 限额配置（示例：level 1 用户）
LEVEL=1
MAX_SINGLE=1000000000000000000000   # 1000 KGT (1000 * 1e18)
DAILY_LIMIT=10000000000000000000000  # 10000 KGT (10000 * 1e18)
ENABLED=true

echo "环境参数："
echo "  ADMIN_ADDR:        $ADMIN_ADDR"
echo "  ETH_RPC_URL:       $ETH_RPC_URL"
echo ""

# ============ 定位项目根目录 ============
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo "项目根目录: $PROJECT_ROOT"
cd "$PROJECT_ROOT"

if [ ! -f "foundry.toml" ]; then
  echo "❌ 未找到 foundry.toml，请确认在 rwa-kyc/VeilChain 目录下运行。"
  exit 1
fi

echo ""
echo "✅ Foundry 版本信息："
forge --version
cast --version

# ============ 1. 编译合约 ============
echo ""
echo "📦 编译 VeilChain 合约..."
forge build

# ============ 2. 部署 KYCRegistry ============
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

echo "✅ KYCRegistry 地址: $KYC_REGISTRY_ADDR"

# ============ 3. 部署 AccessController ============
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

echo "✅ AccessController 地址: $ACCESS_CONTROLLER_ADDR"

# ============ 4. 部署 KYCGuardedToken ============
echo ""
echo "🚀 部署 KYCGuardedToken（包含 limitController 集成）..."
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

export KGT_ADDR

echo "✅ KYCGuardedToken 地址: $KGT_ADDR"

# ============ 5. 部署 LimitController ============
echo ""
echo "🚀 部署 LimitController..."

DEPLOY_OUTPUT=$(forge script script/DeployLimitController.s.sol:DeployLimitController \
  --rpc-url "$ETH_RPC_URL" \
  --broadcast \
  --legacy 2>&1)

echo "$DEPLOY_OUTPUT"

LIMIT_CONTROLLER_ADDR=$(echo "$DEPLOY_OUTPUT" | grep -oP 'LimitController deployed at:\s*\K0x[a-fA-F0-9]{40}' | head -1 || true)

if [ -z "$LIMIT_CONTROLLER_ADDR" ]; then
  echo "❌ 无法从部署日志中提取 LimitController 地址，请检查部署输出。"
  exit 1
fi

echo "✅ LimitController 地址: $LIMIT_CONTROLLER_ADDR"

# ============ 6. 为 level 1 配置限额 ============
echo ""
echo "⚙️  为 KYC level $LEVEL 配置限额..."
echo "   单笔最大：$MAX_SINGLE wei (1000 KGT)"
echo "   日累计：  $DAILY_LIMIT wei (10000 KGT)"

SET_LIMITS_OUTPUT=$(cast send "$LIMIT_CONTROLLER_ADDR" \
  "setLevelLimits(uint8,uint256,uint256,bool)" \
  "$LEVEL" "$MAX_SINGLE" "$DAILY_LIMIT" "$ENABLED" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" \
  --legacy 2>&1)

echo "$SET_LIMITS_OUTPUT"

SET_LIMITS_TX=$(echo "$SET_LIMITS_OUTPUT" | grep "transactionHash" | awk '{print $2}' | head -1)
echo "✅ setLevelLimits Tx: $SET_LIMITS_TX"

# ============ 7. 授予 KYCGuardedToken 为 CALLER_ROLE ============
echo ""
echo "🔑 授予 KYCGuardedToken ($KGT_ADDR) CALLER_ROLE..."

CALLER_ROLE=$(cast keccak "CALLER_ROLE")

GRANT_ROLE_OUTPUT=$(cast send "$LIMIT_CONTROLLER_ADDR" \
  "grantRole(bytes32,address)" \
  "$CALLER_ROLE" "$KGT_ADDR" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" \
  --legacy 2>&1)

echo "$GRANT_ROLE_OUTPUT"

GRANT_ROLE_TX=$(echo "$GRANT_ROLE_OUTPUT" | grep "transactionHash" | awk '{print $2}' | head -1)
echo "✅ grantRole Tx: $GRANT_ROLE_TX"

# ============ 8. 在 KYCGuardedToken 上设置 limitController ============
echo ""
echo "🔗 在 KYCGuardedToken 上设置 limitController..."

SET_LIMIT_CONTROLLER_OUTPUT=$(cast send "$KGT_ADDR" \
  "setLimitController(address)" \
  "$LIMIT_CONTROLLER_ADDR" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" \
  --legacy 2>&1)

echo "$SET_LIMIT_CONTROLLER_OUTPUT"

SET_LIMIT_CONTROLLER_TX=$(echo "$SET_LIMIT_CONTROLLER_OUTPUT" | grep "transactionHash" | awk '{print $2}' | head -1)
echo "✅ setLimitController Tx: $SET_LIMIT_CONTROLLER_TX"

# ============ 9. 验证配置 ============
echo ""
echo "🔍 验证配置..."

# 读取 levelLimits(1)
LEVEL_LIMITS=$(cast call "$LIMIT_CONTROLLER_ADDR" \
  "levelLimits(uint8)(uint256,uint256,bool)" \
  "$LEVEL" \
  --rpc-url "$ETH_RPC_URL")

echo "levelLimits($LEVEL) = $LEVEL_LIMITS"

# 读取 token.limitController()
TOKEN_LIMIT_CONTROLLER=$(cast call "$KGT_ADDR" \
  "limitController()(address)" \
  --rpc-url "$ETH_RPC_URL")

echo "KYCGuardedToken.limitController() = $TOKEN_LIMIT_CONTROLLER"

# ============ 10. 端到端测试：设置 KYC + mint + 测试限额 ============
echo ""
echo "🧪 端到端测试..."

# 10.1 设置 ADMIN_ADDR 为 KYC Approved
echo ""
echo "1️⃣  设置 ADMIN_ADDR 为 KYC Approved (level 1)..."

KYC_PROVIDER_ID=$(cast --format-bytes32-string "kyc_provider")

SET_KYC_OUTPUT=$(cast send "$KYC_REGISTRY_ADDR" \
  "setKYCStatus(address,uint8,uint8,uint256,bytes32)" \
  "$ADMIN_ADDR" \
  2 \
  1 \
  0 \
  "$KYC_PROVIDER_ID" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" \
  --legacy 2>&1)

echo "$SET_KYC_OUTPUT"

SET_KYC_TX=$(echo "$SET_KYC_OUTPUT" | grep "transactionHash" | awk '{print $2}' | head -1)
echo "✅ setKYCStatus Tx: $SET_KYC_TX"

# 10.2 Mint 100000 KGT 给 ADMIN_ADDR
echo ""
echo "2️⃣  Mint 100000 KGT 给 ADMIN_ADDR..."

MINT_AMOUNT=100000000000000000000000  # 100000 * 1e18

MINT_OUTPUT=$(cast send "$KGT_ADDR" \
  "mint(address,uint256)" \
  "$ADMIN_ADDR" \
  "$MINT_AMOUNT" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" \
  --legacy 2>&1)

echo "$MINT_OUTPUT"

MINT_TX=$(echo "$MINT_OUTPUT" | grep "transactionHash" | awk '{print $2}' | head -1)
echo "✅ mint Tx: $MINT_TX"

# 验证余额
BALANCE=$(cast call "$KGT_ADDR" \
  "balanceOf(address)(uint256)" \
  "$ADMIN_ADDR" \
  --rpc-url "$ETH_RPC_URL")

echo "ADMIN_ADDR balance: $BALANCE"

# 10.3 测试单笔限额：尝试转 500 KGT（应该成功）
echo ""
echo "3️⃣  测试单笔限额：转 500 KGT（应该成功）..."

TRANSFER_AMOUNT_OK=500000000000000000000  # 500 * 1e18

TRANSFER_OK_OUTPUT=$(cast send "$KGT_ADDR" \
  "transfer(address,uint256)" \
  "$ADMIN_ADDR" \
  "$TRANSFER_AMOUNT_OK" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" \
  --legacy 2>&1)

echo "$TRANSFER_OK_OUTPUT"

TRANSFER_OK_TX=$(echo "$TRANSFER_OK_OUTPUT" | grep "transactionHash" | awk '{print $2}' | head -1)
echo "✅ transfer 500 KGT Tx: $TRANSFER_OK_TX"

# 10.4 测试单笔限额：尝试转 1500 KGT（应该失败）
echo ""
echo "4️⃣  测试单笔限额：转 1500 KGT（应该失败，超过单笔 1000 限额）..."

TRANSFER_AMOUNT_FAIL=1500000000000000000000  # 1500 * 1e18

TRANSFER_FAIL_OUTPUT=$(cast send "$KGT_ADDR" \
  "transfer(address,uint256)" \
  "$ADMIN_ADDR" \
  "$TRANSFER_AMOUNT_FAIL" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" \
  --legacy 2>&1 || echo "Expected failure: single tx limit exceeded")

echo "$TRANSFER_FAIL_OUTPUT"

if echo "$TRANSFER_FAIL_OUTPUT" | grep -q "execution reverted"; then
  echo "✅ 单笔限额测试通过：1500 KGT 转账被正确拦截"
else
  echo "⚠️  警告：1500 KGT 转账没有被拦截，请检查限额配置"
fi

# ============ 11. 汇总输出 ============
echo ""
echo "=========================================="
echo "✅ 完整 KYC 栈 + LimitController 部署完成"
echo "=========================================="
echo "Admin 地址:                 $ADMIN_ADDR"
echo "KYCRegistry 地址:           $KYC_REGISTRY_ADDR"
echo "AccessController 地址:      $ACCESS_CONTROLLER_ADDR"
echo "KYCGuardedToken 地址:       $KGT_ADDR"
echo "LimitController 地址:       $LIMIT_CONTROLLER_ADDR"
echo ""
echo "限额配置（KYC level $LEVEL）："
echo "  单笔最大：                $MAX_SINGLE wei (1000 KGT)"
echo "  日累计：                  $DAILY_LIMIT wei (10000 KGT)"
echo "  启用状态：                $ENABLED"
echo ""
echo "关键交易哈希："
echo "  setLevelLimits Tx:        $SET_LIMITS_TX"
echo "  grantRole Tx:             $GRANT_ROLE_TX"
echo "  setLimitController Tx:    $SET_LIMIT_CONTROLLER_TX"
echo "  setKYCStatus Tx:          $SET_KYC_TX"
echo "  mint Tx:                  $MINT_TX"
echo "  transfer 500 KGT Tx:      $TRANSFER_OK_TX"
echo ""
echo "L2 RPC:                     $ETH_RPC_URL"
echo "=========================================="
echo ""
echo "后续建议："
echo "1) 在文档中（如三周实施计划 Week 2 Day 14）记录本次合约地址和限额配置，标记为'已实施 & 已验证'；"
echo "2) 继续推进 L1↔L2 桥接 PoC，验证跨链资金流；"
echo "3) 测试日累计限额：多笔转账累计超过 10000 KGT，验证会被 'LimitController: daily limit exceeded' 拦截。"
echo ""

