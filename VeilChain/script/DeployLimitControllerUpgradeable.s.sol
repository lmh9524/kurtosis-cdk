// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/LimitControllerUpgradeable.sol";

contract DeployLimitControllerUpgradeable is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDR");
        address kycRegistry = vm.envAddress("KYC_REGISTRY_ADDR");
        
        vm.startBroadcast();
        
        // 1. 部署实现合约
        LimitControllerUpgradeable implementation = new LimitControllerUpgradeable();
        console.log("LimitControllerUpgradeable Implementation deployed:", address(implementation));
        
        // 2. 部署 ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);
        console.log("ProxyAdmin deployed:", address(proxyAdmin));
        
        // 3. 编码初始化数据
        bytes memory initData = abi.encodeCall(
            LimitControllerUpgradeable.initialize,
            (admin, kycRegistry)
        );
        
        // 4. 部署 Proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("LimitControllerUpgradeable Implementation:", address(implementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("LimitControllerUpgradeable Proxy:", address(proxy));
        console.log("Admin:", admin);
        console.log("KYCRegistry:", kycRegistry);
        console.log("========================================");
    }
}

