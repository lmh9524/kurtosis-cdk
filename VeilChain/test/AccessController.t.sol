// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KYCRegistry.sol";
import "../src/AccessController.sol";
import "../src/KYCDataTypes.sol";

contract AccessControllerTest is Test {
    KYCRegistry private registry;
    AccessController private controller;

    address private admin = address(this);
    address private userA = address(0xA11CE);
    address private userB = address(0xBEEF);

    bytes32 private constant PROVIDER_ID = keccak256("provider");

    function setUp() public {
        registry = new KYCRegistry(admin);
        controller = new AccessController(admin, address(registry));
    }

    function _setApproved(address user, uint256 expiry) internal {
        registry.setKYCStatus(user, Status.Approved, 1, expiry, PROVIDER_ID);
    }

    function testTransferAllowedWhenBothApproved() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, expiry);
        _setApproved(userB, expiry);

        bool ok = controller.canTransfer(userA, userB);
        assertTrue(ok);
    }

    function testTransferDeniedWhenSenderNotApproved() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userB, expiry);

        bool ok = controller.canTransfer(userA, userB);
        assertFalse(ok);
    }

    function testTransferDeniedWhenRecipientExpired() public {
        uint256 expiryActive = block.timestamp + 1 days;
        uint256 expiryPast = block.timestamp + 1000;

        _setApproved(userA, expiryActive);
        _setApproved(userB, expiryPast);

        // 快进时间到 userB 过期之后
        vm.warp(expiryPast + 1);

        bool ok = controller.canTransfer(userA, userB);
        assertFalse(ok);
    }

    function testCanMintOnlyApproved() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, expiry);

        assertTrue(controller.canMint(userA));
        assertFalse(controller.canMint(userB));
    }

    function testPauseBlocksTransfersAndMints() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, expiry);
        _setApproved(userB, expiry);

        // 正常情况下允许
        assertTrue(controller.canTransfer(userA, userB));
        assertTrue(controller.canMint(userA));

        // 暂停后全部拒绝
        controller.pause();

        assertFalse(controller.canTransfer(userA, userB));
        assertFalse(controller.canMint(userA));
    }
}

