// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./KYCDataTypes.sol";
import "./interfaces/IKYCRegistry.sol";

/// @title KYCRegistryUpgradeable
/// @notice Upgradeable version of KYCRegistry for production mainnet.
/// @dev Uses TransparentUpgradeableProxy pattern with ProxyAdmin.
contract KYCRegistryUpgradeable is 
    Initializable,
    IKYCRegistry, 
    AccessControlUpgradeable, 
    PausableUpgradeable 
{
    bytes32 public constant KYC_ADMIN_ROLE = keccak256("KYC_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(address => KYCRecord) private _records;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract (replaces constructor for upgradeable pattern).
    /// @param admin_ The address to be granted all admin roles.
    function initialize(address admin_) public initializer {
        require(admin_ != address(0), "KYCRegistry: admin is zero");

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(KYC_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
    }

    /// @inheritdoc IKYCRegistry
    function setKYCStatus(
        address user,
        Status status,
        uint8 level,
        uint256 expiry,
        bytes32 kycProviderId
    ) external override onlyRole(KYC_ADMIN_ROLE) whenNotPaused {
        require(user != address(0), "KYCRegistry: user is zero");

        _records[user] = KYCRecord({
            status: status,
            level: level,
            updatedAt: uint64(block.timestamp),
            expiry: expiry,
            kycProviderId: kycProviderId
        });

        emit KYCStatusUpdated(user, status, level, expiry, kycProviderId, _msgSender());
    }

    /// @inheritdoc IKYCRegistry
    function isKYCApproved(address user) public view override returns (bool) {
        KYCRecord memory record = _records[user];

        if (record.status != Status.Approved) {
            return false;
        }

        if (record.expiry != 0 && record.expiry < block.timestamp) {
            return false;
        }

        return true;
    }

    /// @inheritdoc IKYCRegistry
    function getRiskLevel(address user) public view override returns (uint8) {
        return _records[user].level;
    }

    /// @inheritdoc IKYCRegistry
    function getRecord(address user) public view override returns (KYCRecord memory) {
        return _records[user];
    }

    // --- Pause control ---

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Storage gap for future upgrades (50 slots reserved).
    uint256[50] private __gap;
}

