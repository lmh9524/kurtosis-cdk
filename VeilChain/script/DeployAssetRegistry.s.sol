// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/AssetRegistry.sol";

/// @notice Deploys AssetRegistry using admin from env.
/// @dev Expected env vars:
///   - PRIVATE_KEY: deployer/admin private key (PoC admin)
///   - ADMIN_ADDR: admin address for AssetRegistry roles
contract DeployAssetRegistry is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDR");

        vm.startBroadcast(deployerPrivateKey);
        AssetRegistry registry = new AssetRegistry(admin);
        vm.stopBroadcast();

        console.log("========================================");
        console.log("AssetRegistry deployed at:", address(registry));
        console.log("Admin:", admin);
        console.log("========================================");
    }
}

