#!/usr/bin/env bash
set -euo pipefail

################################################################################
# run_e2e_verification.sh
#
# 在 EC2 AWS Kurtosis 环境上运行端到端验证测试
# 验证 AccessController/LimitController 更新后的集成
#
# 使用方式：
#   chmod +x script/run_e2e_verification.sh
#   ./script/run_e2e_verification.sh
################################################################################

echo "=========================================="
echo "🚀 EC2 端到端测试验证"
echo "=========================================="

# ============ 1. 环境检查 ============
echo ""
echo "📋 步骤 1: 环境检查"

# 检查 Kurtosis enclave
if ! kurtosis enclave ls | grep -q "cdk.*RUNNING"; then
    echo "❌ Kurtosis enclave 'cdk' 未运行"
    echo "   请先运行: kurtosis run --enclave cdk github.com/0xPolygon/kurtosis-cdk"
    exit 1
fi
echo "✅ Kurtosis enclave 运行中"

# 获取 L2 RPC URL
export L2_RPC_URL="$(kurtosis port print cdk cdk-erigon-node-001 rpc 2>/dev/null || echo "")"
if [ -z "$L2_RPC_URL" ]; then
    echo "❌ 无法获取 L2 RPC URL"
    exit 1
fi
echo "✅ L2 RPC: $L2_RPC_URL"

# 验证链可访问
if ! cast block-number --rpc-url "$L2_RPC_URL" > /dev/null 2>&1; then
    echo "❌ 无法连接到 L2 链"
    exit 1
fi
BLOCK_NUMBER=$(cast block-number --rpc-url "$L2_RPC_URL")
echo "✅ 链可访问，当前区块: $BLOCK_NUMBER"

# ============ 2. 准备账户 ============
echo ""
echo "📋 步骤 2: 准备测试账户"

export DEV_MNEMONIC="giant issue aisle success illegal bike spike question tent bar rely arctic volcano long crawl hungry vocal artwork sniff fantasy very lucky have athlete"
export ADMIN_PK="$(cast wallet private-key --mnemonic "$DEV_MNEMONIC" | tr -d '\n')"
export ADMIN_ADDR="$(cast wallet address --private-key "$ADMIN_PK")"
export USER_A="$(cast wallet address --mnemonic "$DEV_MNEMONIC" --derivation-path "m/44'/60'/0'/0/1")"
export USER_B="$(cast wallet address --mnemonic "$DEV_MNEMONIC" --derivation-path "m/44'/60'/0'/0/2")"
export USER_A_PK="$(cast wallet private-key --mnemonic "$DEV_MNEMONIC" --derivation-path "m/44'/60'/0'/0/1" | tr -d '\n')"

echo "✅ 管理员地址: $ADMIN_ADDR"
echo "✅ 测试用户 A: $USER_A"
echo "✅ 测试用户 B: $USER_B"

# 检查余额
ADMIN_BALANCE=$(cast balance "$ADMIN_ADDR" --rpc-url "$L2_RPC_URL")
echo "   管理员余额: $(cast --to-unit "$ADMIN_BALANCE" ether) ETH"

if [ "$(cast --to-unit "$ADMIN_BALANCE" ether | cut -d. -f1)" -lt 1 ]; then
    echo "⚠️  警告: 管理员余额较低，可能影响测试"
fi

# ============ 3. 编译合约 ============
echo ""
echo "📋 步骤 3: 编译合约"

cd ~/VeilChain || { echo "❌ 未找到 ~/VeilChain 目录"; exit 1; }

if ! forge build > /dev/null 2>&1; then
    echo "❌ 编译失败"
    forge build
    exit 1
fi
echo "✅ 编译成功"

# ============ 4. 运行单元测试 ============
echo ""
echo "📋 步骤 4: 运行单元测试"

echo "   运行 AccessController 测试..."
if ! forge test --match-contract AccessControllerTest -vv > /tmp/access_controller_test.log 2>&1; then
    echo "❌ AccessController 测试失败"
    cat /tmp/access_controller_test.log
    exit 1
