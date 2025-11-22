// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../src/KYCRegistryUpgradeable.sol";

/// @title DeployKYCRegistryUpgradeable
/// @notice Deploys KYCRegistry using TransparentUpgradeableProxy pattern.
contract DeployKYCRegistryUpgradeable is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the implementation contract
        KYCRegistryUpgradeable implementation = new KYCRegistryUpgradeable();
        console.log("KYCRegistry Implementation deployed at:", address(implementation));

        // 2. Deploy ProxyAdmin (will be owned by deployer initially, transfer later to Gnosis Safe)
        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // 3. Encode initialize call
        bytes memory initData = abi.encodeWithSelector(
            KYCRegistryUpgradeable.initialize.selector,
            admin
        );

        // 4. Deploy TransparentUpgradeableProxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );
        console.log("KYCRegistry Proxy deployed at:", address(proxy));

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Implementation:", address(implementation));
        console.log("ProxyAdmin:", address(proxyAdmin));
        console.log("Proxy (use this address):", address(proxy));
        console.log("Admin (initialized with):", admin);
        console.log("\nNext Steps:");
        console.log("1. Update AccessController: setKYCRegistry(%s)", address(proxy));
        console.log("2. Update LimitController: setKYCRegistry(%s)", address(proxy));
        console.log("3. Transfer ProxyAdmin ownership to Gnosis Safe when ready");
    }
}

