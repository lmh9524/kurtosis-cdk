// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/proxy/TransparentUpgradeableProxy.sol";
import "../src/proxy/ProxyAdmin.sol";
import "../src/RWAProductUpgradeable.sol";

contract DeployRWAProductUpgradeable is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDR");
        address kycRegistryProxy = vm.envAddress("KYC_REGISTRY_PROXY_ADDR");
        address assetRegistryProxy = vm.envAddress("ASSET_REGISTRY_PROXY_ADDR");

        // Try to get key from env, fallback to cli provided
        uint256 deployerKey;
        try vm.envUint("ADMIN_KEY") returns (uint256 k) {
            deployerKey = k;
            vm.startBroadcast(deployerKey);
        } catch {
            vm.startBroadcast();
        }

        // 1. Deploy Implementation
        RWAProductUpgradeable implementation = new RWAProductUpgradeable();
        console.log("RWAProductUpgradeable Implementation deployed:", address(implementation));

        // 2. Deploy ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);
        console.log("ProxyAdmin deployed:", address(proxyAdmin));

        // 3. Init Data
        bytes memory initData = abi.encodeCall(
            RWAProductUpgradeable.initialize,
            (admin, kycRegistryProxy, assetRegistryProxy)
        );

        // 4. Deploy Proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        vm.stopBroadcast();

        console.log("========================================");
        console.log("RWAProduct Implementation:", address(implementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("RWAProduct Proxy:", address(proxy));
        console.log("Admin:", admin);
        console.log("KYC Registry:", kycRegistryProxy);
        console.log("Asset Registry:", assetRegistryProxy);
        console.log("========================================");
    }
}

