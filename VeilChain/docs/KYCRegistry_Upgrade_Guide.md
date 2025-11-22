# KYCRegistry 升级指南（PoC → Upgradeable v1）

## 概述

本文档描述如何将 KYCRegistry 从 PoC 版本（不可升级）迁移到可升级版本（TransparentUpgradeableProxy 模式）。

## 架构变更

### PoC 版本（v0.1-poc）
- 直接部署合约实例
- 无法升级逻辑
- 如需修改需重新部署并迁移所有依赖

### 可升级版本（v1.0）
- **实现合约**：`KYCRegistryUpgradeable` - 包含业务逻辑
- **代理合约**：`TransparentUpgradeableProxy` - 用户交互入口，存储所有状态
- **管理合约**：`ProxyAdmin` - 控制升级权限
- 未来可升级逻辑而不影响地址和状态

## 存储布局保证

升级版本保持了与 PoC 版本完全相同的存储布局：

```
Slot 0: AccessControl._roles
Slot 1: Pausable._paused  
Slot 2: mapping(address => KYCRecord) _records
Slot 3-52: __gap (预留 50 个空位用于未来升级)
```

## 部署步骤

### 前提条件

1. 确保已安装 `openzeppelin-contracts-upgradeable` 库
2. 设置环境变量：
   ```bash
   export PRIVATE_KEY=0x...
   export ADMIN_ADDRESS=0x...  # 将获得所有角色的管理员地址
   ```

### 步骤 1：部署可升级合约栈

```bash
cd rwa-kyc/VeilChain

# 部署 KYCRegistry 可升级版本
forge script script/DeployKYCRegistryUpgradeable.s.sol:DeployKYCRegistryUpgradeable \
  --rpc-url $L2_RPC_URL \
  --broadcast \
  --verify

# 记录输出的三个地址：
# - Implementation: 0x...
# - ProxyAdmin: 0x...
# - Proxy: 0x...  (这是要使用的地址)
```

### 步骤 2：更新依赖合约指向

```bash
# 设置新的 KYCRegistry Proxy 地址
export KYC_REGISTRY_PROXY_ADDRESS=0x...  # 从步骤1获取
export ACCESS_CONTROLLER_ADDRESS=0x...   # 现有的 AccessController
export LIMIT_CONTROLLER_ADDRESS=0x...    # 现有的 LimitController

# 更新引用
forge script script/UpdateKYCRegistryReferences.s.sol:UpdateKYCRegistryReferences \
  --rpc-url $L2_RPC_URL \
  --broadcast
```

### 步骤 3：验证部署

使用 `cast` 验证：

```bash
# 验证 Proxy 可以调用
cast call $KYC_REGISTRY_PROXY_ADDRESS "hasRole(bytes32,address)" \
  $(cast keccak "DEFAULT_ADMIN_ROLE()") \
  $ADMIN_ADDRESS \
  --rpc-url $L2_RPC_URL

# 验证 AccessController 指向新地址
cast call $ACCESS_CONTROLLER_ADDRESS "kycRegistry()" --rpc-url $L2_RPC_URL

# 验证 LimitController 指向新地址
cast call $LIMIT_CONTROLLER_ADDRESS "kycRegistry()" --rpc-url $L2_RPC_URL
```

## 升级演练（V1 → V2）

### 部署 V2 实现并升级

```bash
export PROXY_ADMIN_ADDRESS=0x...  # 从部署步骤获取
export KYC_REGISTRY_PROXY_ADDRESS=0x...

forge script script/UpgradeKYCRegistryToV2.s.sol:UpgradeKYCRegistryToV2 \
  --rpc-url $L2_RPC_URL \
  --broadcast
```

### 验证升级

```bash
# 调用新的 V2 函数（注意：不能用 ProxyAdmin owner 调用）
cast call $KYC_REGISTRY_PROXY_ADDRESS "version()" --rpc-url $L2_RPC_URL
# 应返回: "v2.0.0"

# 验证旧数据仍然存在
cast call $KYC_REGISTRY_PROXY_ADDRESS "isKYCApproved(address)" $USER_ADDRESS --rpc-url $L2_RPC_URL
```

