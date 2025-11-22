// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Enum representing high-level KYC status for an address.
enum Status {
    None,
    Pending,
    Approved,
    Rejected,
    Blacklisted
}

/// @notice On-chain KYC record stored for each user.
/// @dev Does not store any raw PII, only abstracted risk / provider info.
struct KYCRecord {
    Status status;
    uint8 level;
    uint64 updatedAt;
    uint256 expiry;
    bytes32 kycProviderId;
}

