// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILimitController {
    /// @notice Check and update the outbound quota usage for a user.
    /// @dev SHOULD revert if the operation would exceed any configured limit.
    /// @param user The address whose quota is being consumed.
    /// @param amount The amount being sent out (in token units).
    function checkAndUpdateOutflow(address user, uint256 amount) external;
}

