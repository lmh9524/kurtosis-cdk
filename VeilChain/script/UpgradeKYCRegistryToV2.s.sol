// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../src/interfaces/ITransparentUpgradeableProxy.sol";
import "../src/KYCRegistryV2.sol";

/// @title UpgradeKYCRegistryToV2
/// @notice Upgrades KYCRegistry proxy to V2 implementation.
contract UpgradeKYCRegistryToV2 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN_ADDRESS");
        address proxyAddress = vm.envAddress("KYC_REGISTRY_PROXY_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy new V2 implementation
        KYCRegistryV2 newImplementation = new KYCRegistryV2();
        console.log("KYCRegistryV2 Implementation deployed at:", address(newImplementation));

        // 2. Get ProxyAdmin instance
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);

        // 3. Upgrade the proxy to new implementation
        // Note: Must be called by ProxyAdmin owner
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddress),
            address(newImplementation),
            "" // No initialization call needed for V2
        );

        console.log("Proxy upgraded to V2 implementation");

        vm.stopBroadcast();

        console.log("\n=== Upgrade Summary ===");
        console.log("Proxy Address:", proxyAddress);
        console.log("New Implementation (V2):", address(newImplementation));
        console.log("\nVerification Steps:");
        console.log("1. Call version() on proxy - should return 'v2.0.0'");
        console.log("2. Verify old state data is preserved");
        console.log("3. Test new hasMinimumLevel() function");
    }
}

