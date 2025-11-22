// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../KYCDataTypes.sol";

interface IKYCRegistry {
    event KYCStatusUpdated(
        address indexed user,
        Status status,
        uint8 level,
        uint256 expiry,
        bytes32 kycProviderId,
        address indexed operator
    );

    function setKYCStatus(
        address user,
        Status status,
        uint8 level,
        uint256 expiry,
        bytes32 kycProviderId
    ) external;

    function isKYCApproved(address user) external view returns (bool);

    function getRiskLevel(address user) external view returns (uint8);

    function getRecord(address user) external view returns (KYCRecord memory);
}

