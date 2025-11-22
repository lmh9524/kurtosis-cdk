// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AssetRegistry.sol";
import "../src/RWAAssetTypes.sol";

contract AssetRegistryTest is Test {
    AssetRegistry private registry;
    address private admin = address(this);
    address private token = address(0xA11CE);

    function setUp() public {
        registry = new AssetRegistry(admin);
    }

    function testRegisterAssetAndReadBack() public {
        bytes32 assetId = keccak256("bond-2025-001");
        bytes32 legalDocHash = keccak256("legal-doc");
        bytes32 jurisdiction = keccak256("CN");
        bytes32 custodian = keccak256("bank-1");

        registry.registerAsset(
            assetId,
            token,
            RWAAssetTypes.AssetType.Bond,
            legalDocHash,
            jurisdiction,
            custodian
        );

        assertTrue(registry.isRegistered(assetId));
        RWAAssetTypes.AssetMetadata memory meta = registry.getAsset(assetId);
        assertEq(meta.assetId, assetId);
        assertEq(address(meta.token), token);
        assertEq(uint8(meta.assetType), uint8(RWAAssetTypes.AssetType.Bond));
        assertEq(uint8(meta.status), uint8(RWAAssetTypes.AssetStatus.Pending));
        assertEq(meta.legalDocHash, legalDocHash);
        assertEq(meta.jurisdiction, jurisdiction);
        assertEq(meta.custodian, custodian);
        assertEq(meta.issuer, admin);
        assertGt(meta.createdAt, 0);
    }

    function testUpdateMetadata() public {
        bytes32 assetId = keccak256("bond-2025-002");
        registry.registerAsset(
            assetId,
            token,
            RWAAssetTypes.AssetType.Bond,
            bytes32(0),
            bytes32(0),
            bytes32(0)
        );

        bytes32 newLegal = keccak256("new-doc");
        bytes32 newJurisdiction = keccak256("US");
        bytes32 newCustodian = keccak256("bank-2");

        registry.updateAssetMetadata(assetId, newLegal, newJurisdiction, newCustodian);
        RWAAssetTypes.AssetMetadata memory meta = registry.getAsset(assetId);
        assertEq(meta.legalDocHash, newLegal);
        assertEq(meta.jurisdiction, newJurisdiction);
        assertEq(meta.custodian, newCustodian);
    }

    function testSetStatus() public {
        bytes32 assetId = keccak256("bond-2025-003");
        registry.registerAsset(
            assetId,
            token,
            RWAAssetTypes.AssetType.Bond,
            bytes32(0),
            bytes32(0),
            bytes32(0)
        );

        registry.setAssetStatus(assetId, RWAAssetTypes.AssetStatus.Active);
        RWAAssetTypes.AssetMetadata memory meta = registry.getAsset(assetId);
        assertEq(uint8(meta.status), uint8(RWAAssetTypes.AssetStatus.Active));

        registry.setAssetStatus(assetId, RWAAssetTypes.AssetStatus.Frozen);
        meta = registry.getAsset(assetId);
        assertEq(uint8(meta.status), uint8(RWAAssetTypes.AssetStatus.Frozen));
    }

    function testNonAdminCannotRegisterOrUpdate() public {
        address nonAdmin = address(0xBEEF);

        bytes32 assetId = keccak256("bond-2025-004");
        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.registerAsset(
            assetId,
            token,
            RWAAssetTypes.AssetType.Bond,
            bytes32(0),
            bytes32(0),
            bytes32(0)
        );

        // register as admin, then try non-admin metadata update
        registry.registerAsset(
            assetId,
            token,
            RWAAssetTypes.AssetType.Bond,
            bytes32(0),
            bytes32(0),
            bytes32(0)
        );

        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.updateAssetMetadata(assetId, bytes32(0), bytes32(0), bytes32(0));
    }

    function testPauseBlocksAdminOperations() public {
        bytes32 assetId = keccak256("bond-2025-005");

        registry.pause();

        vm.expectRevert();
        registry.registerAsset(
            assetId,
            token,
            RWAAssetTypes.AssetType.Bond,
            bytes32(0),
            bytes32(0),
            bytes32(0)
        );

        vm.expectRevert();
        registry.setAssetStatus(assetId, RWAAssetTypes.AssetStatus.Active);
    }
}

