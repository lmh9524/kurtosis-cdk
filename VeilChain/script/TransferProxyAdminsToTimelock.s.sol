// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @notice 将一组 ProxyAdmin 的 owner 转移到 TimelockController。
/// @dev 具体 ProxyAdmin 地址通过环境变量注入，便于在不同环境复用。
contract TransferProxyAdminsToTimelock is Script {
    function run() external {
        address timelock = vm.envAddress("TIMELOCK_ADDR");

        // 可根据需要填充的 ProxyAdmin 地址列表
        address[] memory admins = new address[](5);
        admins[0] = vm.envAddress("KYC_REGISTRY_PROXY_ADMIN_ADDR");
        admins[1] = vm.envAddress("ACCESS_CONTROLLER_PROXY_ADMIN_ADDR");
        admins[2] = vm.envAddress("LIMIT_CONTROLLER_PROXY_ADMIN_ADDR");
        admins[3] = vm.envAddress("KGT_PROXY_ADMIN_ADDR");
        admins[4] = vm.envAddress("ASSET_REGISTRY_PROXY_ADMIN_ADDR");

        vm.startBroadcast();

        for (uint256 i = 0; i < admins.length; i++) {
            ProxyAdmin pa = ProxyAdmin(admins[i]);
            address oldOwner = pa.owner();
            if (oldOwner != timelock) {
                pa.transferOwnership(timelock);
                console.log("Transferred ProxyAdmin ownership", admins[i]);
                console.log("  Old owner:", oldOwner);
                console.log("  New owner:", timelock);
            } else {
                console.log("ProxyAdmin already owned by Timelock:", admins[i]);
            }
        }

        vm.stopBroadcast();
    }
}


