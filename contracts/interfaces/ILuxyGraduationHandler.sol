// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILuxyGraduationHandler
/// @notice Pluggable handler invoked once by LuxyCurve when a curve graduates.
///         Receives the remaining token supply (already transferred) and the
///         ETH reserve (sent as msg.value) and is responsible for creating the
///         public liquidity position (e.g. a Uniswap V3 pool + full-range
///         position) and locking it. Kept as an interface so the AMM
///         integration can be swapped or upgraded without touching the curve.
interface ILuxyGraduationHandler {
    function onGraduate(address token, uint256 tokenAmount) external payable;
}