## 运行测试

```bash
cd rwa-kyc/VeilChain

# 运行升级测试套件
forge test --match-contract KYCRegistryUpgradeTest -vvv

# 预期输出：所有测试通过
# ✓ test_InitialSetup
# ✓ test_SetAndGetKYCStatus
# ✓ test_UpgradeToV2
# ✓ test_PauseUnpause
# ✓ test_ExpiryCheck
# ✓ test_CannotReinitialize
# ✓ test_OnlyAdminCanSetKYC
```

## 治理迁移（生产环境）

在测试网验证通过后，主网部署需要将 ProxyAdmin ownership 转移到多签钱包：

```bash
# 1. 部署或获取 Gnosis Safe 地址
export GNOSIS_SAFE_ADDRESS=0x...

# 2. 转移 ProxyAdmin ownership
cast send $PROXY_ADMIN_ADDRESS \
  "transferOwnership(address)" \
  $GNOSIS_SAFE_ADDRESS \
  --rpc-url $L2_RPC_URL \
  --private-key $PRIVATE_KEY

# 3. 验证 ownership 转移
cast call $PROXY_ADMIN_ADDRESS "owner()" --rpc-url $L2_RPC_URL
```

后续所有升级操作需要通过 Gnosis Safe 多签确认。

## 注意事项

### TransparentProxy 特性
- **ProxyAdmin owner 不能直接调用实现合约函数**，只能调用管理函数
- 功能测试时使用非 ProxyAdmin owner 的地址
- 脚本中的交互调用应使用普通账户，管理调用使用 ProxyAdmin owner

### 存储安全
- 升级时**不能修改现有状态变量的顺序**
- 新状态变量只能追加到末尾
- 使用 `__gap` 预留空间
- 升级前后使用 `forge inspect storage-layout` 对比

### 数据迁移（可选）
如果需要从旧 KYCRegistry 迁移数据：

```solidity
// 在脚本中批量迁移
for (uint i = 0; i < users.length; i++) {
    KYCRecord memory oldRecord = oldRegistry.getRecord(users[i]);
    newRegistry.setKYCStatus(
        users[i],
        oldRecord.status,
        oldRecord.level,
        oldRecord.expiry,
        oldRecord.kycProviderId
    );
}
```

## 回滚策略

如果升级后发现问题：

1. **降级到旧实现**：
   ```bash
   # 通过 ProxyAdmin 回滚到之前的实现地址
   cast send $PROXY_ADMIN_ADDRESS \
     "upgrade(address,address)" \
     $PROXY_ADDRESS \
     $OLD_IMPLEMENTATION_ADDRESS \
     --rpc-url $L2_RPC_URL
   ```

2. **紧急暂停**：
   ```bash
   # 使用 PAUSER_ROLE 暂停合约
   cast send $KYC_REGISTRY_PROXY_ADDRESS \
     "pause()" \
     --rpc-url $L2_RPC_URL \
     --private-key $PAUSER_PRIVATE_KEY
   ```

## 相关文件

- 实现合约：`src/KYCRegistryUpgradeable.sol`
- V2 演示：`src/KYCRegistryV2.sol`
- 部署脚本：`script/DeployKYCRegistryUpgradeable.s.sol`
- 升级脚本：`script/UpgradeKYCRegistryToV2.s.sol`
- 引用更新：`script/UpdateKYCRegistryReferences.s.sol`
- 测试套件：`test/KYCRegistryUpgrade.t.sol`
- 存储布局：`docs/KYCRegistry_v0_storage_layout.txt`

## 后续步骤

1. 在本地/测试网完成完整部署和升级演练
2. 将其他合约（AccessController、LimitController、KYCGuardedToken）也改造为可升级
3. 集成 Timelock 和 Gnosis Safe 多签治理
4. 进行专业安全审计
5. 在主网部署前进行影子网络压测

