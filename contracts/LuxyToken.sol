// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title LuxyToken
/// @notice ERC20 deployed atomically with its LuxyCurve. Enforces a max-wallet
///         cap on every transfer until the curve marks the pair as exempt
///         (curve + eventual LP pool are always exempt).
contract LuxyToken is ERC20 {
    /// @dev Total supply is fixed at deploy time and minted entirely to the curve,
    ///      which then releases it along the bonding curve.
    uint256 public immutable maxWallet; // 5% of total supply, set at construction

    address public curve;               // wired once by initCurve()
    address public pool;                 // set once by curve at graduation
    address private immutable initializer; // deployer helper allowed to wire the curve

    error MaxWalletExceeded(address account, uint256 balanceAfter, uint256 cap);
    error OnlyCurve();
    error AlreadyInitialized();
    error OnlyInitializer();

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalSupply_,
        address initializer_
    ) ERC20(name_, symbol_) {
        initializer = initializer_;
        maxWallet = (totalSupply_ * 5) / 100;
        _mint(initializer_, totalSupply_);
    }

    /// @notice Called once, right after the curve is deployed, by the same
    ///         deployer helper that minted the initial supply to itself.
    ///         Wires the curve address and forwards the full supply to it.
    function initCurve(address curve_) external {
        if (msg.sender != initializer) revert OnlyInitializer();
        if (curve != address(0)) revert AlreadyInitialized();
        curve = curve_;
        _transfer(initializer, curve_, balanceOf(initializer));
    }

    /// @notice Called once by the curve when the pool is created at graduation,
    ///         so the pool address is exempt from the max-wallet cap.
    function setPool(address pool_) external {
        if (msg.sender != curve) revert OnlyCurve();
        pool = pool_;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        // Curve, pool, and the one-shot initializer (holds full supply only
        // between construction and initCurve()) are exempt — everyone else is capped.
        if (to != curve && to != pool && to != initializer && to != address(0)) {
            uint256 bal = balanceOf(to);
            if (bal > maxWallet) revert MaxWalletExceeded(to, bal, maxWallet);
        }
    }
}
