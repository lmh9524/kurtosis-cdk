// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KYCRegistry.sol";
import "../src/KYCDataTypes.sol";

contract KYCRegistryTest is Test {
    KYCRegistry private registry;

    function setUp() public {
        registry = new KYCRegistry(address(this));
    }

    function testDefaultIsNotApproved() public view {
        bool approved = registry.isKYCApproved(address(0x1234));
        assert(!approved);
    }

    function testSetApprovedKYC() public {
        address user = address(0x1234);
        uint8 level = 2;
        uint256 expiry = block.timestamp + 1000;
        bytes32 providerId = keccak256(abi.encodePacked("provider"));

        registry.setKYCStatus(user, Status.Approved, level, expiry, providerId);

        assert(registry.isKYCApproved(user));
        assert(registry.getRiskLevel(user) == level);

        KYCRecord memory record = registry.getRecord(user);
        assert(record.status == Status.Approved);
        assert(record.level == level);
        assert(record.expiry == expiry);
        assert(record.kycProviderId == providerId);
    }

    function testExpiredIsNotApproved() public {
        address user = address(0x1234);
        uint8 level = 1;
        uint256 expiry = block.timestamp + 1000;
        bytes32 providerId = keccak256(abi.encodePacked("provider"));

        registry.setKYCStatus(user, Status.Approved, level, expiry, providerId);

        // 模拟时间向前推进到过期之后
        vm.warp(expiry + 1);

        assert(!registry.isKYCApproved(user));
    }
}

