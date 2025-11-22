// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KYCRegistry.sol";
import "../src/LimitController.sol";
import "../src/KYCDataTypes.sol";

contract LimitControllerTest is Test {
    KYCRegistry private registry;
    LimitController private controller;

    address private admin = address(this);
    address private userA = address(0xA11CE);

    bytes32 private constant PROVIDER_ID = keccak256("provider");

    function setUp() public {
        registry = new KYCRegistry(admin);
        controller = new LimitController(admin, address(registry));
    }

    function _setApproved(address user, uint8 level, uint256 expiry) internal {
        registry.setKYCStatus(user, Status.Approved, level, expiry, PROVIDER_ID);
    }

    function testNoLimitsWhenDisabled() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, 1, expiry);

        // No levelLimits configured -> enabled = false by default
        // Grant CALLER_ROLE to this test contract to simulate a token.
        controller.grantRole(controller.CALLER_ROLE(), address(this));

        controller.checkAndUpdateOutflow(userA, 100 ether);
    }

    function testSingleTxLimit() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, 1, expiry);

        controller.setLevelLimits(1, 100, 0, true); // maxSingle = 100, no daily cap
        controller.grantRole(controller.CALLER_ROLE(), address(this));

        // 50 <= 100 -> ok
        controller.checkAndUpdateOutflow(userA, 50);

        // 150 > 100 -> revert
        vm.expectRevert(bytes("LimitController: single tx limit exceeded"));
        controller.checkAndUpdateOutflow(userA, 150);
    }

    function testDailyLimit() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, 1, expiry);

        controller.setLevelLimits(1, 0, 100, true); // daily cap = 100, no per-tx cap
        controller.grantRole(controller.CALLER_ROLE(), address(this));

        controller.checkAndUpdateOutflow(userA, 40);
        controller.checkAndUpdateOutflow(userA, 50);

        // So far used = 90, next 20 would push to 110 > 100
        vm.expectRevert(bytes("LimitController: daily limit exceeded"));
        controller.checkAndUpdateOutflow(userA, 20);
    }
}

