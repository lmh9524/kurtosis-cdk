// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TransparentUpgradeableProxy.sol";

/// @notice Minimal ProxyAdmin compatible with the classic transparent proxy pattern.
/// @dev 这里只实现本项目用到的 owner、transferOwnership 和 upgradeAndCall 接口，
///      行为等价于 OpenZeppelin 4.9 时代的 ProxyAdmin。
contract ProxyAdmin {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == _owner, "ProxyAdmin: caller is not the owner");
        _;
    }

    constructor(address initialOwner) {
        require(initialOwner != address(0), "ProxyAdmin: owner is zero");
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ProxyAdmin: new owner is zero");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    /// @notice Upgrades `proxy` to `implementation` without calling any function.
    /// @dev 兼容 OpenZeppelin ProxyAdmin 的 `upgrade` 接口，供测试和脚本复用。
    function upgrade(ITransparentUpgradeableProxy proxy, address implementation) external onlyOwner {
        proxy.upgradeToAndCall(implementation, "");
    }

    /// @notice Upgrades `proxy` to `implementation` and optionally calls a function on the new implementation.
    /// @dev 与 OZ ProxyAdmin 的 upgradeAndCall 语义保持一致：
    ///      - 由 ProxyAdmin owner 调用
    ///      - 代理自身的 admin 必须是本 ProxyAdmin 实例
    ///      - 当 data 为空时，要求 msg.value 为 0
    function upgradeAndCall(
        ITransparentUpgradeableProxy proxy,
        address implementation,
        bytes memory data
    ) external payable onlyOwner {
        proxy.upgradeToAndCall{value: msg.value}(implementation, data);
    }
}


