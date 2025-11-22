#!/usr/bin/env bash
set -euo pipefail

################################################################################
# complete_limit_controller_setup.sh
#
# 完成 LimitController 的配置和测试（基于已部署的合约）
#
# 前提：
#   - KYCRegistry / AccessController / KYCGuardedToken / LimitController 已部署
#
# 功能：
#   1. 为 KYC level 1 配置限额（单笔 1000 KGT，日累计 10000 KGT）
#   2. 授予 KYCGuardedToken 为 CALLER_ROLE
#   3. 在 KYCGuardedToken 上设置 limitController 地址
#   4. 验证配置
#   5. 端到端测试：设置 KYC、mint、测试限额
#
# 使用方式：
#   chmod +x complete_limit_controller_setup.sh
#   ./complete_limit_controller_setup.sh
################################################################################

echo "=========================================="
echo "🔧 完成 LimitController 配置和测试"
echo "=========================================="

# ============ 已部署的合约地址 ============
KYC_REGISTRY_ADDR=0x529EB62Ae7B9791F34b7429E9c20313CD48927F4
ACCESS_CONTROLLER_ADDR=0x57f47C1F48b1078608f259B17D11f5ac925e5E04
KGT_ADDR=0x9c85cd40541D67670aaC4D8249a55668896A6BD3
LIMIT_CONTROLLER_ADDR=0x5b73C5498c1E3b4dbA84de0F1833c4a029d90519

ADMIN_ADDR=0xE34aaF64b29273B7D567FCFc40544c014EEe9970
ADMIN_KEY=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625
ETH_RPC_URL=http://127.0.0.1:32824

# 限额配置
LEVEL=1
MAX_SINGLE=1000000000000000000000   # 1000 KGT
DAILY_LIMIT=10000000000000000000000  # 10000 KGT
ENABLED=true

echo "合约地址："
echo "  KYCRegistry:        $KYC_REGISTRY_ADDR"
echo "  AccessController:   $ACCESS_CONTROLLER_ADDR"
echo "  KYCGuardedToken:    $KGT_ADDR"
echo "  LimitController:    $LIMIT_CONTROLLER_ADDR"
echo "  Admin:              $ADMIN_ADDR"
echo ""

# ============ 1. 为 level 1 配置限额 ============
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

# ============ 2. 授予 KYCGuardedToken 为 CALLER_ROLE ============
echo ""
echo "🔑 授予 KYCGuardedToken CALLER_ROLE..."

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

# ============ 3. 在 KYCGuardedToken 上设置 limitController ============
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

# ============ 4. 验证配置 ============
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

if [ "$TOKEN_LIMIT_CONTROLLER" != "$LIMIT_CONTROLLER_ADDR" ]; then
  echo "⚠️  警告：limitController 地址不匹配"
  echo "   预期：$LIMIT_CONTROLLER_ADDR"
  echo "   实际：$TOKEN_LIMIT_CONTROLLER"
fi

# ============ 5. 端到端测试 ============
echo ""
echo "🧪 端到端测试..."

# 5.1 设置 ADMIN_ADDR 为 KYC Approved
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

# 5.2 Mint 100000 KGT 给 ADMIN_ADDR
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

# 5.3 测试单笔限额：尝试转 500 KGT（应该成功）
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

# 5.4 测试单笔限额：尝试转 1500 KGT（应该失败）
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

# ============ 6. 汇总输出 ============
echo ""
echo "=========================================="
echo "✅ LimitController 配置和测试完成"
echo "=========================================="
echo "合约地址："
echo "  KYCRegistry:           $KYC_REGISTRY_ADDR"
echo "  AccessController:      $ACCESS_CONTROLLER_ADDR"
echo "  KYCGuardedToken:       $KGT_ADDR"
echo "  LimitController:       $LIMIT_CONTROLLER_ADDR"
echo "  Admin:                 $ADMIN_ADDR"
echo ""
echo "限额配置（KYC level $LEVEL）："
echo "  单笔最大：             $MAX_SINGLE wei (1000 KGT)"
echo "  日累计：               $DAILY_LIMIT wei (10000 KGT)"
echo "  启用状态：             $ENABLED"
echo ""
echo "关键交易哈希："
echo "  setLevelLimits Tx:     $SET_LIMITS_TX"
echo "  grantRole Tx:          $GRANT_ROLE_TX"
echo "  setLimitController Tx: $SET_LIMIT_CONTROLLER_TX"
echo "  setKYCStatus Tx:       $SET_KYC_TX"
echo "  mint Tx:               $MINT_TX"
echo "  transfer 500 KGT Tx:   $TRANSFER_OK_TX"
echo ""
echo "L2 RPC:                  $ETH_RPC_URL"
echo "=========================================="
echo ""
echo "后续建议："
echo "1) 在文档中记录本次合约地址和限额配置，标记为'已实施 & 已验证'；"
echo "2) 继续推进 L1↔L2 桥接 PoC；"
echo "3) 测试日累计限额：多笔转账累计超过 10000 KGT。"
echo ""

