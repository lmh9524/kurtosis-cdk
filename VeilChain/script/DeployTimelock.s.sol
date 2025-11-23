// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/// @notice 部署 TimelockController，用于作为 ProxyAdmin owner 以及高危配置的执行入口。
/// @dev 设计与 Phase 1 实施计划中的示例保持一致：
///      - proposers: Gnosis Safe 多签
///      - executors: 任意地址（address(0)）
///      - admin: 部署者（部署后应放弃 admin 权限）
contract DeployTimelock is Script {
    function run() external {
        // 多签地址（人类治理入口），由外部通过环境变量注入
        address safe = vm.envAddress("SAFE_ADDR");

        // 延迟时间（秒），例如 48 小时；测试环境可以设为较小值方便演练
        uint256 minDelay = vm.envUint("TIMELOCK_MIN_DELAY");

        address[] memory proposers = new address[](1);
        proposers[0] = safe;

        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone

        vm.startBroadcast();

        TimelockController timelock = new TimelockController(
            minDelay,
            proposers,
            executors,
            msg.sender // admin：部署后应通过脚本或手工交易放弃该 admin 权限
        );

        vm.stopBroadcast();

        console.log("========================================");
        console.log("TimelockController:", address(timelock));
        console.log("Safe (proposer):", safe);
        console.log("Min delay (seconds):", minDelay);
        console.log("Deployer (initial admin):", msg.sender);
        console.log("========================================");
    }
}


