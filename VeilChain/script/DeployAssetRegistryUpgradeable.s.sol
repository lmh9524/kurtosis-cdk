// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/AssetRegistryUpgradeable.sol";

contract DeployAssetRegistryUpgradeable is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDR");
        
        vm.startBroadcast();
        
        // 1. 部署实现合约
        AssetRegistryUpgradeable implementation = new AssetRegistryUpgradeable();
        console.log("AssetRegistryUpgradeable Implementation deployed:", address(implementation));
        
        // 2. 部署 ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);
        console.log("ProxyAdmin deployed:", address(proxyAdmin));
        
        // 3. 编码初始化数据
        bytes memory initData = abi.encodeCall(
            AssetRegistryUpgradeable.initialize,
            (admin)
        );
        
        // 4. 部署 Proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("AssetRegistryUpgradeable Implementation:", address(implementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("AssetRegistryUpgradeable Proxy:", address(proxy));
        console.log("Admin:", admin);
        console.log("========================================");
    }
}

