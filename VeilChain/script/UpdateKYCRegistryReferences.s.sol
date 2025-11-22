// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AccessController.sol";
import "../src/LimitController.sol";

/// @title UpdateKYCRegistryReferences
/// @notice Updates AccessController and LimitController to point to new KYCRegistry proxy.
contract UpdateKYCRegistryReferences is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address newKYCRegistryProxy = vm.envAddress("KYC_REGISTRY_PROXY_ADDRESS");
        address accessControllerAddress = vm.envAddress("ACCESS_CONTROLLER_ADDRESS");
        address limitControllerAddress = vm.envAddress("LIMIT_CONTROLLER_ADDRESS");

        require(newKYCRegistryProxy != address(0), "KYC_REGISTRY_PROXY_ADDRESS not set");
        require(accessControllerAddress != address(0), "ACCESS_CONTROLLER_ADDRESS not set");
        require(limitControllerAddress != address(0), "LIMIT_CONTROLLER_ADDRESS not set");

        vm.startBroadcast(deployerPrivateKey);

        // Update AccessController
        AccessController accessController = AccessController(accessControllerAddress);
        console.log("Updating AccessController at:", accessControllerAddress);
        console.log("Old KYCRegistry:", address(accessController.kycRegistry()));
        
        accessController.setKYCRegistry(newKYCRegistryProxy);
        console.log("New KYCRegistry:", address(accessController.kycRegistry()));

        // Update LimitController
        LimitController limitController = LimitController(limitControllerAddress);
        console.log("\nUpdating LimitController at:", limitControllerAddress);
        console.log("Old KYCRegistry:", address(limitController.kycRegistry()));
        
        limitController.setKYCRegistry(newKYCRegistryProxy);
        console.log("New KYCRegistry:", address(limitController.kycRegistry()));

        vm.stopBroadcast();

        console.log("\n=== Update Complete ===");
        console.log("AccessController now points to:", newKYCRegistryProxy);
        console.log("LimitController now points to:", newKYCRegistryProxy);
        console.log("\nVerification:");
        console.log("1. Test AccessController.canTransfer() with KYC-approved users");
        console.log("2. Test LimitController quota checks");
        console.log("3. Verify KYCGuardedToken transfers work correctly");
    }
}

