// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/KYCRegistry.sol";
import "../src/AccessController.sol";
import "../src/KYCGuardedToken.sol";
import "../src/KYCDataTypes.sol";
import "../src/LimitController.sol";

contract KYCGuardedTokenTest is Test {
    KYCRegistry private registry;
    AccessController private controller;
    KYCGuardedToken private token;

    address private admin = address(this);
    address private userA = address(0xA11CE);
    address private userB = address(0xBEEF);

    bytes32 private constant PROVIDER_ID = keccak256("provider");

    function setUp() public {
        registry = new KYCRegistry(admin);
        controller = new AccessController(admin, address(registry));
        token = new KYCGuardedToken("KYC Token", "KYC", admin, address(controller));
    }

    function _setApproved(address user, uint256 expiry) internal {
        registry.setKYCStatus(user, Status.Approved, 1, expiry, PROVIDER_ID);
    }

    function testMintRequiresKYCApproved() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, expiry);

        // userA 通过 KYC，可以被铸币
        token.mint(userA, 100);
        assertEq(token.balanceOf(userA), 100);

        // userB 未通过 KYC，应该在 _update 中被拒绝
        vm.expectRevert(bytes("KYCGuardedToken: mint not allowed"));
        token.mint(userB, 100);
    }

    function testTransferBlockedWithoutKYC() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, expiry);

        token.mint(userA, 100);

        // userB 没有 KYC，转账应该失败
        vm.expectRevert(bytes("KYCGuardedToken: transfer not allowed"));
        token.transfer(userB, 10);
    }

    function testTransferAllowedWhenBothApproved() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, expiry);
        _setApproved(userB, expiry);

        token.mint(userA, 100);

        // 从 userA 视角发起转账
        vm.prank(userA);
        token.transfer(userB, 10);

        assertEq(token.balanceOf(userA), 90);
        assertEq(token.balanceOf(userB), 10);
    }

    function testPauseBlocksAllTransfersAndMints() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, expiry);

        token.mint(userA, 100);

        controller.pause();

        // 暂停后，转账和铸币都会被 AccessController 拒绝
        vm.expectRevert(bytes("KYCGuardedToken: transfer not allowed"));
        token.transfer(userB, 10);

        vm.expectRevert(bytes("KYCGuardedToken: mint not allowed"));
        token.mint(userA, 10);
    }
}

contract KYCGuardedTokenLimitTest is Test {
    KYCRegistry private registry;
    AccessController private controller;
    LimitController private limitController;
    KYCGuardedToken private token;

    address private admin = address(this);
    address private userA = address(0xA11CE);
    address private userB = address(0xBEEF);

    bytes32 private constant PROVIDER_ID = keccak256("provider");

    function setUp() public {
        registry = new KYCRegistry(admin);
        controller = new AccessController(admin, address(registry));
        token = new KYCGuardedToken("KYC Token", "KYC", admin, address(controller));

        limitController = new LimitController(admin, address(registry));
        // For level 1: max single = 50, daily = 0 (only per-tx cap), enabled = true
        limitController.setLevelLimits(1, 50, 0, true);
        limitController.grantRole(limitController.CALLER_ROLE(), address(token));

        token.setLimitController(address(limitController));
    }

    function _setApproved(address user, uint256 expiry) internal {
        registry.setKYCStatus(user, Status.Approved, 1, expiry, PROVIDER_ID);
    }

    function testTransferRespectsSingleTxLimit() public {
        uint256 expiry = block.timestamp + 1 days;
        _setApproved(userA, expiry);
        _setApproved(userB, expiry);

        token.mint(userA, 100);

        // 40 < 50, 应该成功
        vm.prank(userA);
        token.transfer(userB, 40);

        // 60 > 50, 由于 LimitController 单笔限额，应该失败
        vm.prank(userA);
        vm.expectRevert(bytes("LimitController: single tx limit exceeded"));
        token.transfer(userB, 60);
    }
}

