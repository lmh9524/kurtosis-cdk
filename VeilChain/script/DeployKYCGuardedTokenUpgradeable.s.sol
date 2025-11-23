// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/KYCGuardedTokenUpgradeable.sol";

contract DeployKYCGuardedTokenUpgradeable is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDR");
        address accessController = vm.envAddress("ACCESS_CONTROLLER_ADDR");
        string memory tokenName = vm.envString("TOKEN_NAME");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        
        vm.startBroadcast();
        
        // 1. 部署实现合约
        KYCGuardedTokenUpgradeable implementation = new KYCGuardedTokenUpgradeable();
        console.log("KYCGuardedTokenUpgradeable Implementation deployed:", address(implementation));
        
        // 2. 部署 ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);
        console.log("ProxyAdmin deployed:", address(proxyAdmin));
        
        // 3. 编码初始化数据
        bytes memory initData = abi.encodeCall(
            KYCGuardedTokenUpgradeable.initialize,
            (tokenName, tokenSymbol, admin, accessController)
        );
        
        // 4. 部署 Proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        
        vm.stopBroadcast();
        
        console.log("========================================");
        console.log("KYCGuardedTokenUpgradeable Implementation:", address(implementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("KYCGuardedTokenUpgradeable Proxy:", address(proxy));
        console.log("Admin:", admin);
        console.log("AccessController:", accessController);
        console.log("Token Name:", tokenName);
        console.log("Token Symbol:", tokenSymbol);
        console.log("========================================");
    }
}

