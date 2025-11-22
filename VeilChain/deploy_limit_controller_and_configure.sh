#!/usr/bin/env bash
set -e

################################################################################
# deploy_limit_controller_and_configure.sh
#
# 一键部署 LimitController 并配置限额策略，专门对应三周计划 Week 2 Day 14
# "L1↔L2 桥接与限额控制" 中的业务层限额部分。
#
# 前提：
#   - 当前 L2 上已部署 KYCRegistry / AccessController / KYCGuardedToken
#   - 环境变量或脚本内已配置 ADMIN_KEY / ADMIN_ADDR / ETH_RPC_URL
#
# 功能：
#   1. 部署 LimitController（绑定现有 KYCRegistry）
#   2. 为 KYC level 1 配置示例限额（单笔 1000 KGT，日累计 10000 KGT）
#   3. 授予 KYCGuardedToken 为 CALLER_ROLE
#   4. 在 KYCGuardedToken 上设置 limitController 地址
#   5. 验证配置是否生效（读取 levelLimits 和 token.limitController）
#
# 使用方式（在 EC2 上）：
#   cd ~/VeilChain/rwa-kyc/VeilChain
#   chmod +x deploy_limit_controller_and_configure.sh
#   ./deploy_limit_controller_and_configure.sh
################################################################################

echo "=========================================="
echo "🚀 部署 LimitController 并配置限额策略..."
echo "=========================================="

# ============ 环境变量配置 ============
# 管理员私钥和地址（与之前 KYC 栈一致）
ADMIN_KEY="${ADMIN_KEY:-0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
ADMIN_ADDR="${ADMIN_ADDR:-0xE34aaF64b29273B7D567FCFc40544c014EEe9970}"

# L2 RPC（默认 Kurtosis proxyd-001）
ETH_RPC_URL="${ETH_RPC_URL:-http://127.0.0.1:32824}"

# 现有合约地址（从 关键信息记录.md 第 9 节）
KYC_REGISTRY_ADDR="${KYC_REGISTRY_ADDR:-0x2F50ef6b8e8Ee4E579B17619A92dE3E2ffbD8AD2}"
KGT_ADDR="${KGT_ADDR:-0x35b75f623311c87863Dd34a1fFE9A62a69fd4F87}"

# 限额配置（示例：level 1 用户）
LEVEL=1
MAX_SINGLE=1000000000000000000000   # 1000 KGT (1000 * 1e18)
DAILY_LIMIT=10000000000000000000000  # 10000 KGT (10000 * 1e18)
ENABLED=true

echo "环境参数："
echo "  ADMIN_ADDR:        $ADMIN_ADDR"
echo "  ETH_RPC_URL:       $ETH_RPC_URL"
echo "  KYC_REGISTRY_ADDR: $KYC_REGISTRY_ADDR"
echo "  KGT_ADDR:          $KGT_ADDR"
echo ""

# ============ 1. 编译合约 ============
echo "📦 编译 VeilChain 合约..."
forge build --silent

# ============ 2. 部署 LimitController ============
echo ""
echo "🚀 部署 LimitController..."

export ADMIN_ADDR
export KYC_REGISTRY_ADDR

DEPLOY_OUTPUT=$(forge script script/DeployLimitController.s.sol:DeployLimitController \
  --rpc-url "$ETH_RPC_URL" \
  --private-key "$ADMIN_KEY" \
  --broadcast 2>&1)

echo "$DEPLOY_OUTPUT"

# 从日志中提取 LimitController 地址
LIMIT_CONTROLLER_ADDR=$(echo "$DEPLOY_OUTPUT" | grep "LimitController deployed at:" | awk '{print $NF}')

if [ -z "$LIMIT_CONTROLLER_ADDR" ]; then
  echo "❌ 无法从部署日志中提取 LimitController 地址，请检查部署输出。"
  exit 1
fi

echo ""
echo "✅ LimitController 部署成功：$LIMIT_CONTROLLER_ADDR"

# ============ 3. 为 level 1 配置限额 ============
echo ""
echo "⚙️  为 KYC level $LEVEL 配置限额..."
echo "   单笔最大：$MAX_SINGLE wei (1000 KGT)"
echo "   日累计：  $DAILY_LIMIT wei (10000 KGT)"

SET_LIMITS_OUTPUT=$(cast send "$LIMIT_CONTROLLER_ADDR" \
  "setLevelLimits(uint8,uint256,uint256,bool)" \
  "$LEVEL" "$MAX_SINGLE" "$DAILY_LIMIT" "$ENABLED" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" 2>&1)

echo "$SET_LIMITS_OUTPUT"

SET_LIMITS_TX=$(echo "$SET_LIMITS_OUTPUT" | grep "transactionHash" | awk '{print $2}')
echo "✅ setLevelLimits Tx: $SET_LIMITS_TX"

# ============ 4. 授予 KYCGuardedToken 为 CALLER_ROLE ============
echo ""
echo "🔑 授予 KYCGuardedToken ($KGT_ADDR) CALLER_ROLE..."

# CALLER_ROLE = keccak256("CALLER_ROLE")
CALLER_ROLE=$(cast keccak "CALLER_ROLE")

GRANT_ROLE_OUTPUT=$(cast send "$LIMIT_CONTROLLER_ADDR" \
  "grantRole(bytes32,address)" \
  "$CALLER_ROLE" "$KGT_ADDR" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" 2>&1)

echo "$GRANT_ROLE_OUTPUT"

GRANT_ROLE_TX=$(echo "$GRANT_ROLE_OUTPUT" | grep "transactionHash" | awk '{print $2}')
echo "✅ grantRole Tx: $GRANT_ROLE_TX"

# ============ 5. 在 KYCGuardedToken 上设置 limitController ============
echo ""
echo "🔗 在 KYCGuardedToken 上设置 limitController..."

SET_LIMIT_CONTROLLER_OUTPUT=$(cast send "$KGT_ADDR" \
  "setLimitController(address)" \
  "$LIMIT_CONTROLLER_ADDR" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" 2>&1)

echo "$SET_LIMIT_CONTROLLER_OUTPUT"

SET_LIMIT_CONTROLLER_TX=$(echo "$SET_LIMIT_CONTROLLER_OUTPUT" | grep "transactionHash" | awk '{print $2}')
echo "✅ setLimitController Tx: $SET_LIMIT_CONTROLLER_TX"

# ============ 6. 验证配置 ============
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

# ============ 7. 汇总输出 ============
echo ""
echo "=========================================="
echo "✅ LimitController 部署与配置完成"
echo "=========================================="
echo "LimitController 地址:       $LIMIT_CONTROLLER_ADDR"
echo "KYCRegistry 地址:           $KYC_REGISTRY_ADDR"
echo "KYCGuardedToken 地址:       $KGT_ADDR"
echo "Admin 地址:                 $ADMIN_ADDR"
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
echo ""
echo "L2 RPC:                     $ETH_RPC_URL"
echo "=========================================="
echo ""
echo "后续建议："
echo "1) 使用 cast 模拟一笔超过单笔限额（>1000 KGT）的转账，验证会被 'LimitController: single tx limit exceeded' 拦截；"
echo "2) 模拟多笔累计超过日限额（>10000 KGT）的转账，验证会被 'LimitController: daily limit exceeded' 拦截；"
echo "3) 在文档中（如三周实施计划 Week 2 Day 14）记录本次合约地址和限额配置，标记为'已实施 & 已验证'。"
echo ""

