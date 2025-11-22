// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/LimitController.sol";

contract DeployLimitController is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDR");
        address kycRegistry = vm.envAddress("KYC_REGISTRY_ADDR");

        vm.startBroadcast();

        LimitController limitController = new LimitController(admin, kycRegistry);

        vm.stopBroadcast();

        console.log("========================================");
        console.log("LimitController deployed at:", address(limitController));
        console.log("Admin:", admin);
        console.log("KYCRegistry:", kycRegistry);
        console.log("========================================");
    }
}

