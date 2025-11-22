// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./KYCRegistryUpgradeable.sol";

/// @title KYCRegistryV2
/// @notice V2 version for upgrade testing - adds view helper without breaking storage.
/// @dev This is for demonstration/testing of the upgrade mechanism.
contract KYCRegistryV2 is KYCRegistryUpgradeable {
    /// @notice New event added in V2 for demonstration.
    event UpgradeCompleted(string version, uint256 timestamp);

    /// @notice New view function added in V2 - checks if user has specific KYC level.
    /// @param user The address to check.
    /// @param requiredLevel The minimum KYC level required.
    /// @return bool True if user is approved and has at least the required level.
    function hasMinimumLevel(address user, uint8 requiredLevel) 
        external 
        view 
        returns (bool) 
    {
        if (!isKYCApproved(user)) {
            return false;
        }
        return getRiskLevel(user) >= requiredLevel;
    }

    /// @notice Returns the contract version string.
    /// @return string Version identifier.
    function version() external pure returns (string memory) {
        return "v2.0.0";
    }

    /// @dev Additional storage gap adjustment for V2 (49 slots, since we haven't added storage vars).
    /// Note: In real upgrades, adjust gap based on new storage variables added.
    uint256[49] private __gap_v2;
}

