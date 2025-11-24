// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KYCRegistryUpgradeableV2.sol";
import "../src/KYCDataTypes.sol";
import "../src/proxy/TransparentUpgradeableProxy.sol";
import "../src/proxy/ProxyAdmin.sol";

contract KYCRegistryV2Test is Test {
    KYCRegistryUpgradeableV2 public kycRegistry;
    ProxyAdmin public proxyAdmin;
    address admin = address(0x1);
    address user = address(0x2);
    address attacker = address(0x666);
    
    function setUp() public {
        vm.startPrank(admin);
        
        // 部署 ProxyAdmin
        proxyAdmin = new ProxyAdmin();
        
        // 部署实现合约
        KYCRegistryUpgradeableV2 impl = new KYCRegistryUpgradeableV2();
        
        // 部署代理
        bytes memory initData = abi.encodeWithSelector(
            KYCRegistryUpgradeableV2.initialize.selector,
            admin
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            initData
        );
        
        kycRegistry = KYCRegistryUpgradeableV2(address(proxy));
        vm.stopPrank();
    }
    
    // ========== 基础功能测试 ==========
    
    function testFreezeAccount() public {
        vm.startPrank(admin);
        
        // 设置 KYC（使用枚举类型）
        kycRegistry.setKYCStatus(user, Status.Approved, 2, block.timestamp + 365 days, bytes32(0));
        assertTrue(kycRegistry.isKYCApproved(user));
        
        // 冻结账户
        kycRegistry.freezeAccount(user);
        assertTrue(kycRegistry.isFrozen(user));
        assertFalse(kycRegistry.isKYCApproved(user)); // 冻结后 KYC 失效
        
        // 解冻
        kycRegistry.unfreezeAccount(user);
        assertFalse(kycRegistry.isFrozen(user));
        assertTrue(kycRegistry.isKYCApproved(user));
        
        vm.stopPrank();
    }
    
    function testComplianceCompatibility() public {
        vm.startPrank(admin);
        
        // 使用合规接口
        kycRegistry.setKYCStatus(user, Status.Approved, 2, block.timestamp + 365 days, bytes32(uint256(0x123)));
        
        // 验证接口
        assertTrue(kycRegistry.isVerified(user));
        assertEq(kycRegistry.getKYCLevel(user), 2);
        assertFalse(kycRegistry.isFrozen(user));
        
        vm.stopPrank();
    }
    
    // ========== 边界条件测试 ==========
    
    function testCannotFreezeZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert("Cannot freeze zero address");
        kycRegistry.freezeAccount(address(0));
        vm.stopPrank();
    }
    
    function testCannotFreezeAlreadyFrozen() public {
        vm.startPrank(admin);
        
        kycRegistry.setKYCStatus(user, Status.Approved, 1, block.timestamp + 365 days, bytes32(0));
        kycRegistry.freezeAccount(user);
        
        // 重复冻结应失败
        vm.expectRevert("Already frozen");
        kycRegistry.freezeAccount(user);
        
        vm.stopPrank();
    }
    
    function testCannotUnfreezeNotFrozen() public {
        vm.startPrank(admin);
        
        vm.expectRevert("Not frozen");
        kycRegistry.unfreezeAccount(user);
        
        vm.stopPrank();
    }
    
    function testFreezeWorksForPendingStatus() public {
        vm.startPrank(admin);
        
        // 即使是 Pending 状态也能冻结
        kycRegistry.setKYCStatus(user, Status.Pending, 1, block.timestamp + 365 days, bytes32(0));
        kycRegistry.freezeAccount(user);
        
        assertTrue(kycRegistry.isFrozen(user));
        assertFalse(kycRegistry.isKYCApproved(user)); // Pending 本来就不 approved
        
        vm.stopPrank();
    }
    
    // ========== 权限测试 ==========
    
    function testOnlyAdminCanFreeze() public {
        vm.startPrank(admin);
        kycRegistry.setKYCStatus(user, Status.Approved, 1, block.timestamp + 365 days, bytes32(0));
        vm.stopPrank();
        
        // 非 admin 调用应失败
        vm.startPrank(attacker);
        vm.expectRevert(); // AccessControl: missing role
        kycRegistry.freezeAccount(user);
        vm.stopPrank();
    }
    
    function testOnlyAdminCanUnfreeze() public {
        vm.startPrank(admin);
        kycRegistry.setKYCStatus(user, Status.Approved, 1, block.timestamp + 365 days, bytes32(0));
        kycRegistry.freezeAccount(user);
        vm.stopPrank();
        
        // 非 admin 调用应失败
        vm.startPrank(attacker);
        vm.expectRevert(); // AccessControl: missing role
        kycRegistry.unfreezeAccount(user);
        vm.stopPrank();
    }
    
    // ========== 升级测试 ==========
    
    function testUpgradePreservesData() public {
        vm.startPrank(admin);
        
        // 在 V2 设置数据
        kycRegistry.setKYCStatus(user, Status.Approved, 3, block.timestamp + 365 days, bytes32(uint256(0xabc)));
        
        // 记录升级前的数据
        bool approvedBefore = kycRegistry.isKYCApproved(user);
        uint8 levelBefore = kycRegistry.getRiskLevel(user);
        
        // 部署新实现（模拟升级到 V3）
        KYCRegistryUpgradeableV2 newImpl = new KYCRegistryUpgradeableV2();
        proxyAdmin.upgrade(address(kycRegistry), address(newImpl));
        
        // 验证数据未丢失
        assertTrue(kycRegistry.isKYCApproved(user) == approvedBefore);
        assertEq(kycRegistry.getRiskLevel(user), levelBefore);
        
        vm.stopPrank();
    }
    
    // ========== 批量操作测试 ==========
    
    function testBatchFreeze() public {
        address[] memory users = new address[](3);
        users[0] = address(0x10);
        users[1] = address(0x20);
        users[2] = address(0x30);
        
        vm.startPrank(admin);
        
        // 先给所有用户设置 KYC
        for (uint256 i = 0; i < users.length; i++) {
            kycRegistry.setKYCStatus(users[i], Status.Approved, 1, block.timestamp + 365 days, bytes32(0));
        }
        
        // 批量冻结
        kycRegistry.batchFreezeAccounts(users);
        
        // 验证
        for (uint256 i = 0; i < users.length; i++) {
            assertTrue(kycRegistry.isFrozen(users[i]));
            assertFalse(kycRegistry.isKYCApproved(users[i]));
        }
        
        vm.stopPrank();
    }
    
    // ========== 集成测试 ==========
    
    function testFreezeBlocksApprovalEvenWithValidKYC() public {
        vm.startPrank(admin);
        
        // 设置有效的 KYC
        kycRegistry.setKYCStatus(user, Status.Approved, 3, block.timestamp + 365 days, bytes32(uint256(0x123)));
        
        // 确认 KYC 通过
        assertTrue(kycRegistry.isKYCApproved(user));
        assertTrue(kycRegistry.isVerified(user));
        assertEq(kycRegistry.getKYCLevel(user), 3);
        
        // 冻结账户
        kycRegistry.freezeAccount(user);
        
        // KYC 信息仍然存在，但 approved 状态为 false
        assertFalse(kycRegistry.isKYCApproved(user));
        assertFalse(kycRegistry.isVerified(user));
        assertEq(kycRegistry.getKYCLevel(user), 3); // 等级信息未丢失
        
        // 解冻后恢复
        kycRegistry.unfreezeAccount(user);
        assertTrue(kycRegistry.isKYCApproved(user));
        assertTrue(kycRegistry.isVerified(user));
        
        vm.stopPrank();
    }
    
    function testBatchFreezeSkipsZeroAddresses() public {
        address[] memory users = new address[](3);
        users[0] = address(0x10);
        users[1] = address(0); // 零地址
        users[2] = address(0x30);
        
        vm.startPrank(admin);
        
        // 设置 KYC
        kycRegistry.setKYCStatus(users[0], Status.Approved, 1, block.timestamp + 365 days, bytes32(0));
        kycRegistry.setKYCStatus(users[2], Status.Approved, 1, block.timestamp + 365 days, bytes32(0));
        
        // 批量冻结（应跳过零地址）
        kycRegistry.batchFreezeAccounts(users);
        
        // 验证
        assertTrue(kycRegistry.isFrozen(users[0]));
        assertFalse(kycRegistry.isFrozen(users[1])); // 零地址未冻结
        assertTrue(kycRegistry.isFrozen(users[2]));
        
        vm.stopPrank();
    }
}

