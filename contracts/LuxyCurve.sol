// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {LuxyToken} from "./LuxyToken.sol";
import {IGraduationRouter} from "./interfaces/IGraduationRouter.sol";

/// @title LuxyCurve
/// @notice Deterministic bonding curve for a single LuxyToken.
///         Price function: P(s) = P0 + dP * s^2  (s = tokens sold so far)
///         Cost to buy `amount` tokens starting at supply `s0`:
///           cost = P0*amount + dP * ((s0+amount)^3 - s0^3) / 3
///         NOTE: this uses plain uint256 fixed-point (1e18) math for clarity.
///         Before mainnet deploy, harden precision with a battle-tested
///         fixed-point lib (e.g. PRBMath) and add fuzz/invariant tests around
///         the cubic term for large supplies.
contract LuxyCurve {
    uint256 public constant WAD = 1e18;

    uint256 public constant MAX_BUY_BPS = 500;   // 5% of curve target, per tx
    uint256 public constant MAX_FEE_BPS = 500;   // 5% fee ceiling
    uint256 public constant BPS_DENOM = 10_000;

    LuxyToken public token;
    address public immutable factory;
    address public immutable graduationRouter;

    uint256 public immutable p0;      // starting price, WAD
    uint256 public immutable dP;      // curve steepness, WAD
    uint256 public immutable target;  // graduation reserve target, in wei (~3.96 ETH)
    uint256 public immutable feeBps;  // buy/sell fee, set by governance at deploy, <= MAX_FEE_BPS

    uint256 public supplySold;   // s: tokens released from the curve so far
    uint256 public reserve;      // ETH held by the curve
    bool public graduated;

    address public referrer; // optional, set on first buy per trader via referral code resolution off-chain -> passed in

    event Deployed(address indexed token, address indexed creator, uint256 p0, uint256 dP, uint256 target);
    event Buy(address indexed buyer, uint256 tokenAmount, uint256 ethIn, uint256 fee, address referrer, uint256 newSupply);
    event Sell(address indexed seller, uint256 tokenAmount, uint256 ethOut, uint256 fee, uint256 newSupply);
    event Graduated(address indexed pool, uint256 tokenAmount, uint256 ethAmount);

    error AlreadyGraduated();
    error BelowMinBuy();
    error ExceedsMaxBuyPerTx();
    error SlippageExceeded();
    error InsufficientReserve();
    error FeeTooHigh();

    constructor(
        uint256 p0_,
        uint256 dP_,
        uint256 target_,
        uint256 feeBps_,
        address graduationRouter_
    ) {
        if (feeBps_ > MAX_FEE_BPS) revert FeeTooHigh();
        factory = msg.sender;
        p0 = p0_;
        dP = dP_;
        target = target_;
        feeBps = feeBps_;
        graduationRouter = graduationRouter_;
    }

    /// @notice Wired once by the deployer helper right after both the curve
    ///         and the token exist (token.initCurve() forwards the full
    ///         supply here in the same deploy transaction).
    function setToken(address token_) external {
        require(msg.sender == factory, "only factory");
        require(address(token) == address(0), "already set");
        token = LuxyToken(token_);
    }

    /// @notice Quote the ETH cost (including fee) to buy `amount` tokens at current state.
    function quoteBuy(uint256 amount) public view returns (uint256 cost, uint256 fee) {
        uint256 s0 = supplySold;
        uint256 s1 = s0 + amount;
        uint256 base = _integral(s0, s1);
        fee = (base * feeBps) / BPS_DENOM;
        cost = base + fee;
    }

    /// @notice Quote the ETH returned (after fee) for selling `amount` tokens at current state.
    function quoteSell(uint256 amount) public view returns (uint256 proceeds, uint256 fee) {
        uint256 s0 = supplySold;
        uint256 s1 = s0 - amount;
        uint256 base = _integral(s1, s0);
        fee = (base * feeBps) / BPS_DENOM;
        proceeds = base - fee;
    }

    /// @dev cost = P0*(s1-s0) + dP*(s1^3 - s0^3)/3, all WAD-scaled.
    function _integral(uint256 s0, uint256 s1) internal view returns (uint256) {
        uint256 linear = (p0 * (s1 - s0)) / WAD;
        uint256 cubic = (dP * (s1 * s1 * s1 - s0 * s0 * s0)) / (3 * WAD * WAD);
        return linear + cubic;
    }

    function buy(uint256 minTokensOut, uint256 tokenAmount, address referrer_) external payable {
        if (graduated) revert AlreadyGraduated();
        if (tokenAmount < 1 ether) revert BelowMinBuy(); // min buy: 1 token
        if (tokenAmount > (target * MAX_BUY_BPS) / BPS_DENOM) revert ExceedsMaxBuyPerTx();
        if (tokenAmount < minTokensOut) revert SlippageExceeded();

        (uint256 cost, uint256 fee) = quoteBuy(tokenAmount);
        require(msg.value >= cost, "insufficient ETH sent");

        supplySold += tokenAmount;
        reserve += (cost - fee);

        token.transfer(msg.sender, tokenAmount);

        // refund overpayment
        if (msg.value > cost) {
            (bool ok, ) = msg.sender.call{value: msg.value - cost}("");
            require(ok, "refund failed");
        }

        emit Buy(msg.sender, tokenAmount, cost, fee, referrer_, supplySold);

        if (reserve >= target) {
            _graduate();
        }
    }

    function sell(uint256 tokenAmount, uint256 minEthOut) external {
        if (graduated) revert AlreadyGraduated();

        (uint256 proceeds, uint256 fee) = quoteSell(tokenAmount);
        if (proceeds < minEthOut) revert SlippageExceeded();
        if (proceeds > reserve) revert InsufficientReserve();

        token.transferFrom(msg.sender, address(this), tokenAmount);
        supplySold -= tokenAmount;
        reserve -= proceeds;

        (bool ok, ) = msg.sender.call{value: proceeds}("");
        require(ok, "payout failed");

        emit Sell(msg.sender, tokenAmount, proceeds, fee, supplySold);
    }

    function _graduate() internal {
        graduated = true;
        uint256 remainingTokens = token.balanceOf(address(this));
        uint256 ethAmount = reserve;
        reserve = 0;

        token.approve(graduationRouter, remainingTokens);
        address pool = IGraduationRouter(graduationRouter).graduate{value: ethAmount}(
            address(token),
            remainingTokens,
            ethAmount
        );
        token.setPool(pool);

        emit Graduated(pool, remainingTokens, ethAmount);
    }

    receive() external payable {
        revert("use buy()");
    }
}
