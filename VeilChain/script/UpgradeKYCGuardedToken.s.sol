// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ITransparentUpgradeableProxy.sol";
import "../src/KYCGuardedTokenUpgradeable.sol";

/// @notice Script to upgrade KYCGuardedTokenUpgradeable to a new implementation
contract UpgradeKYCGuardedToken is Script {
    function run() external {
        address proxyAdminAddr = vm.envAddress("PROXY_ADMIN_ADDR");
        address proxyAddr = vm.envAddress("KYC_GUARDED_TOKEN_PROXY_ADDR");
        
        vm.startBroadcast();
        
        // 1. 部署新的实现合约
        KYCGuardedTokenUpgradeable newImplementation = new KYCGuardedTokenUpgradeable();
        console.log("New KYCGuardedTokenUpgradeable Implementation deployed:", address(newImplementation));
        
        // 2. 通过 ProxyAdmin 升级 Proxy
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddr);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddr),
            address(newImplementation),
            "" // 无需调用额外的初始化函数
        );
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("Upgraded KYCGuardedTokenUpgradeable");
        console.log("Proxy Address:", proxyAddr);
        console.log("New Implementation:", address(newImplementation));
        console.log("ProxyAdmin:", proxyAdminAddr);
        console.log("========================================");
    }
}

