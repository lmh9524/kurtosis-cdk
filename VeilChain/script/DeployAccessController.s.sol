// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AccessController.sol";

/// @notice Deploys AccessController pointing to an existing KYCRegistry.
/// @dev Uses the same admin as KYCRegistry for the PoC.
contract DeployAccessController is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDR");
        address kycRegistry = vm.envAddress("KYC_REGISTRY_ADDR");

        vm.startBroadcast(deployerPrivateKey);
        AccessController controller = new AccessController(admin, kycRegistry);
        vm.stopBroadcast();

        console.log("========================================");
        console.log("AccessController deployed at:", address(controller));
        console.log("Admin:", admin);
        console.log("KYCRegistry:", kycRegistry);
        console.log("========================================");
    }
}

