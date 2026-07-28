// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title RewardVault
/// @notice Pro-rata WETH staking rewards for a single graduated pool's LP
///         token. No lock period on the stake itself — only reward claims are
///         a separate, on-demand action, matching the docs. One vault is
///         deployed per graduated launch by the graduation handler.
contract RewardVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable stakeToken; // the graduated pool's LP token
    IERC20 public immutable rewardToken; // WETH

    uint256 public totalStaked;
    mapping(address => uint256) public stakedOf;

    uint256 public rewardPerTokenStored;
    mapping(address => uint256) public rewardPerTokenPaid;
    mapping(address => uint256) public rewardsAccrued;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardAdded(uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    constructor(address owner_, address stakeToken_, address rewardToken_) Ownable(owner_) {
        stakeToken = IERC20(stakeToken_);
        rewardToken = IERC20(rewardToken_);
    }

    modifier updateReward(address account) {
        if (account != address(0)) {
            rewardsAccrued[account] = earned(account);
            rewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function earned(address account) public view returns (uint256) {
        uint256 delta = rewardPerTokenStored - rewardPerTokenPaid[account];
        return rewardsAccrued[account] + (stakedOf[account] * delta) / 1e18;
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "RewardVault: zero amount");
        totalStaked += amount;
        stakedOf[msg.sender] += amount;
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0 && amount <= stakedOf[msg.sender], "RewardVault: bad amount");
        totalStaked -= amount;
        stakedOf[msg.sender] -= amount;
        stakeToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /// @notice Claim accrued WETH rewards. Manual, on-demand — no auto-compounding.
    function claim() external nonReentrant updateReward(msg.sender) {
        uint256 amount = rewardsAccrued[msg.sender];
        require(amount > 0, "RewardVault: nothing to claim");
        rewardsAccrued[msg.sender] = 0;
        rewardToken.safeTransfer(msg.sender, amount);
        emit RewardClaimed(msg.sender, amount);
    }

    /// @notice Streams newly received WETH into the pro-rata pool. Called by
    ///         whatever fee-splitting mechanism routes yield to this vault.
    function notifyRewardAmount(uint256 amount) external updateReward(address(0)) {
        require(totalStaked > 0, "RewardVault: no stakers");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardPerTokenStored += (amount * 1e18) / totalStaked;
        emit RewardAdded(amount);
    }
}
