// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./RWAAssetTypes.sol";
import "./interfaces/IAssetRegistry.sol";

/// @title AssetRegistryUpgradeable
/// @notice Upgradeable version of AssetRegistry for production mainnet.
/// @dev Uses TransparentUpgradeableProxy pattern with ProxyAdmin.
contract AssetRegistryUpgradeable is 
    Initializable,
    IAssetRegistry, 
    AccessControlUpgradeable, 
    PausableUpgradeable 
{
    using RWAAssetTypes for RWAAssetTypes.AssetMetadata;

    bytes32 public constant ASSET_ADMIN_ROLE = keccak256("ASSET_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    mapping(bytes32 => RWAAssetTypes.AssetMetadata) private _assets;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract (replaces constructor for upgradeable pattern).
    /// @param admin_ The address to be granted all admin roles.
    function initialize(address admin_) public initializer {
        require(admin_ != address(0), "AssetRegistry: admin is zero");

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(ASSET_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);
    }

    /// @inheritdoc IAssetRegistry
    function registerAsset(
        bytes32 assetId,
        address token,
        RWAAssetTypes.AssetType assetType,
        bytes32 legalDocHash,
        bytes32 jurisdiction,
        bytes32 custodian
    ) external override onlyRole(ASSET_ADMIN_ROLE) whenNotPaused {
        require(assetId != bytes32(0), "AssetRegistry: assetId is zero");
        require(token != address(0), "AssetRegistry: token is zero");
        require(!_exists(assetId), "AssetRegistry: asset already exists");

        RWAAssetTypes.AssetMetadata memory meta = RWAAssetTypes.AssetMetadata({
            assetId: assetId,
            assetType: assetType,
            status: RWAAssetTypes.AssetStatus.Pending,
            token: token,
            legalDocHash: legalDocHash,
            jurisdiction: jurisdiction,
            custodian: custodian,
            issuer: _msgSender(),
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        _assets[assetId] = meta;

        emit AssetRegistered(assetId, token, meta.issuer);
        emit AssetMetadataUpdated(
            assetId,
            meta.assetType,
            meta.status,
            meta.token,
            meta.legalDocHash,
            meta.jurisdiction,
            meta.custodian,
            _msgSender()
        );
    }

    /// @inheritdoc IAssetRegistry
    function updateAssetMetadata(
        bytes32 assetId,
        bytes32 legalDocHash,
        bytes32 jurisdiction,
        bytes32 custodian
    ) external override onlyRole(ASSET_ADMIN_ROLE) whenNotPaused {
        RWAAssetTypes.AssetMetadata storage meta = _assets[assetId];
        require(_exists(assetId), "AssetRegistry: unknown asset");

        meta.legalDocHash = legalDocHash;
        meta.jurisdiction = jurisdiction;
        meta.custodian = custodian;
        meta.updatedAt = uint64(block.timestamp);

        emit AssetMetadataUpdated(
            assetId,
            meta.assetType,
            meta.status,
            meta.token,
            meta.legalDocHash,
            meta.jurisdiction,
            meta.custodian,
            _msgSender()
        );
    }

    /// @inheritdoc IAssetRegistry
    function setAssetStatus(bytes32 assetId, RWAAssetTypes.AssetStatus newStatus)
        external
        override
        onlyRole(ASSET_ADMIN_ROLE)
        whenNotPaused
    {
        RWAAssetTypes.AssetMetadata storage meta = _assets[assetId];
        require(_exists(assetId), "AssetRegistry: unknown asset");

        RWAAssetTypes.AssetStatus oldStatus = meta.status;
        if (oldStatus == newStatus) {
            return;
        }

        meta.status = newStatus;
        meta.updatedAt = uint64(block.timestamp);

        emit AssetStatusChanged(assetId, oldStatus, newStatus, _msgSender());
    }

    /// @inheritdoc IAssetRegistry
    function getAsset(bytes32 assetId)
        external
        view
        override
        returns (RWAAssetTypes.AssetMetadata memory)
    {
        require(_exists(assetId), "AssetRegistry: unknown asset");
        return _assets[assetId];
    }

    /// @inheritdoc IAssetRegistry
    function isRegistered(bytes32 assetId) public view override returns (bool) {
        return _exists(assetId);
    }

    function _exists(bytes32 assetId) internal view returns (bool) {
        return _assets[assetId].assetId != bytes32(0);
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

