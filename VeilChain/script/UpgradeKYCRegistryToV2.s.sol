// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/proxy/ProxyAdmin.sol";
import "../src/proxy/TransparentUpgradeableProxy.sol";
import "../src/KYCRegistryUpgradeableV2.sol";

/// @title UpgradeKYCRegistryToV2
/// @notice Upgrades KYCRegistry proxy to V2 implementation (with freeze functionality).
contract UpgradeKYCRegistryToV2 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("ADMIN_KEY");
        address proxyAdminAddress = vm.envAddress("KYC_REGISTRY_PROXY_ADMIN_ADDR");
        address proxyAddress = vm.envAddress("KYC_REGISTRY_PROXY_ADDR");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new V2 implementation
        KYCRegistryUpgradeableV2 newImplementation = new KYCRegistryUpgradeableV2();
        console.log("KYCRegistryUpgradeableV2 Implementation deployed at:", address(newImplementation));

        // 2. Get ProxyAdmin instance
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // 3. Upgrade the proxy to new implementation
        // Note: Must be called by ProxyAdmin owner (which is ADMIN_KEY in our current environment)
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddress),
            address(newImplementation),
            "" // No initialization call needed for V2
        );

        console.log("Proxy upgraded to KYCRegistryUpgradeableV2");

        vm.stopBroadcast();

        console.log("\n=== Upgrade Summary ===");
        console.log("Proxy Address:", proxyAddress);
        console.log("New Implementation (V2):", address(newImplementation));
        console.log("\nVerification Steps:");
        console.log("1. Verify isFrozen(user) function exists");
        console.log("2. Verify freezeAccount(user) works");
    }
}

