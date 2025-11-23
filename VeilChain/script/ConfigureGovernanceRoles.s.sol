// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import "../src/KYCRegistryUpgradeable.sol";
import "../src/AccessControllerUpgradeable.sol";
import "../src/LimitControllerUpgradeable.sol";
import "../src/KYCGuardedTokenUpgradeable.sol";
import "../src/AssetRegistryUpgradeable.sol";

/// @notice 按 Phase 1 规划配置治理层角色分工（Safe / Timelock / 运营地址）。
/// @dev 通过环境变量注入各类地址，方便在不同环境（本地、Kurtosis、测试网）重复使用。
contract ConfigureGovernanceRoles is Script {
    function run() external {
        // 治理与运营主体
        address safe = vm.envAddress("SAFE_ADDR");                 // Gnosis Safe 多签（DEFAULT_ADMIN_ROLE）
        address timelock = vm.envAddress("TIMELOCK_ADDR");         // TimelockController（ProxyAdmin owner + 限额等关键参数）
        address kycOperator = vm.envAddress("KYC_OPERATOR_ADDR");  // KYC_ADMIN_ROLE
        address minter = vm.envAddress("MINTER_ADDR");             // MINTER_ROLE
        address riskOfficer = vm.envAddress("RISK_OFFICER_ADDR");  // PAUSER_ROLE（可选：风控多签）
        address oldAdmin = vm.envAddress("OLD_ADMIN_ADDR");        // 早期部署使用的 EOA，需要撤权

        // 核心合约 Proxy 地址
        KYCRegistryUpgradeable kyc = KYCRegistryUpgradeable(vm.envAddress("KYC_REGISTRY_PROXY_ADDR"));
        AccessControllerUpgradeable access = AccessControllerUpgradeable(vm.envAddress("ACCESS_CONTROLLER_PROXY_ADDR"));
        LimitControllerUpgradeable limit = LimitControllerUpgradeable(vm.envAddress("LIMIT_CONTROLLER_PROXY_ADDR"));
        KYCGuardedTokenUpgradeable kgt = KYCGuardedTokenUpgradeable(vm.envAddress("KGT_PROXY_ADDR"));
        AssetRegistryUpgradeable asset = AssetRegistryUpgradeable(vm.envAddress("ASSET_REGISTRY_PROXY_ADDR"));

        vm.startBroadcast();

        // --------- KYCRegistry ---------
        // DEFAULT_ADMIN_ROLE -> Safe
        bytes32 dr = kyc.DEFAULT_ADMIN_ROLE();
        bytes32 kycAdmin = kyc.KYC_ADMIN_ROLE();
        bytes32 pauser = kyc.PAUSER_ROLE();

        kyc.grantRole(dr, safe);
        kyc.revokeRole(dr, oldAdmin);

        kyc.grantRole(kycAdmin, kycOperator);
        kyc.revokeRole(kycAdmin, oldAdmin);

        kyc.grantRole(pauser, riskOfficer);
        // 视需要从 oldAdmin 撤销 PAUSER_ROLE

        // --------- AccessController ---------
        dr = access.DEFAULT_ADMIN_ROLE();
        pauser = access.PAUSER_ROLE();

        access.grantRole(dr, safe);
        access.revokeRole(dr, oldAdmin);

        access.grantRole(pauser, riskOfficer);

        // --------- LimitController ---------
        dr = limit.DEFAULT_ADMIN_ROLE();
        bytes32 limitAdmin = limit.LIMIT_ADMIN_ROLE();
        pauser = limit.PAUSER_ROLE();
        bytes32 callerRole = limit.CALLER_ROLE();

        // DEFAULT_ADMIN_ROLE 仍由 Safe 持有，用于治理层变更
        limit.grantRole(dr, safe);
        limit.revokeRole(dr, oldAdmin);

        // LIMIT_ADMIN_ROLE -> Timelock（关键限额参数必须走治理流程）
        limit.grantRole(limitAdmin, timelock);
        limit.revokeRole(limitAdmin, oldAdmin);

        // PAUSER_ROLE -> 风控
        limit.grantRole(pauser, riskOfficer);

        // CALLER_ROLE 由业务合约持有（例如 KGT），此处不做变更
        // limit.grantRole(callerRole, <KGT address>) 由部署脚本完成
        callerRole; // silence unused-variable warning

        // --------- KYCGuardedToken (KGT) ---------
        dr = kgt.DEFAULT_ADMIN_ROLE();
        bytes32 minterRole = kgt.MINTER_ROLE();
        pauser = kgt.PAUSER_ROLE();

        kgt.grantRole(dr, safe);
        kgt.revokeRole(dr, oldAdmin);

        kgt.grantRole(minterRole, minter);
        kgt.revokeRole(minterRole, oldAdmin);

        kgt.grantRole(pauser, riskOfficer);

        // --------- AssetRegistry ---------
        dr = asset.DEFAULT_ADMIN_ROLE();
        bytes32 assetAdmin = asset.ASSET_ADMIN_ROLE();
        pauser = asset.PAUSER_ROLE();

        asset.grantRole(dr, safe);
        asset.revokeRole(dr, oldAdmin);

        asset.grantRole(assetAdmin, safe);
        asset.revokeRole(assetAdmin, oldAdmin);

        asset.grantRole(pauser, riskOfficer);

        vm.stopBroadcast();
    }
}


