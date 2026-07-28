// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ILuxyGraduationHandler.sol";
import "./interfaces/IUniswapV3Minimal.sol";

/// @title UniswapV3GraduationHandler
/// @notice Reference implementation of ILuxyGraduationHandler. Wraps the ETH
///         reserve into WETH, creates/initializes the token/WETH pool if
///         needed, and mints a full-range liquidity position that stays in
///         this contract forever (never approved or transferred out) — this
///         is the "locked LP" the docs describe.
///
///         ⚠️ Reference only: fill in the real WETH9 / NonfungiblePositionManager
///         addresses for Robinhood Chain before deploying, and get this
///         audited — it moves real ETH and mints real liquidity positions.
contract UniswapV3GraduationHandler is ILuxyGraduationHandler, Ownable {
    IWETH9 public immutable weth;
    INonfungiblePositionManager public immutable positionManager;
    address public immutable factory; // LuxyFactory, the only allowed caller

    /// @notice Pool fee tier used for every graduated pair (0.3% default).
    uint24 public poolFee = 3000;

    /// @notice tokenId of the locked position, per launched token.
    mapping(address => uint256) public positionIdOf;

    event PositionCreated(address indexed token, address indexed pool, uint256 tokenId, uint128 liquidity);

    modifier onlyFactory() {
        require(msg.sender == factory, "GraduationHandler: not factory");
        _;
    }

    constructor(address owner_, address factory_, address weth_, address positionManager_) Ownable(owner_) {
        factory = factory_;
        weth = IWETH9(weth_);
        positionManager = INonfungiblePositionManager(positionManager_);
    }

    function setPoolFee(uint24 fee_) external onlyOwner {
        poolFee = fee_;
    }

    /// @inheritdoc ILuxyGraduationHandler
    function onGraduate(address token, uint256 tokenAmount) external payable override onlyFactory {
        weth.deposit{value: msg.value}();

        (address token0, address token1, uint256 amount0, uint256 amount1) = token < address(weth)
            ? (token, address(weth), tokenAmount, msg.value)
            : (address(weth), token, msg.value, tokenAmount);

        IERC20(token0).approve(address(positionManager), amount0);
        IERC20(token1).approve(address(positionManager), amount1);

        // The pool address itself was already pre-created by LuxyFactory at
        // launch time (see LuxyFactory.poolOf) — this call is idempotent: it
        // only initializes the starting price if that hasn't happened yet.
        positionManager.createAndInitializePoolIfNecessary(token0, token1, poolFee, _sqrtPriceX96(amount0, amount1));

        // Full-range position — simplest, most defensible default for a
        // graduation LP with no active management.
        int24 tickLower = -887200;
        int24 tickUpper = 887200;

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: poolFee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this), // locked: NFT stays here, never moved
            deadline: block.timestamp
        });

        (uint256 tokenId, uint128 liquidity, , ) = positionManager.mint(params);
        positionIdOf[token] = tokenId;

        emit PositionCreated(token, address(0), tokenId, liquidity);
    }

    receive() external payable {}

    /// @dev Reference-quality price derivation only. For production-grade
    ///      precision on very large amounts, use Uniswap's FullMath/TickMath
    ///      libraries (512-bit mulDiv) instead of this scaled-down approximation.
    function _sqrtPriceX96(uint256 amount0, uint256 amount1) internal pure returns (uint160) {
        uint256 numerator = amount1;
        uint256 denominator = amount0;
        while (numerator > type(uint128).max) {
            numerator >>= 1;
            denominator >>= 1;
        }
        if (denominator == 0) denominator = 1;
        uint256 ratioX192 = (numerator << 192) / denominator; // safe: numerator <= 2^128
        return uint160(_sqrt(ratioX192));
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
