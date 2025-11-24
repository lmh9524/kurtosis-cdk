// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/RWAProductUpgradeable.sol";
import "../src/KYCDataTypes.sol";
import "./mocks/MockERC20.sol";

contract RWAProductUpgradeableTest is Test {
    using stdStorage for StdStorage;

    RWAProductUpgradeable public product;
    MockERC20 public token;

    address public admin = address(0x1);
    address public investor = address(0x2);
    address public other = address(0x3);

    bytes32 public constant PRODUCT_ID = keccak256("PRODUCT-001");

    // Minimal mock for IKYCRegistry that we can control via storage
    address public kycRegistry;

    function setUp() public {
        vm.startPrank(admin);

        // Deploy mock ERC20 as underlying token
        token = new MockERC20("USD Coin", "USDC", 18);

        // Deploy a minimal KYC registry mock (EOA placeholder)
        kycRegistry = address(0x1234);

        // Deploy product and initialize
        product = new RWAProductUpgradeable();
        product.initialize(admin, kycRegistry, address(0));

        vm.stopPrank();
    }

    function _mintAndApprove(address user, uint256 amount) internal {
        token.mint(user, amount);
        vm.prank(user);
        token.approve(address(product), amount);
    }

    function test_IssueProduct_Succeeds() public {
        vm.prank(admin);
        product.issueProduct(
            PRODUCT_ID,
            "Bond 2025",
            address(token),
            1_000e18,
            100e18,
            block.timestamp + 365 days,
            500 // 5% in basis points
        );

        (
            bytes32 pid,
            string memory name,
            address underlyingToken,
            uint256 totalSupply,
            uint256 pricePerShare,
            uint256 maturityDate,
            uint256 interestRate,
            uint256 issuedAt,
            RWAProductUpgradeable.ProductStatus status
        ) = product.products(PRODUCT_ID);

        assertEq(pid, PRODUCT_ID);
        assertEq(name, "Bond 2025");
        assertEq(underlyingToken, address(token));
        assertEq(totalSupply, 1_000e18);
        assertEq(pricePerShare, 100e18);
        assertEq(interestRate, 500);
        assertEq(uint256(status), uint256(RWAProductUpgradeable.ProductStatus.Active));
        assertGt(issuedAt, 0);
        assertGt(maturityDate, block.timestamp);
    }

    function test_SubscribeAndRedeem_Flow() public {
        // 1. issue product
        vm.prank(admin);
        product.issueProduct(
            PRODUCT_ID,
            "Bond 2025",
            address(token),
            1_000e18,
            100e18,
            block.timestamp + 365 days,
            500
        );

        // 2. mock KYC approved via vm.mockCall
        vm.mockCall(
            kycRegistry,
            abi.encodeWithSelector(IKYCRegistry.isKYCApproved.selector, investor),
            abi.encode(true)
        );

        // 3. mint underlying to investor and approve
        uint256 subscribeShares = 100e18;
        uint256 subscribeAmount = subscribeShares * 100e18 / 1e18; // 100 * 100
        _mintAndApprove(investor, subscribeAmount);

        // 4. subscribe
        vm.prank(investor);
        product.subscribe(PRODUCT_ID, subscribeShares);

        assertEq(product.holdings(PRODUCT_ID, investor), subscribeShares);

        // 5. redeem half
        uint256 redeemShares = 50e18;
        uint256 redeemAmount = redeemShares * 100e18 / 1e18;

        vm.prank(investor);
        product.redeem(PRODUCT_ID, redeemShares);

        assertEq(product.holdings(PRODUCT_ID, investor), subscribeShares - redeemShares);
        assertEq(token.balanceOf(investor), redeemAmount);
    }

    function test_DistributeInterest_ComputesCorrectly() public {
        vm.prank(admin);
        product.issueProduct(
            PRODUCT_ID,
            "Bond 2025",
            address(token),
            1_000e18,
            100e18,
            block.timestamp + 365 days,
            500 // 5% annual
        );

        vm.mockCall(
            kycRegistry,
            abi.encodeWithSelector(IKYCRegistry.isKYCApproved.selector, investor),
            abi.encode(true)
        );

        uint256 shares = 100e18;
        uint256 principal = shares * 100e18; // before /1e18
        uint256 daysHeld = 30;
        uint256 expectedInterest = principal * 500 * daysHeld / 365 / 10000 / 1e18;

        _mintAndApprove(investor, shares * 100e18 / 1e18);
        vm.prank(investor);
        product.subscribe(PRODUCT_ID, shares);

        // Fund contract with enough tokens to pay interest
        token.mint(address(product), expectedInterest);

        address[] memory investors = new address[](1);
        investors[0] = investor;

        vm.prank(admin);
        product.distributeInterest(PRODUCT_ID, investors, daysHeld);

        assertEq(token.balanceOf(investor), expectedInterest);
    }

    function test_SettleMaturity_PaysPrincipalAndFinalInterest() public {
        vm.prank(admin);
        product.issueProduct(
            PRODUCT_ID,
            "Bond 2025",
            address(token),
            1_000e18,
            100e18,
            block.timestamp + 10 days,
            500
        );

        vm.mockCall(
            kycRegistry,
            abi.encodeWithSelector(IKYCRegistry.isKYCApproved.selector, investor),
            abi.encode(true)
        );

        uint256 shares = 100e18;
        uint256 principal = shares * 100e18 / 1e18;

        _mintAndApprove(investor, shares * 100e18 / 1e18);
        vm.prank(investor);
        product.subscribe(PRODUCT_ID, shares);

        // Fast-forward to maturity
        vm.warp(block.timestamp + 11 days);

        // Compute max possible interest (upper bound, exact daysToMaturity depends on lastInterestDistribution)
        uint256 daysToMaturity = (product.products(PRODUCT_ID).maturityDate() - product.lastInterestDistribution(PRODUCT_ID)) / 1 days;
        uint256 finalInterestUpper = shares * 100e18 * 500 * daysToMaturity / 365 / 10000 / 1e18;

        token.mint(address(product), principal + finalInterestUpper);

        address[] memory investors = new address[](1);
        investors[0] = investor;

        vm.prank(admin);
        product.settleMaturity(PRODUCT_ID, investors);

        assertGe(token.balanceOf(investor), principal);
        assertEq(product.holdings(PRODUCT_ID, investor), 0);
    }

    function test_OnlyIssuerCanIssue() public {
        vm.expectRevert(); // AccessControl: missing role
        product.issueProduct(
            PRODUCT_ID,
            "Bond 2025",
            address(token),
            1_000e18,
            100e18,
            block.timestamp + 365 days,
            500
        );
    }

    function test_OnlyOperatorCanDistributeInterest() public {
        vm.expectRevert(); // AccessControl: missing role
        address[] memory investors = new address[](1);
        investors[0] = investor;
        product.distributeInterest(PRODUCT_ID, investors, 30);
    }

    function test_SubscribeRequiresKYC() public {
        vm.prank(admin);
        product.issueProduct(
            PRODUCT_ID,
            "Bond 2025",
            address(token),
            1_000e18,
            100e18,
            block.timestamp + 365 days,
            500
        );

        // 默认 mock 为 false（未 KYC），不设置 mockCall 即为 0（false）
        _mintAndApprove(investor, 100e18 * 100e18 / 1e18);

        vm.expectRevert("KYC required");
        vm.prank(investor);
        product.subscribe(PRODUCT_ID, 100e18);
    }
}


