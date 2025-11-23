// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/interfaces/IAccessController.sol";
import "../src/AccessControllerUpgradeable.sol";
import "../src/KYCRegistry.sol";
import "../src/KYCDataTypes.sol";

contract AccessControllerUpgradeTest is Test {
    AccessControllerUpgradeable public accessController;
    KYCRegistry public kycRegistry;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;

    // 为了配合 vm.expectEmit，在测试合约中重新声明事件签名
    event KYCRegistryUpdated(
        address indexed oldRegistry,
        address indexed newRegistry,
        address indexed operator
    );
    
    address public admin = address(0x1);
    address public user = address(0x2);
    address public pauser = address(0x3);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // 1. 部署 KYCRegistry
        kycRegistry = new KYCRegistry(admin);
        
        // 2. 部署 AccessControllerUpgradeable 实现合约
        AccessControllerUpgradeable implementation = new AccessControllerUpgradeable();
        
        // 3. 部署 ProxyAdmin
        proxyAdmin = new ProxyAdmin(admin);
        
        // 4. 编码初始化数据并部署 Proxy
        bytes memory initData = abi.encodeCall(
            AccessControllerUpgradeable.initialize,
            (admin, address(kycRegistry))
        );
        
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        
        // 5. 将 Proxy 包装为 AccessControllerUpgradeable 接口
        accessController = AccessControllerUpgradeable(address(proxy));
        
        vm.stopPrank();
    }
    
    function test_InitialSetup() public view {
        assertEq(address(accessController.kycRegistry()), address(kycRegistry));
        assertTrue(accessController.hasRole(accessController.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(accessController.hasRole(accessController.PAUSER_ROLE(), admin));
    }
    
    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        accessController.initialize(admin, address(kycRegistry));
    }
    
    function test_CanTransfer_BothApproved() public {
        vm.startPrank(admin);
        
        address from = address(0x100);
        address to = address(0x101);
        
        // 设置 KYC 状态
        kycRegistry.setKYCStatus(
            from,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        kycRegistry.setKYCStatus(
            to,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        vm.stopPrank();
        
        assertTrue(accessController.canTransfer(from, to));
    }
    
    function test_CanTransfer_FromNotApproved() public {
        vm.startPrank(admin);
        
        address from = address(0x100);
        address to = address(0x101);
        
        // 只为 to 设置 KYC
        kycRegistry.setKYCStatus(
            to,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        vm.stopPrank();
        
        assertFalse(accessController.canTransfer(from, to));
    }
    
    function test_CanMint() public {
        vm.startPrank(admin);
        
        address to = address(0x100);
        
        kycRegistry.setKYCStatus(
            to,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        vm.stopPrank();
        
        assertTrue(accessController.canMint(to));
    }
    
    function test_Pause() public {
        vm.startPrank(admin);
        
        accessController.pause();
        
        assertTrue(accessController.paused());
        
        // 设置 KYC 后，暂停时 canTransfer 应该返回 false
        address from = address(0x100);
        address to = address(0x101);
        
        kycRegistry.setKYCStatus(
            from,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        kycRegistry.setKYCStatus(
            to,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        assertFalse(accessController.canTransfer(from, to));
        
        // 恢复后应该可以转账
        accessController.unpause();
        assertTrue(accessController.canTransfer(from, to));
        
        vm.stopPrank();
    }
    
    function test_SetKYCRegistry() public {
        vm.startPrank(admin);
        
        KYCRegistry newRegistry = new KYCRegistry(admin);
        
        vm.expectEmit(true, true, true, true);
        emit KYCRegistryUpdated(
            address(kycRegistry),
            address(newRegistry),
            admin
        );
        
        accessController.setKYCRegistry(address(newRegistry));
        
        assertEq(address(accessController.kycRegistry()), address(newRegistry));
        
        vm.stopPrank();
    }
    
    function test_Upgrade() public {
        vm.startPrank(admin);
        
        // 设置一些状态
        address from = address(0x100);
        address to = address(0x101);
        
        kycRegistry.setKYCStatus(
            from,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        kycRegistry.setKYCStatus(
            to,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        assertTrue(accessController.canTransfer(from, to));
        
        // 升级到新实现
        AccessControllerUpgradeable newImplementation = new AccessControllerUpgradeable();
        
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(newImplementation),
            ""
        );
        
        // 验证状态保持
        assertEq(address(accessController.kycRegistry()), address(kycRegistry));
        assertTrue(accessController.canTransfer(from, to));
        
        vm.stopPrank();
    }
}

