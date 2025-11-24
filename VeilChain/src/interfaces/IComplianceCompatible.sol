// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IComplianceCompatible
 * @notice 轻量级合规接口（受 ERC-3643 启发，但不依赖 OnchainID）
 * @dev 为现有 KYCRegistry 提供标准化的查询接口
 */
interface IComplianceCompatible {
    // ========== 核心合规查询（类 ERC-3643） ==========
    
    /// @notice 检查地址是否通过合规验证（类似 ERC-3643 的 isVerified）
    /// @param _userAddress 用户地址
    /// @return bool 是否通过验证
    function isVerified(address _userAddress) external view returns (bool);
    
    /// @notice 检查地址是否被冻结
    /// @param _userAddress 用户地址
    /// @return bool 是否冻结
    function isFrozen(address _userAddress) external view returns (bool);
    
    // ========== 扩展查询（保持 Veil 特色） ==========
    
    /// @notice 获取 KYC 等级
    function getKYCLevel(address _user) external view returns (uint8);
    
    /// @notice 获取风险等级
    function getRiskLevel(address _user) external view returns (uint8);
    
    /// @notice 获取过期时间
    function getExpiry(address _user) external view returns (uint256);
}

