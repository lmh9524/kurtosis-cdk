// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./../RWAAssetTypes.sol";

/// @title IAssetRegistry
/// @notice Registry for high-level RWA products (not individual positions).
interface IAssetRegistry {
    /// @notice Emitted when a new RWA asset is registered.
    event AssetRegistered(bytes32 indexed assetId, address indexed token, address indexed issuer);

    /// @notice Emitted when metadata of an existing asset is updated.
    /// @dev Struct fields are flattened in the event for simpler indexing.
    event AssetMetadataUpdated(
        bytes32 indexed assetId,
        RWAAssetTypes.AssetType assetType,
        RWAAssetTypes.AssetStatus status,
        address indexed token,
        bytes32 legalDocHash,
        bytes32 jurisdiction,
        bytes32 custodian,
        address indexed operator
    );

    /// @notice Emitted when the status of an asset changes.
    event AssetStatusChanged(bytes32 indexed assetId, RWAAssetTypes.AssetStatus oldStatus, RWAAssetTypes.AssetStatus newStatus, address indexed operator);

    /// @notice Register a new RWA product and link it to a tradable token.
    /// @param assetId Stable identifier for the asset (e.g. hash of external ID / ISIN).
    /// @param token Underlying tradable token contract (e.g. KYCGuardedToken instance).
    /// @param assetType High-level category (bond, fund, real estate, invoice, etc.).
    /// @param legalDocHash Hash of primary legal / issuance documents.
    /// @param jurisdiction Encoded jurisdiction / region identifier.
    /// @param custodian Encoded custodian identifier.
    function registerAsset(
        bytes32 assetId,
        address token,
        RWAAssetTypes.AssetType assetType,
        bytes32 legalDocHash,
        bytes32 jurisdiction,
        bytes32 custodian
    ) external;

    /// @notice Update asset metadata (docs / jurisdiction / custodian).
    function updateAssetMetadata(
        bytes32 assetId,
        bytes32 legalDocHash,
        bytes32 jurisdiction,
        bytes32 custodian
    ) external;

    /// @notice Update asset lifecycle status, e.g. Pending -> Active -> Frozen/Defaulted/Redeemed.
    function setAssetStatus(bytes32 assetId, RWAAssetTypes.AssetStatus newStatus) external;

    /// @notice Get full metadata for a registered asset.
    function getAsset(bytes32 assetId) external view returns (RWAAssetTypes.AssetMetadata memory);

    /// @notice Return whether an asset is registered.
    function isRegistered(bytes32 assetId) external view returns (bool);
}

