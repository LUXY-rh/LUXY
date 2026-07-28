// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IGraduationRouter
/// @notice Boundary between LuxyCurve and the AMM integration. Keeping this as
///         a thin adapter interface means the curve contract itself never
///         needs to import full Uniswap V3 core/periphery code, and the real
///         adapter (pointing at Robinhood Chain's Uniswap V3 deployment) can
///         be swapped or upgraded without touching curve logic.
///         TODO(luxy): implement GraduationRouterV3 against the actual
///         Uniswap V3 Factory / NonfungiblePositionManager addresses on
///         Robinhood Chain (4663) before mainnet deploy.
interface IGraduationRouter {
    /// @param token       the graduating token (curve holds `tokenAmount` of it)
    /// @param tokenAmount remaining curve supply to seed the pool with
    /// @param ethAmount   ETH reserve to pair against (sent as msg.value)
    /// @return pool       address of the created/seeded pool
    function graduate(address token, uint256 tokenAmount, uint256 ethAmount)
        external
        payable
        returns (address pool);
}
