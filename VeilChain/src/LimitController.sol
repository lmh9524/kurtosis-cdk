// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IKYCRegistry.sol";
import "./interfaces/ILimitController.sol";

/// @title LimitController
/// @notice Simple per-level single-tx & daily outflow limits based on KYC level.
/// @dev This is a PoC component intended for RWA experiments, not production.
contract LimitController is AccessControl, Pausable, ILimitController {
    bytes32 public constant LIMIT_ADMIN_ROLE = keccak256("LIMIT_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Callers (e.g. tokens) that are allowed to consume quota.
    bytes32 public constant CALLER_ROLE = keccak256("CALLER_ROLE");

    struct LimitConfig {
        uint256 maxSingle; // 0 means no per-tx cap
        uint256 daily;     // 0 means no daily cap
        bool enabled;      // false means no limits for this level
    }

    struct DailyUsage {
        uint64 day;   // day index = block.timestamp / 1 days
        uint256 used; // amount already used today
    }

    IKYCRegistry public kycRegistry;

    /// @notice Per KYC level limit configuration.
    mapping(uint8 => LimitConfig) public levelLimits;

    /// @notice Per-user daily usage tracking.
    mapping(address => DailyUsage) public outflowUsage;

    event KYCRegistryUpdated(address indexed oldRegistry, address indexed newRegistry, address indexed operator);
    event LevelLimitsUpdated(uint8 indexed level, uint256 maxSingle, uint256 daily, bool enabled, address indexed operator);

    constructor(address admin_, address kycRegistry_) {
        require(admin_ != address(0), "LimitController: admin is zero");
        require(kycRegistry_ != address(0), "LimitController: registry is zero");

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(LIMIT_ADMIN_ROLE, admin_);
        _grantRole(PAUSER_ROLE, admin_);

        kycRegistry = IKYCRegistry(kycRegistry_);
        emit KYCRegistryUpdated(address(0), kycRegistry_, admin_);
    }

    /// @notice Update the KYC registry reference (e.g. after an upgrade).
    function setKYCRegistry(address newRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRegistry != address(0), "LimitController: registry is zero");

        address old = address(kycRegistry);
        kycRegistry = IKYCRegistry(newRegistry);
        emit KYCRegistryUpdated(old, newRegistry, _msgSender());
    }

    /// @notice Configure limits for a given KYC level.
    /// @param level      KYC level from the registry.
    /// @param maxSingle_ Max amount per single operation (0 = no cap).
    /// @param daily_     Max cumulative amount per day (0 = no cap).
    /// @param enabled_   Whether limits are enforced for this level.
    function setLevelLimits(
        uint8 level,
        uint256 maxSingle_,
        uint256 daily_,
        bool enabled_
    ) external onlyRole(LIMIT_ADMIN_ROLE) {
        levelLimits[level] = LimitConfig({
            maxSingle: maxSingle_,
            daily: daily_,
            enabled: enabled_
        });

        emit LevelLimitsUpdated(level, maxSingle_, daily_, enabled_, _msgSender());
    }

    /// @inheritdoc ILimitController
    function checkAndUpdateOutflow(address user, uint256 amount) external override whenNotPaused {
        require(hasRole(CALLER_ROLE, _msgSender()), "LimitController: unauthorized caller");
        if (amount == 0) {
            return;
        }

        uint8 level = kycRegistry.getRiskLevel(user);
        LimitConfig memory cfg = levelLimits[level];

        if (!cfg.enabled) {
            // No limits for this level.
            return;
        }

        if (cfg.maxSingle != 0) {
            require(amount <= cfg.maxSingle, "LimitController: single tx limit exceeded");
        }

        if (cfg.daily != 0) {
            uint64 today = uint64(block.timestamp / 1 days);
            DailyUsage storage usage = outflowUsage[user];

            if (usage.day != today) {
                usage.day = today;
                usage.used = 0;
            }

            uint256 newUsed = usage.used + amount;
            require(newUsed <= cfg.daily, "LimitController: daily limit exceeded");
            usage.used = newUsed;
        }
    }

    /// @notice View helper to get remaining daily capacity for a user.
    /// @dev Returns type(uint256).max if no daily cap is configured for the user's level.
    function getRemainingDailyOutflow(address user) external view returns (uint256) {
        uint8 level = kycRegistry.getRiskLevel(user);
        LimitConfig memory cfg = levelLimits[level];

        if (!cfg.enabled || cfg.daily == 0) {
            return type(uint256).max;
        }

        uint64 today = uint64(block.timestamp / 1 days);
        DailyUsage memory usage = outflowUsage[user];

        if (usage.day != today) {
            return cfg.daily;
        }

        if (usage.used >= cfg.daily) {
            return 0;
        }

        return cfg.daily - usage.used;
    }

    // --- Pause control ---

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}

