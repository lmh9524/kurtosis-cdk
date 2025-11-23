# EC2 上测试验证 Upgradeable 合约栈指南

## 前置条件

1. **EC2 服务器已配置**：
   - Kurtosis CDK 环境运行中
   - Foundry 已安装
   - Docker 权限已配置

2. **环境变量准备**：
   ```bash
   export ADMIN_ADDR="0xE34aaF64b29273B7D567FCFc40544c014EEe9970"
   export ADMIN_KEY="0x12d7de8621a77640c9241b2595ba78ce443d05e94090365ab3bb5e19df82c625"
   export ETH_RPC_URL="http://127.0.0.1:1043"  # 或从 kurtosis port print 获取
   ```

3. **代码已同步**：
   ```bash
   cd ~/kurtosis-cdk
   git pull origin mainnet-v1-dev
   cd VeilChain
   ```

---

## 步骤 1：编译合约

```bash
cd ~/kurtosis-cdk/VeilChain

# 编译所有合约（包括新的 Upgradeable 版本）
forge build
```

**预期输出**：编译成功，无错误

---

## 步骤 2：运行单元测试

```bash
# 运行所有升级相关测试
forge test --match-path "**/*Upgrade*.t.sol" -vv

# 或运行所有测试
forge test -vv
```

**预期结果**：
- ✅ `AccessControllerUpgradeTest` 所有测试通过
- ✅ `LimitControllerUpgradeTest` 所有测试通过
- ✅ `KYCGuardedTokenUpgradeTest` 所有测试通过
- ✅ `AssetRegistryUpgradeTest` 所有测试通过

---

## 步骤 3：部署 Upgradeable 合约栈

### 方式 A：使用自动化脚本（推荐）

```bash
cd ~/kurtosis-cdk/VeilChain

# 确保脚本有执行权限
chmod +x script/deploy_all_upgradeable_stack.sh

# 执行部署
./script/deploy_all_upgradeable_stack.sh
```

脚本会：
1. 自动检测 RPC URL
2. 按顺序部署所有 Upgradeable 合约
3. 配置合约间引用
4. 输出所有合约地址

**注意**：脚本会提示你输入部署后的合约地址，这些地址需要保存用于后续验证。

### 方式 B：手动部署（逐步执行）

#### 3.1 部署 KYCRegistryUpgradeable

```bash
export ADMIN_ADDRESS="$ADMIN_ADDR"
forge script script/DeployKYCRegistryUpgradeable.s.sol:DeployKYCRegistryUpgradeable \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy

# 从输出中提取 Proxy 地址，例如：
export KYC_REGISTRY_PROXY_ADDR="0x..."
```

#### 3.2 部署 AccessControllerUpgradeable

```bash
export KYC_REGISTRY_ADDR="$KYC_REGISTRY_PROXY_ADDR"
forge script script/DeployAccessControllerUpgradeable.s.sol:DeployAccessControllerUpgradeable \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy

export ACCESS_CONTROLLER_PROXY_ADDR="0x..."  # 从输出提取
```

#### 3.3 部署 LimitControllerUpgradeable

```bash
export KYC_REGISTRY_ADDR="$KYC_REGISTRY_PROXY_ADDR"
forge script script/DeployLimitControllerUpgradeable.s.sol:DeployLimitControllerUpgradeable \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy

export LIMIT_CONTROLLER_PROXY_ADDR="0x..."  # 从输出提取
```

#### 3.4 部署 KYCGuardedTokenUpgradeable

```bash
export ACCESS_CONTROLLER_ADDR="$ACCESS_CONTROLLER_PROXY_ADDR"
export TOKEN_NAME="KYC Guarded Token"
export TOKEN_SYMBOL="KGT"
forge script script/DeployKYCGuardedTokenUpgradeable.s.sol:DeployKYCGuardedTokenUpgradeable \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy

export KYC_GUARDED_TOKEN_PROXY_ADDR="0x..."  # 从输出提取
```

#### 3.5 部署 AssetRegistryUpgradeable

```bash
forge script script/DeployAssetRegistryUpgradeable.s.sol:DeployAssetRegistryUpgradeable \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy

export ASSET_REGISTRY_PROXY_ADDR="0x..."  # 从输出提取
```

#### 3.6 配置合约间引用

