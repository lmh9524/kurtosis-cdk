// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/KYCRegistryUpgradeable.sol";
import "../src/KYCRegistryV2.sol";
import "../src/KYCDataTypes.sol";

contract KYCRegistryUpgradeTest is Test {
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    KYCRegistryUpgradeable public implementation;
    KYCRegistryUpgradeable public registryProxy;
    
    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);

    function setUp() public {
        // Deploy implementation
        implementation = new KYCRegistryUpgradeable();

        // Deploy ProxyAdmin（owner = admin，与升级时使用的 msg.sender 保持一致）
        proxyAdmin = new ProxyAdmin(admin);

        // Encode initialize call
        bytes memory initData = abi.encodeWithSelector(
            KYCRegistryUpgradeable.initialize.selector,
            admin
        );

        // Deploy proxy
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        // Get proxy interface
        registryProxy = KYCRegistryUpgradeable(address(proxy));
    }

    function test_InitialSetup() public {
        // Verify admin has correct roles
        assertTrue(registryProxy.hasRole(registryProxy.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registryProxy.hasRole(registryProxy.KYC_ADMIN_ROLE(), admin));
        assertTrue(registryProxy.hasRole(registryProxy.PAUSER_ROLE(), admin));
    }

    function test_SetAndGetKYCStatus() public {
        vm.startPrank(admin);
        
        uint256 expiry = block.timestamp + 365 days;
        registryProxy.setKYCStatus(
            user1,
            Status.Approved,
            2,
            expiry,
            bytes32("provider-001")
        );

        assertTrue(registryProxy.isKYCApproved(user1));
        assertEq(registryProxy.getRiskLevel(user1), 2);

        KYCRecord memory record = registryProxy.getRecord(user1);
        assertEq(uint8(record.status), uint8(Status.Approved));
        assertEq(record.level, 2);
        assertEq(record.expiry, expiry);
        assertEq(record.kycProviderId, bytes32("provider-001"));

        vm.stopPrank();
    }

    function test_UpgradeToV2() public {
        // Set some state in V1
        vm.startPrank(admin);
        uint256 expiry = block.timestamp + 365 days;
        registryProxy.setKYCStatus(
            user1,
            Status.Approved,
            3,
            expiry,
            bytes32("provider-001")
        );
        registryProxy.setKYCStatus(
            user2,
            Status.Approved,
            1,
            expiry,
            bytes32("provider-002")
        );
        vm.stopPrank();

        // Verify V1 state
        assertTrue(registryProxy.isKYCApproved(user1));
        assertEq(registryProxy.getRiskLevel(user1), 3);

        // Deploy V2 implementation
        KYCRegistryV2 implementationV2 = new KYCRegistryV2();

        // Upgrade proxy to V2（通过 ProxyAdmin）
        vm.prank(admin);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(implementationV2),
            ""
        );

        // After upgrade, the proxy should point to V2 but keep state
        KYCRegistryV2 v2 = KYCRegistryV2(address(proxy));

        // State from V1 is preserved
        assertTrue(v2.isKYCApproved(user1));
        assertEq(v2.getRiskLevel(user1), 3);
        assertTrue(v2.isKYCApproved(user2));
        assertEq(v2.getRiskLevel(user2), 1);

        // New V2 helper functions work as expected
        assertTrue(v2.hasMinimumLevel(user1, 2));
        assertFalse(v2.hasMinimumLevel(user2, 2));
        assertEq(keccak256(bytes(v2.version())), keccak256(bytes("v2.0.0")));
    }

    function test_PauseUnpause() public {
        vm.startPrank(admin);
        
        registryProxy.pause();
        assertTrue(registryProxy.paused());

        // Should revert when paused
        vm.expectRevert();
        registryProxy.setKYCStatus(
            user1,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );

        registryProxy.unpause();
        assertFalse(registryProxy.paused());

        // Should work after unpause
        registryProxy.setKYCStatus(
            user1,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        assertTrue(registryProxy.isKYCApproved(user1));

        vm.stopPrank();
    }

    function test_ExpiryCheck() public {
        vm.startPrank(admin);
        
        uint256 expiry = block.timestamp + 1 days;
        registryProxy.setKYCStatus(
            user1,
            Status.Approved,
            1,
            expiry,
            bytes32("provider-001")
        );

        // Should be approved before expiry
        assertTrue(registryProxy.isKYCApproved(user1));

        // Warp time past expiry
        vm.warp(expiry + 1);

        // Should not be approved after expiry
        assertFalse(registryProxy.isKYCApproved(user1));

        vm.stopPrank();
    }

    function test_CannotReinitialize() public {
        vm.expectRevert();
        registryProxy.initialize(address(0x999));
    }

    function test_OnlyAdminCanSetKYC() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        registryProxy.setKYCStatus(
            user2,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );

        vm.stopPrank();
    }
}

