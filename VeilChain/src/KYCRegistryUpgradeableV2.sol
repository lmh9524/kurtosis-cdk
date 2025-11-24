// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./KYCRegistryUpgradeable.sol";
import "./interfaces/IComplianceCompatible.sol";
import "./KYCDataTypes.sol";

/**
 * @title KYCRegistryUpgradeableV2
 * @notice 在 V1 基础上增加：
 *   1. 账户冻结功能（freeze/unfreeze）
 *   2. 轻量级合规接口（受 ERC-3643 启发）
 * @dev 存储布局：V1 的 _records(1) + __gap(50) -> V2 增加 _frozenAccounts(1)，剩余 __gap(49)
 */
contract KYCRegistryUpgradeableV2 is KYCRegistryUpgradeable, IComplianceCompatible {
    
    // ========== 新增存储变量 ==========
    
    /// @notice 冻结账户映射
    mapping(address => bool) private _frozenAccounts;
    
    // ========== 事件 ==========
    
    event AccountFrozen(address indexed account, address indexed admin);
    event AccountUnfrozen(address indexed account, address indexed admin);
    
    // ========== 冻结功能 ==========
    
    /// @notice 冻结账户
    /// @param account 要冻结的地址
    function freezeAccount(address account) public onlyRole(KYC_ADMIN_ROLE) whenNotPaused {
        require(account != address(0), "Cannot freeze zero address");
        require(!_frozenAccounts[account], "Already frozen");
        _frozenAccounts[account] = true;
        emit AccountFrozen(account, _msgSender());
    }
    
    /// @notice 解冻账户
    /// @param account 要解冻的地址
    function unfreezeAccount(address account) public onlyRole(KYC_ADMIN_ROLE) whenNotPaused {
        require(_frozenAccounts[account], "Not frozen");
        _frozenAccounts[account] = false;
        emit AccountUnfrozen(account, _msgSender());
    }
    
    /// @notice 检查账户是否冻结
    /// @param account 要检查的地址
    /// @return bool 是否冻结
    function isFrozen(address account) public view override(IComplianceCompatible) returns (bool) {
        return _frozenAccounts[account];
    }
    
    /// @notice 重写 isKYCApproved，增加冻结检查
    /// @dev 冻结的账户即使 KYC 通过也不被认为是 approved
    function isKYCApproved(address user) public view override(KYCRegistryUpgradeable) returns (bool) {
        if (_frozenAccounts[user]) {
            return false;
        }
        return super.isKYCApproved(user);
    }
    
    // ========== IComplianceCompatible 接口实现 ==========
    
    /// @notice 检查用户是否通过合规验证（类 ERC-3643）
    /// @param _userAddress 用户地址
    /// @return bool 是否通过验证（KYC approved 且未冻结）
    function isVerified(address _userAddress) external view override(IComplianceCompatible) returns (bool) {
        return isKYCApproved(_userAddress);
    }
    
    /// @notice 获取 KYC 等级
    function getKYCLevel(address _user) external view override(IComplianceCompatible) returns (uint8) {
        return getRecord(_user).level;
    }
    
    /// @notice 获取风险等级（复用 level 字段）
    function getRiskLevel(address _user)
        public
        view
        override(IComplianceCompatible, KYCRegistryUpgradeable)
        returns (uint8)
    {
        return KYCRegistryUpgradeable.getRiskLevel(_user);
    }
    
    /// @notice 获取过期时间
    function getExpiry(address _user) external view override(IComplianceCompatible) returns (uint256) {
        return getRecord(_user).expiry;
    }
    
    // ========== 便利方法：批量操作 ==========
    
    /// @notice 批量冻结账户
    /// @param accounts 要冻结的地址数组
    function batchFreezeAccounts(address[] calldata accounts) external onlyRole(KYC_ADMIN_ROLE) whenNotPaused {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (!_frozenAccounts[accounts[i]] && accounts[i] != address(0)) {
                _frozenAccounts[accounts[i]] = true;
                emit AccountFrozen(accounts[i], _msgSender());
            }
        }
    }
    
    // ========== 存储空位预留 ==========
    
    /// @dev V1 原有 50 个槽位，V2 使用了 1 个（_frozenAccounts），剩余 49 个
    uint256[49] private __gap;
}