```bash
# 在 KYCGuardedToken 上设置 LimitController
cast send "$KYC_GUARDED_TOKEN_PROXY_ADDR" \
    "setLimitController(address)" "$LIMIT_CONTROLLER_PROXY_ADDR" \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --legacy

# 授予 KYCGuardedToken CALLER_ROLE
CALLER_ROLE=$(cast call "$LIMIT_CONTROLLER_PROXY_ADDR" "CALLER_ROLE()(bytes32)" --rpc-url "$ETH_RPC_URL")
cast send "$LIMIT_CONTROLLER_PROXY_ADDR" \
    "grantRole(bytes32,address)" "$CALLER_ROLE" "$KYC_GUARDED_TOKEN_PROXY_ADDR" \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --legacy
```

---

## 步骤 4：验证部署

### 使用验证脚本

```bash
chmod +x script/verify_upgradeable_stack.sh
./script/verify_upgradeable_stack.sh
```

### 手动验证

```bash
# 1. 验证合约存在
cast code "$KYC_REGISTRY_PROXY_ADDR" --rpc-url "$ETH_RPC_URL"
cast code "$ACCESS_CONTROLLER_PROXY_ADDR" --rpc-url "$ETH_RPC_URL"
cast code "$LIMIT_CONTROLLER_PROXY_ADDR" --rpc-url "$ETH_RPC_URL"
cast code "$KYC_GUARDED_TOKEN_PROXY_ADDR" --rpc-url "$ETH_RPC_URL"

# 2. 验证 AccessController 配置
cast call "$ACCESS_CONTROLLER_PROXY_ADDR" "kycRegistry()(address)" --rpc-url "$ETH_RPC_URL"
# 应该返回 KYC_REGISTRY_PROXY_ADDR

# 3. 验证 LimitController 配置
cast call "$LIMIT_CONTROLLER_PROXY_ADDR" "kycRegistry()(address)" --rpc-url "$ETH_RPC_URL"
cast call "$LIMIT_CONTROLLER_PROXY_ADDR" "levelLimits(uint8)(uint256,uint256,bool)" "1" --rpc-url "$ETH_RPC_URL"

# 4. 验证 KYCGuardedToken 配置
cast call "$KYC_GUARDED_TOKEN_PROXY_ADDR" "accessController()(address)" --rpc-url "$ETH_RPC_URL"
cast call "$KYC_GUARDED_TOKEN_PROXY_ADDR" "limitController()(address)" --rpc-url "$ETH_RPC_URL"
```

---

## 步骤 5：端到端功能测试

### 5.1 设置测试用户 KYC

```bash
TEST_USER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"  # 或使用其他测试地址

cast send "$KYC_REGISTRY_PROXY_ADDR" \
    "setKYCStatus(address,uint8,uint8,uint256,bytes32)" \
    "$TEST_USER" \
    "2" \
    "1" \
    "$(cast --to-uint256 $(($(date +%s) + 365 * 86400)))" \
    "$(cast --to-bytes32 "provider-test")" \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --legacy
```

### 5.2 配置限额

```bash
cast send "$LIMIT_CONTROLLER_PROXY_ADDR" \
    "setLevelLimits(uint8,uint256,uint256,bool)" \
    "1" \
    "$(cast --to-uint256 1000000000000000000000)" \
    "$(cast --to-uint256 10000000000000000000000)" \
    "true" \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --legacy
```

### 5.3 测试 Mint

```bash
cast send "$KYC_GUARDED_TOKEN_PROXY_ADDR" \
    "mint(address,uint256)" \
    "$TEST_USER" \
    "$(cast --to-uint256 100000000000000000000000)" \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --legacy

# 验证余额
cast call "$KYC_GUARDED_TOKEN_PROXY_ADDR" "balanceOf(address)(uint256)" "$TEST_USER" --rpc-url "$ETH_RPC_URL"
```

### 5.4 测试 Transfer（限额检查）

