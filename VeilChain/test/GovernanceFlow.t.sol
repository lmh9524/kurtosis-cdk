// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../src/KYCRegistryUpgradeable.sol";
import "../src/KYCRegistryV2.sol";

/// @title GovernanceFlowTest
/// @notice 演练「Safe -> Timelock -> ProxyAdmin -> Proxy 升级」完整治理链路。
/// @dev 这里将 Safe 简化为一个普通 EOA 地址，重点验证 Timelock + ProxyAdmin 组合行为。
contract GovernanceFlowTest is Test {
    address public safe;      // 模拟 Gnosis Safe 多签
    address public deployer;  // 部署者 / 临时 admin

    TimelockController public timelock;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    KYCRegistryUpgradeable public registryProxy;

    address public admin = address(0xA);
    address public user = address(0xB);

    function setUp() public {
        safe = address(0x111);
        deployer = address(this);

        // 1. 部署 TimelockController（proposer = safe, executor = anyone）
        address[] memory proposers = new address[](1);
        proposers[0] = safe;

        address[] memory executors = new address[](1);
        // 将 Safe 同时设为 proposer 和 executor，避免依赖 TimelockController 对 address(0) 的特殊处理实现
        executors[0] = safe;

        timelock = new TimelockController(
            2 days,
            proposers,
            executors,
            deployer // admin（测试中保留，不做进一步权限收紧）
        );

        // 2. 部署实现合约 + ProxyAdmin + Proxy
        KYCRegistryUpgradeable implementation = new KYCRegistryUpgradeable();
        proxyAdmin = new ProxyAdmin(deployer);

        bytes memory initData = abi.encodeCall(
            KYCRegistryUpgradeable.initialize,
            (admin)
        );

        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        registryProxy = KYCRegistryUpgradeable(address(proxy));

        // 3. 将 ProxyAdmin owner 迁移给 Timelock（真实环境中由迁移脚本或 Safe 触发）
        proxyAdmin.transferOwnership(address(timelock));
        assertEq(proxyAdmin.owner(), address(timelock));
    }

    /// @notice Safe 通过 Timelock 调度一次升级，从 V1 升级到 V2，并验证状态保持。
    function test_SafeTimelockUpgradeFlow() public {
        // 先在 V1 下写入一点状态
        vm.startPrank(admin);
        uint256 expiry = block.timestamp + 365 days;
        registryProxy.setKYCStatus(
            user,
            Status.Approved,
            2,
            expiry,
            bytes32("provider-001")
        );
        vm.stopPrank();

        assertTrue(registryProxy.isKYCApproved(user));
        assertEq(registryProxy.getRiskLevel(user), 2);

        // 1. 部署 V2 实现
        KYCRegistryV2 implementationV2 = new KYCRegistryV2();

        // 2. 由 Safe 通过 Timelock 调度一次 ProxyAdmin.upgrade 调用
        // 为了兼容不同版本的 ProxyAdmin，这里直接使用函数签名编码，而不是依赖 ProxyAdmin.upgrade.selector
        bytes memory data = abi.encodeWithSignature(
            "upgrade(address,address)",
            ITransparentUpgradeableProxy(address(proxy)),
            address(implementationV2)
        );

        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("kyc-upgrade-v2");

        // Safe 发起 schedule（作为 proposer）
        vm.prank(safe);
        timelock.schedule(
            address(proxyAdmin),
            0,
            data,
            predecessor,
            salt,
            timelock.getMinDelay()
        );

        // 时间前，由 Safe 直接尝试执行应失败（operation not ready）
        vm.prank(safe);
        vm.expectRevert();
        timelock.execute(
            address(proxyAdmin),
            0,
            data,
            predecessor,
            salt
        );

        // 快进时间到 minDelay 之后
        vm.warp(block.timestamp + timelock.getMinDelay());

        // 3. 到期后，由 Safe 作为 executor 触发 execute
        vm.prank(safe);
        timelock.execute(
            address(proxyAdmin),
            0,
            data,
            predecessor,
            salt
        );

        // 4. 升级后，proxy 指向 V2，实现应保持状态，新函数可用
        KYCRegistryV2 v2 = KYCRegistryV2(address(proxy));

        assertTrue(v2.isKYCApproved(user));
        assertEq(v2.getRiskLevel(user), 2);
        assertTrue(v2.hasMinimumLevel(user, 2));
        assertEq(keccak256(bytes(v2.version())), keccak256(bytes("v2.0.0")));
    }
}


