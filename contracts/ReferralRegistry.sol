// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ReferralRegistry
/// @notice One permanent code per referrer. Curves (or a fee router paying on
///         their behalf) credit a referrer's accrued balance from fee volume;
///         referrers withdraw any time. Tiering by volume is computed here so
///         the frontend can read a single `tierOf(address)` value.
contract ReferralRegistry is Ownable, ReentrancyGuard {
    struct Referrer {
        bytes32 code;
        uint256 lifetimeVolume; // wei of trade volume credited under this code
        uint256 accrued;        // wei withdrawable now
    }

    mapping(address => Referrer) public referrerOf;
    mapping(bytes32 => address) public ownerOfCode;

    /// @notice Curves/fee routers authorized to credit referral earnings.
    mapping(address => bool) public isCreditor;

    /// @notice Volume thresholds (wei) for tiers 1..n; share bps per tier.
    uint256[] public tierThresholds;
    uint16[] public tierShareBps;

    event CodeRegistered(address indexed referrer, bytes32 code);
    event Credited(address indexed referrer, uint256 volume, uint256 amount);
    event Withdrawn(address indexed referrer, uint256 amount);
    event CreditorSet(address indexed creditor, bool allowed);

    constructor(address owner_) Ownable(owner_) {}

    modifier onlyCreditor() {
        require(isCreditor[msg.sender], "ReferralRegistry: not a creditor");
        _;
    }

    function registerCode(bytes32 code_) external {
        require(referrerOf[msg.sender].code == bytes32(0), "ReferralRegistry: already registered");
        require(ownerOfCode[code_] == address(0), "ReferralRegistry: code taken");
        referrerOf[msg.sender].code = code_;
        ownerOfCode[code_] = msg.sender;
        emit CodeRegistered(msg.sender, code_);
    }

    /// @notice Called by an authorized curve/fee router when a trade under a
    ///         referral code settles. `amount` is the referrer's share of the
    ///         fee, already computed and sent as msg.value.
    function credit(address referrer, uint256 volume) external payable onlyCreditor nonReentrant {
        Referrer storage r = referrerOf[referrer];
        require(r.code != bytes32(0), "ReferralRegistry: not registered");
        r.lifetimeVolume += volume;
        r.accrued += msg.value;
        emit Credited(referrer, volume, msg.value);
    }

    function withdraw() external nonReentrant {
        uint256 amount = referrerOf[msg.sender].accrued;
        require(amount > 0, "ReferralRegistry: nothing to withdraw");
        referrerOf[msg.sender].accrued = 0;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "ReferralRegistry: withdraw failed");
        emit Withdrawn(msg.sender, amount);
    }

    function tierOf(address referrer) external view returns (uint16 shareBps) {
        uint256 volume = referrerOf[referrer].lifetimeVolume;
        for (uint256 i = tierThresholds.length; i > 0; i--) {
            if (volume >= tierThresholds[i - 1]) {
                return tierShareBps[i - 1];
            }
        }
        return 0;
    }

    function setTiers(uint256[] calldata thresholds_, uint16[] calldata shareBps_) external onlyOwner {
        require(thresholds_.length == shareBps_.length, "ReferralRegistry: length mismatch");
        tierThresholds = thresholds_;
        tierShareBps = shareBps_;
    }

    function setCreditor(address creditor_, bool allowed_) external onlyOwner {
        isCreditor[creditor_] = allowed_;
        emit CreditorSet(creditor_, allowed_);
    }
}
