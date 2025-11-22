// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KYCRegistry.sol";

/// @title DeployKYCRegistry
/// @notice Simple deployment script for the KYCRegistry contract.
contract DeployKYCRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDR");

        vm.startBroadcast(deployerPrivateKey);
        KYCRegistry registry = new KYCRegistry(admin);
        vm.stopBroadcast();

        console.log("========================================");
        console.log("KYCRegistry deployed at:", address(registry));
        console.log("Admin:", admin);
        console.log("========================================");
    }
}

