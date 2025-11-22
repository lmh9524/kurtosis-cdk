// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IKYCRegistry.sol";

/// @title IAccessController
/// @notice Thin access-control facade over KYCRegistry for business contracts (tokens, gates, etc.).
interface IAccessController {
    /// @notice Emitted when the underlying KYC registry is updated.
    event KYCRegistryUpdated(
        address indexed oldRegistry,
        address indexed newRegistry,
        address indexed operator
    );

    /// @notice Current KYC registry used for checks.
    function kycRegistry() external view returns (IKYCRegistry);

    /// @notice Whether a transfer from `from` to `to` is allowed under current rules.
    function canTransfer(address from, address to) external view returns (bool);

    /// @notice Whether minting tokens to `to` is allowed under current rules.
    function canMint(address to) external view returns (bool);
}

