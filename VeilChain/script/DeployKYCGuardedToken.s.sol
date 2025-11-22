// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/KYCGuardedToken.sol";

/// @notice Deploys a KYCGuardedToken wired to an existing AccessController.
contract DeployKYCGuardedToken is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDR");
        address accessController = vm.envAddress("ACCESS_CONTROLLER_ADDR");

        vm.startBroadcast(deployerPrivateKey);
        KYCGuardedToken token = new KYCGuardedToken(
            "KYC Guarded Token",
            "KGT",
            admin,
            accessController
        );
        vm.stopBroadcast();

        console.log("========================================");
        console.log("KYCGuardedToken deployed at:", address(token));
        console.log("Admin:", admin);
        console.log("AccessController:", accessController);
        console.log("========================================");
    }
}

