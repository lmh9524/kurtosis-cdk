// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/interfaces/ITransparentUpgradeableProxy.sol";
import "../src/LimitControllerUpgradeable.sol";

/// @notice Script to upgrade LimitControllerUpgradeable to a new implementation
contract UpgradeLimitController is Script {
    function run() external {
        address proxyAdminAddr = vm.envAddress("PROXY_ADMIN_ADDR");
        address proxyAddr = vm.envAddress("LIMIT_CONTROLLER_PROXY_ADDR");
        
        vm.startBroadcast();
        
        // 1. 部署新的实现合约
        LimitControllerUpgradeable newImplementation = new LimitControllerUpgradeable();
        console.log("New LimitControllerUpgradeable Implementation deployed:", address(newImplementation));
        
        // 2. 通过 ProxyAdmin 升级 Proxy
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddr);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddr),
            address(newImplementation),
            "" // 无需调用额外的初始化函数
        );
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("Upgraded LimitControllerUpgradeable");
        console.log("Proxy Address:", proxyAddr);
        console.log("New Implementation:", address(newImplementation));
        console.log("ProxyAdmin:", proxyAdminAddr);
        console.log("========================================");
    }
}

