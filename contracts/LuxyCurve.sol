// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LuxyToken} from "./LuxyToken.sol";

/// @title LuxyCurve — Bonding curve: P(s) = P₀ + ΔP · s²
/// @notice Prices every buy/sell from on-chain reserves. Graduates at target.
contract LuxyCurve {
    LuxyToken public immutable token;

    // Curve parameters (fixed at deploy, immutable)
    uint256 public immutable P0;        // Starting price per token (in wei)
    uint256 public immutable deltaP;    // Steepness coefficient
    uint256 public immutable targetETH; // Reserve target for graduation (~3.96 ETH)
    uint256 public constant PRECISION = 1e18;

    // State
    uint256 public totalSold;       // Total tokens sold (cumulative supply of the curve)
    uint256 public reserveETH;      // Total ETH in the curve
    bool public graduated;

    // Fee (basis points, max 500 = 5%)
    uint256 public buyFeeBps = 100;  // 1%
    uint256 public sellFeeBps = 100; // 1%
    uint256 public constant MAX_FEE_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10000;

    address public immutable factory;
    address public immutable feeRecipient;

    event Bought(address indexed buyer, uint256 ethIn, uint256 tokensOut);
    event Sold(address indexed seller, uint256 tokensIn, uint256 ethOut);
    event Graduated(address indexed pool, uint256 eth, uint256 tokens);

    modifier onlyFactory() {
        require(msg.sender == factory, "LuxyCurve: only factory");
        _;
    }

    modifier tradingLive() {
        require(!graduated, "LuxyCurve: graduated");
        _;
    }

    constructor(
        address _token,
        uint256 _P0,
        uint256 _deltaP,
        uint256 _targetETH,
        address _factory,
        address _feeRecipient
    ) {
        token = LuxyToken(_token);
        P0 = _P0;
        deltaP = _deltaP;
        targetETH = _targetETH;
        factory = _factory;
        feeRecipient = _feeRecipient;
    }

    // ── Quote ──

    /// @notice Returns the ETH quote for a buy or sell
    /// @param amount Token amount
    /// @return quote The ETH value of the trade (before fees)
    function getQuote(uint256 amount, bool /* isBuy */) public view returns (uint256 quote) {
        // price(s) = P0 + deltaP * s² / PRECISION
        uint256 s = totalSold;
        uint256 price = P0 + (deltaP * s * s) / PRECISION;
        quote = (amount * price) / PRECISION;
    }

    /// @notice Returns quotes WITH fees applied
    function getQuoteWithFee(uint256 amount, bool isBuy)
        external
        view
        returns (uint256 quote, uint256 fee)
    {
        quote = getQuote(amount, isBuy);
        uint256 feeBps = isBuy ? buyFeeBps : sellFeeBps;
        fee = (quote * feeBps) / BPS_DENOMINATOR;
        if (isBuy) quote += fee;
        else quote -= fee;
    }

    // ── Trade ──

    /// @notice Buy tokens with ETH — exact ETH input
    function buy() external payable tradingLive returns (uint256 tokensOut) {
        require(msg.value > 0, "LuxyCurve: zero ETH");

        uint256 fee = (msg.value * buyFeeBps) / BPS_DENOMINATOR;
        uint256 ethForTokens = msg.value - fee;

        // Calculate tokens for ETH at current price
        uint256 price = P0 + (deltaP * totalSold * totalSold) / PRECISION;
        tokensOut = (ethForTokens * PRECISION) / price;
        require(tokensOut > 0, "LuxyCurve: zero tokens");

        totalSold += tokensOut;
        reserveETH += ethForTokens;

        // Mint tokens to buyer
        token.mint(msg.sender, tokensOut);

        // Send fee
        if (fee > 0) payable(feeRecipient).transfer(fee);

        emit Bought(msg.sender, msg.value, tokensOut);

        // Check graduation
        if (reserveETH >= targetETH) {
            _graduate();
        }
    }

    /// @notice Sell tokens for ETH — proportional to reserve
    function sell(uint256 tokensIn) external tradingLive returns (uint256 ethOut) {
        require(tokensIn > 0, "LuxyCurve: zero tokens");
        require(token.balanceOf(msg.sender) >= tokensIn, "LuxyCurve: insufficient balance");
        require(tokensIn <= totalSold, "LuxyCurve: exceeds supply");

        // Proportional: ethOut = tokensIn * reserveETH / totalSold
        uint256 grossETH = (tokensIn * reserveETH) / totalSold;
        uint256 fee = (grossETH * sellFeeBps) / BPS_DENOMINATOR;
        ethOut = grossETH - fee;

        require(ethOut > 0, "LuxyCurve: zero ETH out");
        require(reserveETH >= grossETH, "LuxyCurve: insufficient reserves");

        totalSold -= tokensIn;
        reserveETH -= grossETH;

        token.burn(msg.sender, tokensIn);
        payable(msg.sender).transfer(ethOut);
        if (fee > 0) payable(feeRecipient).transfer(fee);

        emit Sold(msg.sender, tokensIn, ethOut);
    }

    // ── Admin ──

    function setBuyFee(uint256 _bps) external onlyFactory {
        require(_bps <= MAX_FEE_BPS, "LuxyCurve: fee too high");
        buyFeeBps = _bps;
    }

    function setSellFee(uint256 _bps) external onlyFactory {
        require(_bps <= MAX_FEE_BPS, "LuxyCurve: fee too high");
        sellFeeBps = _bps;
    }

    // ── Graduation ──

    /// @notice Force graduation (emergency / admin override)
    function forceGraduate() external onlyFactory {
        require(!graduated, "LuxyCurve: already graduated");
        _graduate();
    }

    function _graduate() internal {
        graduated = true;
        token.graduate();
        emit Graduated(address(0), reserveETH, token.balanceOf(address(this)));
    }

    receive() external payable {
        // Only accept ETH via buy()
        revert("LuxyCurve: use buy()");
    }
}
