// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/ITransparentUpgradeableProxy.sol";
import "../src/KYCGuardedTokenUpgradeable.sol";
import "../src/AccessControllerUpgradeable.sol";
import "../src/LimitControllerUpgradeable.sol";
import "../src/KYCRegistry.sol";
import "../src/KYCDataTypes.sol";

contract KYCGuardedTokenUpgradeTest is Test {
    KYCGuardedTokenUpgradeable public token;
    AccessControllerUpgradeable public accessController;
    LimitControllerUpgradeable public limitController;
    KYCRegistry public kycRegistry;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    
    address public admin = address(0x1);
    address public minter = address(0x2);
    address public userA = address(0x100);
    address public userB = address(0x101);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // 1. 部署 KYCRegistry
        kycRegistry = new KYCRegistry(admin);
        
        // 2. 部署 AccessController
        AccessControllerUpgradeable accessImpl = new AccessControllerUpgradeable();
        ProxyAdmin accessProxyAdmin = new ProxyAdmin(admin);
        bytes memory accessInitData = abi.encodeCall(
            AccessControllerUpgradeable.initialize,
            (admin, address(kycRegistry))
        );
        TransparentUpgradeableProxy accessProxy = new TransparentUpgradeableProxy(
            address(accessImpl),
            address(accessProxyAdmin),
            accessInitData
        );
        accessController = AccessControllerUpgradeable(address(accessProxy));
        
        // 3. 部署 KYCGuardedToken
        KYCGuardedTokenUpgradeable implementation = new KYCGuardedTokenUpgradeable();
        proxyAdmin = new ProxyAdmin(admin);
        
        bytes memory initData = abi.encodeCall(
            KYCGuardedTokenUpgradeable.initialize,
            ("KYC Guarded Token", "KGT", admin, address(accessController))
        );
        
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        
        token = KYCGuardedTokenUpgradeable(address(proxy));
        
        vm.stopPrank();
    }
    
    function test_InitialSetup() public view {
        assertEq(token.name(), "KYC Guarded Token");
        assertEq(token.symbol(), "KGT");
        assertEq(token.decimals(), 18);
        assertEq(address(token.accessController()), address(accessController));
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(token.hasRole(token.MINTER_ROLE(), admin));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), admin));
    }
    
    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        token.initialize("Test", "TST", admin, address(accessController));
    }
    
    function test_Mint_Success() public {
        vm.startPrank(admin);
        
        // 设置 userA KYC 状态
        kycRegistry.setKYCStatus(
            userA,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        // Mint 代币
        token.mint(userA, 1000 ether);
        
        assertEq(token.balanceOf(userA), 1000 ether);
        
        vm.stopPrank();
    }
    
    function test_Mint_Fail_NotApproved() public {
        vm.startPrank(admin);
        
        // userA 未设置 KYC
        vm.expectRevert("KYCGuardedToken: mint not allowed");
        token.mint(userA, 1000 ether);
        
        vm.stopPrank();
    }
    
    function test_Transfer_Success() public {
        vm.startPrank(admin);
        
        // 设置 userA 和 userB 的 KYC 状态
        kycRegistry.setKYCStatus(
            userA,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        kycRegistry.setKYCStatus(
            userB,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        // Mint 代币给 userA
        token.mint(userA, 1000 ether);
        
        vm.stopPrank();
        
        // userA 转账给 userB
        vm.prank(userA);
        token.transfer(userB, 500 ether);
        
        assertEq(token.balanceOf(userA), 500 ether);
        assertEq(token.balanceOf(userB), 500 ether);
    }
    
    function test_Transfer_Fail_RecipientNotApproved() public {
        vm.startPrank(admin);
        
        // 只设置 userA 的 KYC
        kycRegistry.setKYCStatus(
            userA,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        token.mint(userA, 1000 ether);
        
        vm.stopPrank();
        
        // userB 未设置 KYC，转账应该失败
        vm.prank(userA);
        vm.expectRevert("KYCGuardedToken: transfer not allowed");
        token.transfer(userB, 500 ether);
    }
    
    function test_WithLimitController() public {
        vm.startPrank(admin);
        
        // 部署 LimitController
        LimitControllerUpgradeable limitImpl = new LimitControllerUpgradeable();
        ProxyAdmin limitProxyAdmin = new ProxyAdmin(admin);
        bytes memory limitInitData = abi.encodeCall(
            LimitControllerUpgradeable.initialize,
            (admin, address(kycRegistry))
        );
        TransparentUpgradeableProxy limitProxy = new TransparentUpgradeableProxy(
            address(limitImpl),
            address(limitProxyAdmin),
            limitInitData
        );
        limitController = LimitControllerUpgradeable(address(limitProxy));
        
        // 设置 token 为 CALLER
        limitController.grantRole(limitController.CALLER_ROLE(), address(token));
        
        // 配置限额
        limitController.setLevelLimits(1, 1000 ether, 10000 ether, true);
        
        // 将 LimitController 设置到 token
        token.setLimitController(address(limitController));
        
        // 设置 KYC
        kycRegistry.setKYCStatus(
            userA,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        kycRegistry.setKYCStatus(
            userB,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        token.mint(userA, 5000 ether);
        
        vm.stopPrank();
        
        // 测试在限额内的转账
        vm.prank(userA);
        token.transfer(userB, 500 ether);
        
        assertEq(token.balanceOf(userB), 500 ether);
        
        // 测试超过单笔限额的转账
        vm.prank(userA);
        vm.expectRevert("LimitController: single tx limit exceeded");
        token.transfer(userB, 1500 ether);
    }
    
    function test_Pause() public {
        vm.startPrank(admin);
        
        kycRegistry.setKYCStatus(
            userA,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        token.mint(userA, 1000 ether);
        
        // 暂停
        token.pause();
        
        // 尝试 mint 应该失败
        vm.expectRevert("KYCGuardedToken: paused");
        token.mint(userA, 100 ether);
        
        // 恢复
        token.unpause();
        
        // 现在应该可以 mint
        token.mint(userA, 100 ether);
        assertEq(token.balanceOf(userA), 1100 ether);
        
        vm.stopPrank();
    }
    
    function test_Upgrade() public {
        vm.startPrank(admin);
        
        // 设置 KYC 并 mint 代币
        kycRegistry.setKYCStatus(
            userA,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        token.mint(userA, 1000 ether);
        
        uint256 balanceBefore = token.balanceOf(userA);
        
        // 升级到新实现
        KYCGuardedTokenUpgradeable newImplementation = new KYCGuardedTokenUpgradeable();
        
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(newImplementation),
            ""
        );
        
        // 验证状态保持
        assertEq(token.name(), "KYC Guarded Token");
        assertEq(token.symbol(), "KGT");
        assertEq(token.balanceOf(userA), balanceBefore);
        assertEq(address(token.accessController()), address(accessController));
        
        // 验证功能仍然正常
        token.mint(userA, 500 ether);
        assertEq(token.balanceOf(userA), 1500 ether);
        
        vm.stopPrank();
    }
}

