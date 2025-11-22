#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "部署 AssetRegistry + 注册示例 RWA 资产 到 L2（Polygon CDK devnet）"
echo "=========================================="

# 1. 基本参数（可通过环境变量覆盖）
: "${ADMIN_KEY:=0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625}"
: "${ADMIN_ADDR:=0xE34aaF64b29273B7D567FCFc40544c014EEe9970}"
: "${ETH_RPC_URL:=http://127.0.0.1:32824}"   # 当前 Kurtosis proxyd-001 L2 RPC
# 默认使用当前环境下已部署的 KYCGuardedToken，如有重新部署可通过 export KGT_ADDR 覆盖
: "${KGT_ADDR:=0x35b75f623311c87863Dd34a1fFE9A62a69fd4F87}"

export ADMIN_KEY
export ADMIN_ADDR
export ETH_RPC_URL
export KGT_ADDR
export PRIVATE_KEY="$ADMIN_KEY"

# 2. 定位 Foundry 项目根目录（VeilChain）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

echo "项目根目录: $PROJECT_ROOT"
cd "$PROJECT_ROOT"

# 3. 确保当前目录下存在 VeilChain 的 foundry.toml
if [[ ! -f "foundry.toml" ]]; then
  echo "❌ 未找到 foundry.toml，请确认在 rwa-kyc/VeilChain 目录下运行该脚本。"
  exit 1
fi

echo ""
echo "✅ Foundry 版本信息："
forge --version
cast --version

# 4. 编译合约
echo ""
echo "🛠 编译 VeilChain 合约..."
forge build

# 5. 部署 AssetRegistry
echo ""
echo "🚀 部署 AssetRegistry..."
AR_OUTPUT=$(forge script script/DeployAssetRegistry.s.sol:DeployAssetRegistry \
  --rpc-url "$ETH_RPC_URL" \
  --broadcast \
  --legacy 2>&1)

echo "$AR_OUTPUT"

ASSET_REGISTRY_ADDR=$(echo "$AR_OUTPUT" | grep -oP 'AssetRegistry deployed at:\s*\K0x[a-fA-F0-9]{40}' | head -1 || true)

if [[ -z "$ASSET_REGISTRY_ADDR" ]]; then
  echo "❌ 未能从输出中解析 AssetRegistry 地址，请在上方日志中手动查找 'AssetRegistry deployed at:'。"
  exit 1
fi

export ASSET_REGISTRY_ADDR

echo "AssetRegistry 地址: $ASSET_REGISTRY_ADDR"

# 6. 注册一个示例 RWA 资产（bond-2025-001），参数与关键信息记录保持一致
echo ""
echo "📝 注册示例 RWA 资产 bond-2025-001..."

ASSET_ID=0xcc6b75307f7f2af86b5148ef35bebed75531940a80b3aaf67e51d672af689d67
LEGAL_DOC_HASH=0x47d23278575c32bdc9e00123d9c83ff0485c6569aa3fffdf87fc793efd85f994
JURISDICTION=0xf8609dc9e17ae3d389c9f285ef4a3418632c9ba23251295f985500bcfc7f3ee5
CUSTODIAN=0x251e591c8582c2c9158ff6d76fc9a9bb33e386cb9483a2a147f345482f6a2a20
ASSET_TYPE_BOND=1  # RWAAssetTypes.AssetType.Bond

REGISTER_OUTPUT=$(cast send "$ASSET_REGISTRY_ADDR" \
  "registerAsset(bytes32,address,uint8,bytes32,bytes32,bytes32)" \
  "$ASSET_ID" "$KGT_ADDR" "$ASSET_TYPE_BOND" "$LEGAL_DOC_HASH" "$JURISDICTION" "$CUSTODIAN" \
  --private-key "$ADMIN_KEY" \
  --rpc-url "$ETH_RPC_URL" 2>&1)

echo "$REGISTER_OUTPUT"

REGISTER_TX_HASH=$(echo "$REGISTER_OUTPUT" | grep -oP 'transactionHash\s+\K0x[a-fA-F0-9]{64}' | head -1 || true)

# 7. 简单验证：检查 isRegistered(assetId)
echo ""
echo "🔍 验证资产是否已注册..."
IS_REGISTERED=$(cast call "$ASSET_REGISTRY_ADDR" \
  "isRegistered(bytes32)(bool)" \
  "$ASSET_ID" \
  --rpc-url "$ETH_RPC_URL")

echo "isRegistered(assetId) = $IS_REGISTERED"

# 8. 总结输出
echo ""
echo "=========================================="
echo "✅ AssetRegistry + 示例资产 部署与注册完成"
echo "=========================================="
echo "Admin 地址:            $ADMIN_ADDR"
echo "KYCGuardedToken 地址:  $KGT_ADDR"
echo "AssetRegistry 地址:    $ASSET_REGISTRY_ADDR"
echo "示例资产 ID:           $ASSET_ID (bond-2025-001)"
echo "示例资产类型:          AssetType.Bond (1)"
echo "示例资产注册 Tx Hash:  ${REGISTER_TX_HASH:-<未解析，可在上方日志中查看>}"
echo "L2 RPC:                $ETH_RPC_URL"
echo "=========================================="
echo "后续建议："
echo "1) 使用 cast 调用 getAsset(assetId)，核对 token / legalDocHash / jurisdiction / custodian 等字段；"
echo "2) 在文档中（如三周实施计划 Week 2 第 11–13 天）记录本次合约地址和示例资产信息，标记为“已实施 & 已验证”。"