fi

echo "   运行 LimitController 测试..."
if ! forge test --match-contract LimitControllerTest -vv > /tmp/limit_controller_test.log 2>&1; then
    echo "❌ LimitController 测试失败"
    cat /tmp/limit_controller_test.log
    exit 1
fi

echo "   运行 KYCGuardedToken 测试..."
if ! forge test --match-contract KYCGuardedTokenTest -vv > /tmp/kgt_test.log 2>&1; then
    echo "❌ KYCGuardedToken 测试失败"
    cat /tmp/kgt_test.log
    exit 1
fi

echo "   运行 KYCGuardedTokenLimitTest 测试..."
if ! forge test --match-contract KYCGuardedTokenLimitTest -vv > /tmp/kgt_limit_test.log 2>&1; then
    echo "❌ KYCGuardedTokenLimitTest 测试失败"
    cat /tmp/kgt_limit_test.log
    exit 1
fi

echo "✅ 所有单元测试通过"

# ============ 5. 检查已部署的合约 ============
echo ""
echo "📋 步骤 5: 检查已部署的合约"

# 尝试从环境变量或配置文件读取合约地址
if [ -f ~/VeilChain/.env ]; then
    source ~/VeilChain/.env
fi

# 如果未设置，提示用户输入
if [ -z "${KYC_REGISTRY_ADDR:-}" ]; then
    echo "⚠️  未找到已部署的合约地址"
    echo "   请提供合约地址，或运行部署脚本："
    echo "   ./deploy_kyc_stack_with_limits.sh"
    read -p "   是否继续验证已部署的合约？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    read -p "   KYCRegistry 地址: " KYC_REGISTRY_ADDR
    read -p "   AccessController 地址: " ACCESS_CONTROLLER_ADDR
    read -p "   LimitController 地址: " LIMIT_CONTROLLER_ADDR
    read -p "   KYCGuardedToken 地址: " KGT_ADDR
fi

export KYC_REGISTRY_ADDR
export ACCESS_CONTROLLER_ADDR
export LIMIT_CONTROLLER_ADDR
export KGT_ADDR

echo "   合约地址："
echo "     KYCRegistry:        $KYC_REGISTRY_ADDR"
echo "     AccessController:   $ACCESS_CONTROLLER_ADDR"
echo "     LimitController:    $LIMIT_CONTROLLER_ADDR"
echo "     KYCGuardedToken:    $KGT_ADDR"

# 验证合约是否存在
for addr in "$KYC_REGISTRY_ADDR" "$ACCESS_CONTROLLER_ADDR" "$LIMIT_CONTROLLER_ADDR" "$KGT_ADDR"; do
    CODE=$(cast code "$addr" --rpc-url "$L2_RPC_URL" 2>/dev/null || echo "")
    if [ -z "$CODE" ] || [ "$CODE" = "0x" ]; then
        echo "❌ 合约地址 $addr 上没有字节码（可能是 EOA 或无效地址）"
        exit 1
    fi
done
echo "✅ 所有合约地址有效"

# ============ 6. 验证 AccessController ============
echo ""
echo "📋 步骤 6: 验证 AccessController 集成"

# 设置 KYC 状态
echo "   设置测试用户 KYC 状态..."
KYC_PROVIDER_ID=$(cast --format-bytes32-string "kyc_provider")

cast send "$KYC_REGISTRY_ADDR" \
  "setKYCStatus(address,uint8,uint8,uint256,bytes32)" \
  "$USER_A" \
  2 \
  1 \
  $(($(date +%s) + 86400)) \
  "$KYC_PROVIDER_ID" \
  --rpc-url "$L2_RPC_URL" \
  --private-key "$ADMIN_PK" > /dev/null 2>&1

