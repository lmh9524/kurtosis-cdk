// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title RWAAssetTypes
/// @notice Shared enums and structs for RWA asset registration & lifecycle.
/// @dev Kept minimal; high-level design follows internal RWA docs.
library RWAAssetTypes {
    /// @notice High-level asset category for an RWA product.
    enum AssetType {
        Unknown,
        Bond,
        Fund,
        RealEstate,
        Invoice
    }

    /// @notice Lifecycle status of an RWA product on-chain.
    enum AssetStatus {
        Pending,
        Active,
        Frozen,
        Defaulted,
        Redeemed,
        Closed
    }

    /// @notice Core metadata for an RWA product managed by AssetRegistry.
    struct AssetMetadata {
        bytes32 assetId; // stable identifier (e.g. hash of external ID)
        AssetType assetType;
        AssetStatus status;
        address token; // underlying tradable token (e.g. KYCGuardedToken)
        bytes32 legalDocHash; // hash of primary legal / issuance docs
        bytes32 jurisdiction; // e.g. ISO country / region code
        bytes32 custodian; // abstracted custodian identifier
        address issuer; // address that registered the asset
        uint64 createdAt;
        uint64 updatedAt;
    }
}

