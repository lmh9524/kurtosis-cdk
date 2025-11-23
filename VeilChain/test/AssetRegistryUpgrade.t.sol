// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/AssetRegistryUpgradeable.sol";
import "../src/RWAAssetTypes.sol";

contract AssetRegistryUpgradeTest is Test {
    AssetRegistryUpgradeable public registry;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    
    address public admin = address(0x1);
    address public issuer = address(0x2);
    address public tokenAddr = address(0x100);
    
    bytes32 public assetId = keccak256("ASSET-001");
    
    function setUp() public {
        vm.startPrank(admin);
        
        // 1. 部署 AssetRegistryUpgradeable 实现合约
        AssetRegistryUpgradeable implementation = new AssetRegistryUpgradeable();
        
        // 2. 部署 ProxyAdmin
        proxyAdmin = new ProxyAdmin(admin);
        
        // 3. 编码初始化数据并部署 Proxy
        bytes memory initData = abi.encodeCall(
            AssetRegistryUpgradeable.initialize,
            (admin)
        );
        
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        
        // 4. 将 Proxy 包装为 AssetRegistryUpgradeable 接口
        registry = AssetRegistryUpgradeable(address(proxy));
        
        vm.stopPrank();
    }
    
    function test_InitialSetup() public view {
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.ASSET_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.PAUSER_ROLE(), admin));
    }
    
    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        registry.initialize(admin);
    }
    
    function test_RegisterAsset() public {
        vm.startPrank(admin);
        
        registry.registerAsset(
            assetId,
            tokenAddr,
            RWAAssetTypes.AssetType.Bond,
            bytes32("legal-doc-hash"),
            bytes32("US"),
            bytes32("custodian-001")
        );
        
        assertTrue(registry.isRegistered(assetId));
        
        RWAAssetTypes.AssetMetadata memory asset = registry.getAsset(assetId);
        
        assertEq(asset.assetId, assetId);
        assertEq(uint256(asset.assetType), uint256(RWAAssetTypes.AssetType.Bond));
        assertEq(uint256(asset.status), uint256(RWAAssetTypes.AssetStatus.Pending));
        assertEq(asset.token, tokenAddr);
        assertEq(asset.legalDocHash, bytes32("legal-doc-hash"));
        assertEq(asset.jurisdiction, bytes32("US"));
        assertEq(asset.custodian, bytes32("custodian-001"));
        assertEq(asset.issuer, admin);
        
        vm.stopPrank();
    }
    
    function test_RegisterAsset_Fail_DuplicateId() public {
        vm.startPrank(admin);
        
        registry.registerAsset(
            assetId,
            tokenAddr,
            RWAAssetTypes.AssetType.Bond,
            bytes32("legal-doc-hash"),
            bytes32("US"),
            bytes32("custodian-001")
        );
        
        vm.expectRevert("AssetRegistry: asset already exists");
        registry.registerAsset(
            assetId,
            tokenAddr,
            RWAAssetTypes.AssetType.Bond,
            bytes32("legal-doc-hash"),
            bytes32("US"),
            bytes32("custodian-001")
        );
        
        vm.stopPrank();
    }
    
    function test_UpdateAssetMetadata() public {
        vm.startPrank(admin);
        
        registry.registerAsset(
            assetId,
            tokenAddr,
            RWAAssetTypes.AssetType.Bond,
            bytes32("legal-doc-hash"),
            bytes32("US"),
            bytes32("custodian-001")
        );
        
        registry.updateAssetMetadata(
            assetId,
            bytes32("new-legal-doc-hash"),
            bytes32("UK"),
            bytes32("custodian-002")
        );
        
        RWAAssetTypes.AssetMetadata memory asset = registry.getAsset(assetId);
        
        assertEq(asset.legalDocHash, bytes32("new-legal-doc-hash"));
        assertEq(asset.jurisdiction, bytes32("UK"));
        assertEq(asset.custodian, bytes32("custodian-002"));
        
        vm.stopPrank();
    }
    
    function test_SetAssetStatus() public {
        vm.startPrank(admin);
        
        registry.registerAsset(
            assetId,
            tokenAddr,
            RWAAssetTypes.AssetType.Bond,
            bytes32("legal-doc-hash"),
            bytes32("US"),
            bytes32("custodian-001")
        );
        
        // 初始状态应该是 Pending
        RWAAssetTypes.AssetMetadata memory asset = registry.getAsset(assetId);
        assertEq(uint256(asset.status), uint256(RWAAssetTypes.AssetStatus.Pending));
        
        // 更新为 Active
        registry.setAssetStatus(assetId, RWAAssetTypes.AssetStatus.Active);
        
        asset = registry.getAsset(assetId);
        assertEq(uint256(asset.status), uint256(RWAAssetTypes.AssetStatus.Active));
        
        // 更新为 Frozen
        registry.setAssetStatus(assetId, RWAAssetTypes.AssetStatus.Frozen);
        
        asset = registry.getAsset(assetId);
        assertEq(uint256(asset.status), uint256(RWAAssetTypes.AssetStatus.Frozen));
        
        vm.stopPrank();
    }
    
    function test_Pause() public {
        vm.startPrank(admin);
        
        registry.pause();
        
        assertTrue(registry.paused());
        
        // 暂停时无法注册资产
        vm.expectRevert();
        registry.registerAsset(
            assetId,
            tokenAddr,
            RWAAssetTypes.AssetType.Bond,
            bytes32("legal-doc-hash"),
            bytes32("US"),
            bytes32("custodian-001")
        );
        
        // 恢复后可以注册
        registry.unpause();
        
        registry.registerAsset(
            assetId,
            tokenAddr,
            RWAAssetTypes.AssetType.Bond,
            bytes32("legal-doc-hash"),
            bytes32("US"),
            bytes32("custodian-001")
        );
        
        assertTrue(registry.isRegistered(assetId));
        
        vm.stopPrank();
    }
    
    function test_Upgrade() public {
        // 注册一些资产
        vm.startPrank(admin);
        registry.registerAsset(
            assetId,
            tokenAddr,
            RWAAssetTypes.AssetType.Bond,
            bytes32("legal-doc-hash"),
            bytes32("US"),
            bytes32("custodian-001")
        );
        
        registry.setAssetStatus(assetId, RWAAssetTypes.AssetStatus.Active);

        vm.stopPrank();

        // 升级到新实现（通过 ProxyAdmin）
        AssetRegistryUpgradeable newImplementation = new AssetRegistryUpgradeable();
        vm.prank(admin);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(newImplementation),
            ""
        );
        
        // 验证状态保持
        assertTrue(registry.isRegistered(assetId));
        
        RWAAssetTypes.AssetMetadata memory asset = registry.getAsset(assetId);
        assertEq(asset.assetId, assetId);
        assertEq(uint256(asset.status), uint256(RWAAssetTypes.AssetStatus.Active));
        assertEq(asset.token, tokenAddr);
        
        // 验证功能仍然正常
        bytes32 newAssetId = keccak256("ASSET-002");
        registry.registerAsset(
            newAssetId,
            address(0x101),
            RWAAssetTypes.AssetType.Fund,
            bytes32("new-doc-hash"),
            bytes32("SG"),
            bytes32("custodian-003")
        );
        
        assertTrue(registry.isRegistered(newAssetId));
    }
}