cast send "$KYC_REGISTRY_ADDR" \
  "setKYCStatus(address,uint8,uint8,uint256,bytes32)" \
  "$USER_B" \
  2 \
  1 \
  $(($(date +%s) + 86400)) \
  "$KYC_PROVIDER_ID" \
  --rpc-url "$L2_RPC_URL" \
  --private-key "$ADMIN_PK" > /dev/null 2>&1

# 验证 canTransfer
CAN_TRANSFER=$(cast call "$ACCESS_CONTROLLER_ADDR" \
  "canTransfer(address,address)" \
  "$USER_A" \
  "$USER_B" \
  --rpc-url "$L2_RPC_URL")

if [ "$CAN_TRANSFER" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "✅ canTransfer 检查通过"
else
    echo "❌ canTransfer 检查失败: $CAN_TRANSFER"
    exit 1
fi

# 验证 canMint
CAN_MINT=$(cast call "$ACCESS_CONTROLLER_ADDR" \
  "canMint(address)" \
  "$USER_A" \
  --rpc-url "$L2_RPC_URL")

if [ "$CAN_MINT" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "✅ canMint 检查通过"
else
    echo "❌ canMint 检查失败: $CAN_MINT"
    exit 1
fi

# ============ 7. 验证 LimitController ============
echo ""
echo "📋 步骤 7: 验证 LimitController 集成"

# 查询限额配置
LEVEL_LIMITS=$(cast call "$LIMIT_CONTROLLER_ADDR" \
  "levelLimits(uint8)" \
  1 \
  --rpc-url "$L2_RPC_URL")

if [ -n "$LEVEL_LIMITS" ] && [ "$LEVEL_LIMITS" != "0x" ]; then
    echo "✅ LimitController 限额配置存在"
    echo "   配置: $LEVEL_LIMITS"
else
    echo "⚠️  LimitController 限额配置未设置或为空"
fi

# 验证 CALLER_ROLE
HAS_CALLER_ROLE=$(cast call "$LIMIT_CONTROLLER_ADDR" \
  "hasRole(bytes32,address)" \
  "$(cast call "$LIMIT_CONTROLLER_ADDR" "CALLER_ROLE()(bytes32)" --rpc-url "$L2_RPC_URL")" \
  "$KGT_ADDR" \
  --rpc-url "$L2_RPC_URL")

if [ "$HAS_CALLER_ROLE" = "0x0000000000000000000000000000000000000000000000000000000000000001" ]; then
    echo "✅ KYCGuardedToken 具有 CALLER_ROLE"
else
    echo "⚠️  KYCGuardedToken 未授予 CALLER_ROLE"
fi

# 验证 KGT 是否设置了 LimitController
KGT_LIMIT_CTRL=$(cast call "$KGT_ADDR" \
  "limitController()" \
  --rpc-url "$L2_RPC_URL")

if [ "$(cast --to-checksum-address "$KGT_LIMIT_CTRL")" = "$(cast --to-checksum-address "$LIMIT_CONTROLLER_ADDR")" ]; then
    echo "✅ KYCGuardedToken 已设置 LimitController"
else
    echo "⚠️  KYCGuardedToken 未设置 LimitController 或地址不匹配"
    echo "   当前: $KGT_LIMIT_CTRL"
    echo "   期望: $LIMIT_CONTROLLER_ADDR"
fi

# ============ 8. 端到端功能测试 ============
echo ""
echo "📋 步骤 8: 端到端功能测试"

# 确保 USER_A 有足够 gas
USER_A_ETH_BALANCE=$(cast balance "$USER_A" --rpc-url "$L2_RPC_URL")
if [ "$(cast --to-unit "$USER_A_ETH_BALANCE" ether | cut -d. -f1)" -lt 1 ]; then
    echo "   USER_A ETH 余额不足，尝试从 ADMIN_ADDR 转 1 ETH..."
    cast send "$USER_A" \
      --value 1000000000000000000 \
      --rpc-url "$L2_RPC_URL" \
      --private-key "$ADMIN_PK" > /dev/null 2>&1 || echo "⚠️  无法自动为 USER_A 补充 gas，请手动转入 ETH。"
fi

# Mint 代币（从 ADMIN_ADDR 铸给 USER_A）
echo "   Mint 代币给 USER_A..."
cast send "$KGT_ADDR" \
  "mint(address,uint256)" \
  "$USER_A" \
  10000000000000000000000 \
  --rpc-url "$L2_RPC_URL" \
  --private-key "$ADMIN_PK" > /dev/null 2>&1

BALANCE_A=$(cast call "$KGT_ADDR" \
  "balanceOf(address)" \
  "$USER_A" \
  --rpc-url "$L2_RPC_URL")

if [ "$(cast --to-unit "$BALANCE_A" ether | cut -d. -f1)" -ge 10000 ]; then
    echo "✅ Mint 成功，USER_A 余额: $(cast --to-unit "$BALANCE_A" ether) KGT"
else
    echo "❌ Mint 失败或余额不正确"
    exit 1
fi

# 测试转账（小额度，应该成功；from = USER_A）
echo "   测试小额转账（应成功，from = USER_A → USER_B）..."
TX_OK_OUTPUT=$(cast send "$KGT_ADDR" \
  "transfer(address,uint256)" \
  "$USER_B" \
  500000000000000000000 \
  --rpc-url "$L2_RPC_URL" \
  --private-key "$USER_A_PK" 2>&1 || echo "")

TX_OK_HASH=$(echo "$TX_OK_OUTPUT" | grep -o "0x[a-fA-F0-9]\{64\}" | head -1 || echo "")

if [ -n "$TX_OK_HASH" ]; then
    echo "✅ 小额转账成功，交易哈希: $TX_OK_HASH"
else
    echo "❌ 小额转账失败，输出如下："
    echo "$TX_OK_OUTPUT"
    exit 1
fi

# 测试超出单笔限额（应由 LimitController 拦截）
echo "   测试单笔限额（尝试转 1500 KGT，应被 LimitController 拦截）..."
TX_FAIL_OUTPUT=$(cast send "$KGT_ADDR" \
  "transfer(address,uint256)" \
  "$USER_B" \
  1500000000000000000000 \
  --rpc-url "$L2_RPC_URL" \
  --private-key "$USER_A_PK" 2>&1 || echo "")

if echo "$TX_FAIL_OUTPUT" | grep -q "LimitController: single tx limit exceeded"; then
    echo "✅ 单笔限额测试通过：1500 KGT 被 LimitController 正确拦截"
else
    echo "❌ 单笔限额测试未触发预期的 'LimitController: single tx limit exceeded'，请检查："
    echo "   - level 1 的 levelLimits 是否已设置（maxSingle / daily / enabled）"
    echo "   - KYCRegistry 中 USER_A 的 level 是否为 1 且已通过 KYC"
    echo "   - LimitController 是否已授予 KGT CALLER_ROLE，且 KGT.limitController 指向正确地址"
    echo ""
    echo "实际输出："
    echo "$TX_FAIL_OUTPUT"
    exit 1
fi

# ============ 9. 生成测试报告 ============
echo ""
echo "=========================================="
echo "✅ 验证完成"
echo "=========================================="
echo ""
echo "测试环境:"
echo "  L2 RPC: $L2_RPC_URL"
echo "  链 ID: $(cast chain-id --rpc-url "$L2_RPC_URL")"
echo "  当前区块: $(cast block-number --rpc-url "$L2_RPC_URL")"
echo ""
echo "合约地址:"
echo "  KYCRegistry:        $KYC_REGISTRY_ADDR"
echo "  AccessController:   $ACCESS_CONTROLLER_ADDR"
echo "  LimitController:    $LIMIT_CONTROLLER_ADDR"
echo "  KYCGuardedToken:    $KGT_ADDR"
echo ""
echo "测试结果:"
echo "  ✅ 单元测试: 通过"
echo "  ✅ AccessController 集成: 通过"
echo "  ✅ LimitController 集成: 通过"
echo "  ✅ 端到端功能: 通过"
echo ""
echo "=========================================="

