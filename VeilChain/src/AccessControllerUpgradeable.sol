// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IAccessController.sol";
import "./interfaces/IKYCRegistry.sol";

/// @title AccessControllerUpgradeable
/// @notice Upgradeable version of AccessController for production mainnet.
/// @dev Uses TransparentUpgradeableProxy pattern with ProxyAdmin.
contract AccessControllerUpgradeable is 
    Initializable,
    IAccessController,
    AccessControlUpgradeable, 
    PausableUpgradeable 
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IKYCRegistry public override kycRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract (replaces constructor for upgradeable pattern).
    /// @param admin_ The address to be granted all admin roles.
    /// @param kycRegistry_ The KYCRegistry contract address.
    function initialize(address admin_, address kycRegistry_) public initializer {
        require(admin_ != address(0), "AccessController: admin is zero");
        require(kycRegistry_ != address(0), "AccessController: registry is zero");

        __AccessControl_init();
        __Pausable_init();

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

    /// @dev Storage gap for future upgrades (49 slots reserved).
    uint256[49] private __gap;
}

