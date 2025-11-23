// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ITransparentUpgradeableProxy
/// @notice Interface for TransparentUpgradeableProxy
/// @dev This interface is needed for OpenZeppelin v5.0.0 compatibility
interface ITransparentUpgradeableProxy {
    function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