```bash
TEST_USER_B="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"

# 先为 USER_B 设置 KYC
cast send "$KYC_REGISTRY_PROXY_ADDR" \
    "setKYCStatus(address,uint8,uint8,uint256,bytes32)" \
    "$TEST_USER_B" \
    "2" \
    "1" \
    "$(cast --to-uint256 $(($(date +%s) + 365 * 86400)))" \
    "$(cast --to-bytes32 "provider-test")" \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --legacy

# 测试在限额内的转账（500 KGT）
cast send "$KYC_GUARDED_TOKEN_PROXY_ADDR" \
    "transfer(address,uint256)" \
    "$TEST_USER_B" \
    "$(cast --to-uint256 500000000000000000000)" \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --from "$TEST_USER" \
    --legacy

# 测试超过单笔限额的转账（1500 KGT，应该失败）
cast send "$KYC_GUARDED_TOKEN_PROXY_ADDR" \
    "transfer(address,uint256)" \
    "$TEST_USER_B" \
    "$(cast --to-uint256 1500000000000000000000)" \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --from "$TEST_USER" \
    --legacy
# 预期：revert with "LimitController: single tx limit exceeded"
```

---

## 步骤 6：测试升级功能

### 6.1 升级 AccessController

```bash
export PROXY_ADMIN_ADDR="0x..."  # 从部署输出中获取
export ACCESS_CONTROLLER_PROXY_ADDR="0x..."

forge script script/UpgradeAccessController.s.sol:UpgradeAccessController \
    --rpc-url "$ETH_RPC_URL" \
    --private-key "$ADMIN_KEY" \
    --broadcast \
    --legacy
```

### 6.2 验证升级后状态保持

```bash
# 验证 kycRegistry 地址未变
cast call "$ACCESS_CONTROLLER_PROXY_ADDR" "kycRegistry()(address)" --rpc-url "$ETH_RPC_URL"

# 验证功能仍然正常
cast call "$ACCESS_CONTROLLER_PROXY_ADDR" "canMint(address)(bool)" "$TEST_USER" --rpc-url "$ETH_RPC_URL"
```

---

## 步骤 7：保存部署信息

将以下信息保存到 `关键信息记录.md`：

```markdown
### Phase 1 Upgradeable 合约栈部署记录

- **环境**：AWS EC2 Kurtosis CDK L2
- **L2 RPC**：`http://127.0.0.1:1043`
- **链 ID**：`2151908`（或从 `cast chain-id` 获取）
- **部署时间**：YYYY-MM-DD HH:MM:SS

- **合约地址**：
  - KYCRegistry Proxy: `0x...`
  - AccessController Proxy: `0x...`
  - LimitController Proxy: `0x...`
  - KYCGuardedToken Proxy: `0x...`
  - AssetRegistry Proxy: `0x...`
  - ProxyAdmin (AccessController): `0x...`
  - ProxyAdmin (LimitController): `0x...`
  - ProxyAdmin (KYCGuardedToken): `0x...`
  - ProxyAdmin (AssetRegistry): `0x...`

- **配置交易哈希**：
  - setLimitController: `0x...`
  - grantRole CALLER_ROLE: `0x...`
  - setLevelLimits(1): `0x...`
```

---

## 故障排查

### 问题 1：编译失败

```bash
# 检查依赖
forge install
forge update

# 清理缓存
forge clean
forge build
```

### 问题 2：RPC 连接失败

```bash
# 检查 Kurtosis 状态
kurtosis enclave ls
kurtosis port print cdk proxyd-001 rpc

# 手动测试 RPC
cast block-number --rpc-url "$ETH_RPC_URL"
```

### 问题 3：Gas 不足

```bash
# 检查余额
cast balance "$ADMIN_ADDR" --rpc-url "$ETH_RPC_URL"

# 如果余额不足，从其他账户转账
```

### 问题 4：权限错误

```bash
# 验证角色
cast call "$CONTRACT_ADDR" "hasRole(bytes32,address)(bool)" "$ROLE" "$ADMIN_ADDR" --rpc-url "$ETH_RPC_URL"

# 授予角色（如果需要）
cast send "$CONTRACT_ADDR" "grantRole(bytes32,address)" "$ROLE" "$ADMIN_ADDR" --rpc-url "$ETH_RPC_URL" --private-key "$ADMIN_KEY" --legacy
```

---

## 下一步

完成验证后，可以继续 Phase 1 的后续任务：
- 任务 5：引入 Gnosis Safe 多签
- 任务 6：引入 TimelockController
- 任务 7：拆分运营角色权限

