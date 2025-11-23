// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/LimitControllerUpgradeable.sol";
import "../src/KYCRegistry.sol";
import "../src/KYCDataTypes.sol";

contract LimitControllerUpgradeTest is Test {
    LimitControllerUpgradeable public limitController;
    KYCRegistry public kycRegistry;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    
    address public admin = address(0x1);
    address public caller = address(0x2);
    address public user = address(0x100);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // 1. 部署 KYCRegistry
        kycRegistry = new KYCRegistry(admin);
        
        // 2. 部署 LimitControllerUpgradeable 实现合约
        LimitControllerUpgradeable implementation = new LimitControllerUpgradeable();
        
        // 3. 部署 ProxyAdmin
        proxyAdmin = new ProxyAdmin(admin);
        
        // 4. 编码初始化数据并部署 Proxy
        bytes memory initData = abi.encodeCall(
            LimitControllerUpgradeable.initialize,
            (admin, address(kycRegistry))
        );
        
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        
        // 5. 将 Proxy 包装为 LimitControllerUpgradeable 接口
        limitController = LimitControllerUpgradeable(address(proxy));
        
        // 6. 授予 caller CALLER_ROLE
        limitController.grantRole(limitController.CALLER_ROLE(), caller);
        
        vm.stopPrank();
    }
    
    function test_InitialSetup() public view {
        assertEq(address(limitController.kycRegistry()), address(kycRegistry));
        assertTrue(limitController.hasRole(limitController.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(limitController.hasRole(limitController.LIMIT_ADMIN_ROLE(), admin));
        assertTrue(limitController.hasRole(limitController.PAUSER_ROLE(), admin));
        assertTrue(limitController.hasRole(limitController.CALLER_ROLE(), caller));
    }
    
    function test_CannotInitializeTwice() public {
        vm.expectRevert();
        limitController.initialize(admin, address(kycRegistry));
    }
    
    function test_SetLevelLimits() public {
        vm.startPrank(admin);
        
        limitController.setLevelLimits(1, 1000 ether, 10000 ether, true);
        
        (uint256 maxSingle, uint256 daily, bool enabled) = limitController.levelLimits(1);
        
        assertEq(maxSingle, 1000 ether);
        assertEq(daily, 10000 ether);
        assertTrue(enabled);
        
        vm.stopPrank();
    }
    
    function test_CheckAndUpdateOutflow_WithinLimit() public {
        vm.startPrank(admin);
        
        // 设置用户 KYC 等级为 1
        kycRegistry.setKYCStatus(
            user,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        // 设置等级 1 的限额
        limitController.setLevelLimits(1, 1000 ether, 10000 ether, true);
        
        vm.stopPrank();
        
        // caller 调用 checkAndUpdateOutflow
        vm.prank(caller);
        limitController.checkAndUpdateOutflow(user, 500 ether);
        
        // 验证剩余额度
        uint256 remaining = limitController.getRemainingDailyOutflow(user);
        assertEq(remaining, 9500 ether);
    }
    
    function test_CheckAndUpdateOutflow_ExceedsSingleLimit() public {
        vm.startPrank(admin);
        
        kycRegistry.setKYCStatus(
            user,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        limitController.setLevelLimits(1, 1000 ether, 10000 ether, true);
        
        vm.stopPrank();
        
        vm.prank(caller);
        vm.expectRevert("LimitController: single tx limit exceeded");
        limitController.checkAndUpdateOutflow(user, 1500 ether);
    }
    
    function test_CheckAndUpdateOutflow_ExceedsDailyLimit() public {
        vm.startPrank(admin);
        
        kycRegistry.setKYCStatus(
            user,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        limitController.setLevelLimits(1, 1000 ether, 2000 ether, true);
        
        vm.stopPrank();
        
        vm.startPrank(caller);
        
        // 第一笔：1000 ether
        limitController.checkAndUpdateOutflow(user, 1000 ether);
        
        // 第二笔：500 ether，总计 1500 ether，还在限额内
        limitController.checkAndUpdateOutflow(user, 500 ether);
        
        // 第三笔：600 ether，总计 2100 ether，超过日限额 2000 ether
        vm.expectRevert("LimitController: daily limit exceeded");
        limitController.checkAndUpdateOutflow(user, 600 ether);
        
        vm.stopPrank();
    }
    
    function test_DailyLimitReset() public {
        vm.startPrank(admin);
        
        kycRegistry.setKYCStatus(
            user,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        limitController.setLevelLimits(1, 1000 ether, 2000 ether, true);
        
        vm.stopPrank();
        
        vm.startPrank(caller);
        
        // 第一天：使用 1500 ether
        limitController.checkAndUpdateOutflow(user, 1000 ether);
        limitController.checkAndUpdateOutflow(user, 500 ether);
        
        assertEq(limitController.getRemainingDailyOutflow(user), 500 ether);
        
        // 跳到第二天
        vm.warp(block.timestamp + 1 days);
        
        // 剩余额度应该重置为 2000 ether
        assertEq(limitController.getRemainingDailyOutflow(user), 2000 ether);
        
        // 可以再次使用完整额度
        limitController.checkAndUpdateOutflow(user, 1000 ether);
        assertEq(limitController.getRemainingDailyOutflow(user), 1000 ether);
        
        vm.stopPrank();
    }
    
    function test_Upgrade() public {
        vm.startPrank(admin);
        
        // 设置限额和用户状态
        kycRegistry.setKYCStatus(
            user,
            Status.Approved,
            1,
            block.timestamp + 365 days,
            bytes32("provider-001")
        );
        
        limitController.setLevelLimits(1, 1000 ether, 10000 ether, true);
        
        vm.stopPrank();
        
        vm.prank(caller);
        limitController.checkAndUpdateOutflow(user, 500 ether);
        
        uint256 remainingBefore = limitController.getRemainingDailyOutflow(user);
        
        // 升级到新实现（通过 ProxyAdmin）
        LimitControllerUpgradeable newImplementation = new LimitControllerUpgradeable();
        vm.prank(admin);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(newImplementation),
            ""
        );

        // 升级后，日剩余额度应保持不变
        uint256 remainingAfter = limitController.getRemainingDailyOutflow(user);
        assertEq(remainingAfter, remainingBefore);
    }
}

