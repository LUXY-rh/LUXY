// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../contracts/LuxyToken.sol";
import "../contracts/LuxyCurve.sol";
import "../contracts/LuxyFactory.sol";

contract LuxyTest is Test {
    LuxyFactory public factory;
    LuxyToken public token;
    LuxyCurve public curve;

    address public creator = makeAddr("creator");
    address public buyer = makeAddr("buyer");
    address public seller = makeAddr("seller");
    address public feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        vm.deal(buyer, 100 ether);
        vm.deal(seller, 0);

        factory = new LuxyFactory(feeRecipient);

        vm.prank(creator);
        (address t, address c) = factory.deploy("Luxy Test", "LTST");
        token = LuxyToken(t);
        curve = LuxyCurve(payable(c));
    }

    function testDeploy() public view {
        assertEq(token.name(), "Luxy Test");
        assertEq(token.symbol(), "LTST");
        assertEq(token.decimals(), 18);
        assertEq(token.curve(), address(curve));
    }

    function testBuy() public {
        vm.prank(buyer);
        curve.buy{value: 1 ether}();
        assertGt(token.balanceOf(buyer), 0);
        assertGt(curve.totalSold(), 0);
        assertGt(curve.reserveETH(), 0);
    }

    function testSell() public {
        // Buy first
        vm.prank(buyer);
        curve.buy{value: 1 ether}();

        uint256 bal = token.balanceOf(buyer);
        uint256 ethBefore = buyer.balance;

        // Sell half back
        vm.prank(buyer);
        curve.sell(bal / 2);

        assertGt(buyer.balance, ethBefore);
    }

    function testMaxWallet() public {
        // Buy
        vm.prank(buyer);
        curve.buy{value: 0.1 ether}();

        uint256 bal = token.balanceOf(buyer);
        // Transfer a tiny amount to another wallet (should work)
        vm.prank(buyer);
        token.transfer(seller, 1 ether); // 1 token
        assertGt(token.balanceOf(seller), 0);
    }

    function testQuoteMonotonic() public {
        uint256 q1 = curve.getQuote(100 ether, true);
        vm.prank(buyer);
        curve.buy{value: 1 ether}();
        uint256 q2 = curve.getQuote(100 ether, true);
        // Price should increase after a buy
        assertGt(q2, q1);
    }

    function testFees() public {
        uint256 feeBalBefore = feeRecipient.balance;
        vm.prank(buyer);
        curve.buy{value: 1 ether}();
        assertGt(feeRecipient.balance, feeBalBefore);
    }

    function testCannotBuyAfterGraduation() public {
        // Set fees to 0 so all ETH goes to the curve
        vm.prank(address(factory));
        curve.setBuyFee(0);
        vm.prank(address(factory));
        curve.setSellFee(0);

        // Buy until graduation (target is 3.96 ETH)
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        curve.buy{value: 3.97 ether}();

        assertTrue(curve.graduated());

        vm.expectRevert("LuxyCurve: graduated");
        vm.prank(buyer);
        curve.buy{value: 0.1 ether}();
    }

    function testRevertZeroBuy() public {
        vm.expectRevert("LuxyCurve: zero ETH");
        vm.prank(buyer);
        curve.buy{value: 0}();
    }

    function testRevertZeroSell() public {
        vm.expectRevert("LuxyCurve: zero tokens");
        vm.prank(buyer);
        curve.sell(0);
    }

    function testGovernanceOnly() public {
        vm.expectRevert("LuxyCurve: only factory");
        vm.prank(buyer);
        curve.setBuyFee(50);
    }

    function testCannotSetCurveTwice() public {
        // Curve already set by factory — non-factory can't call
        vm.expectRevert("LuxyToken: curve already set");
        vm.prank(address(factory));
        token.setCurve(address(0x1));
    }
}
