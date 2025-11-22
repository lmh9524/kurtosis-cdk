// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IAccessController.sol";

/// @title AccessController
/// @notice Uses KYCRegistry to decide whether transfers / mints are allowed.
/// @dev This contract is intentionally minimal for the PoC. More complex
///      risk rules (limits per address, per-asset, country blocks, etc.)
///      can be layered on top later.
contract AccessController is IAccessController, AccessControl, Pausable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IKYCRegistry public override kycRegistry;

    constructor(address admin_, address kycRegistry_) {
        require(admin_ != address(0), "AccessController: admin is zero");
        require(kycRegistry_ != address(0), "AccessController: registry is zero");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);

        kycRegistry = IKYCRegistry(kycRegistry_);
        emit KYCRegistryUpdated(address(0), kycRegistry_, admin_);
    }

    /// @notice Update the KYC registry reference (e.g. after an upgrade).
    function setKYCRegistry(address newRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRegistry != address(0), "AccessController: registry is zero");

        address old = address(kycRegistry);
        kycRegistry = IKYCRegistry(newRegistry);
        emit KYCRegistryUpdated(old, newRegistry, _msgSender());
    }

    /// @inheritdoc IAccessController
    function canTransfer(address from, address to) public view override returns (bool) {
        if (paused()) {
            return false;
        }

        // Disallow transfers involving the zero address (mint/burn handled separately).
        if (from == address(0) || to == address(0)) {
            return false;
        }

        if (!kycRegistry.isKYCApproved(from)) {
            return false;
        }
        if (!kycRegistry.isKYCApproved(to)) {
            return false;
        }

        return true;
    }

    /// @inheritdoc IAccessController
    function canMint(address to) public view override returns (bool) {
        if (paused()) {
            return false;
        }

        if (to == address(0)) {
            return false;
        }

        return kycRegistry.isKYCApproved(to);
    }

    // --- Pause control ---

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}

