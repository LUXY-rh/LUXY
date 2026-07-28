// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LuxyToken} from "./LuxyToken.sol";
import {LuxyCurve} from "./LuxyCurve.sol";

/// @title LuxyFactory
/// @notice Deploys a LuxyToken + LuxyCurve pair atomically in one signature,
///         maintains the on-chain deployment registry (for the indexer to
///         read), and holds the governance knobs described in the docs:
///         launch pausing, gated-mode allowlist, and per-launch fee ceiling.
contract LuxyFactory is Ownable {
    uint256 public constant DEFAULT_TOTAL_SUPPLY = 1_000_000_000 ether; // 1e9 tokens, 18 decimals
    uint256 public constant DEFAULT_TARGET = 3.96 ether;
    uint256 public constant DEFAULT_FEE_BPS = 100; // 1%
    uint256 public constant MAX_FEE_BPS_LOCAL = 500; // 5% hard ceiling

    address public graduationRouter;
    bool public launchesPaused;
    bool public gatedMode;
    mapping(address => bool) public allowedDeployers;
    mapping(address => bool) public blocked; // access-control layer: wallets blocked from trading

    struct Deployment {
        address token;
        address curve;
        address creator;
        uint256 deployedAt;
    }

    Deployment[] public deployments;
    mapping(address => uint256) public curveIndexByToken; // token => index+1 in deployments (0 = none)

    event LaunchDeployed(address indexed token, address indexed curve, address indexed creator, string name, string symbol);
    event LaunchesPausedSet(bool paused);
    event GatedModeSet(bool gated);
    event DeployerAllowed(address indexed who, bool allowed);
    event WalletBlocked(address indexed who, bool blocked_);

    error Paused();
    error NotAllowed();
    error FeeTooHigh();

    constructor(address graduationRouter_) Ownable(msg.sender) {
        graduationRouter = graduationRouter_;
    }

    modifier canDeploy() {
        if (launchesPaused) revert Paused();
        if (gatedMode && !allowedDeployers[msg.sender]) revert NotAllowed();
        _;
    }

    /// @notice One-signature deploy: creates the token (minted fully to the curve)
    ///         and its bonding curve contract in a single call.
    function deploy(
        string calldata name_,
        string calldata symbol_,
        uint256 feeBps_
    ) external canDeploy returns (address tokenAddr, address curveAddr) {
        if (feeBps_ > MAX_FEE_BPS_LOCAL) revert FeeTooHigh();

        // Precompute curve address via CREATE would need CREATE2; for simplicity
        // deploy curve first with a placeholder, then token, then wire back.
        // Two-step deploy kept atomic within a single external call.
        LuxyCurveDeployer helper = new LuxyCurveDeployer();
        (tokenAddr, curveAddr) = helper.deployPair(
            name_,
            symbol_,
            DEFAULT_TOTAL_SUPPLY,
            _curveP0(),
            _curveDeltaP(),
            DEFAULT_TARGET,
            feeBps_,
            graduationRouter
        );

        uint256 idx = deployments.length;
        deployments.push(Deployment(tokenAddr, curveAddr, msg.sender, block.timestamp));
        curveIndexByToken[tokenAddr] = idx + 1;

        emit LaunchDeployed(tokenAddr, curveAddr, msg.sender, name_, symbol_);
    }

    function deploymentsCount() external view returns (uint256) {
        return deployments.length;
    }

    function _curveP0() internal pure returns (uint256) {
        return 1e12; // starting price in wei per token, WAD-scaled; tune before deploy
    }

    function _curveDeltaP() internal pure returns (uint256) {
        return 1e3; // curve steepness; tune so target reserve is hit near expected supply
    }

    // --- Governance (docs: "Governance" administrative scope) ---

    function setLaunchesPaused(bool paused) external onlyOwner {
        launchesPaused = paused;
        emit LaunchesPausedSet(paused);
    }

    function setGatedMode(bool gated) external onlyOwner {
        gatedMode = gated;
        emit GatedModeSet(gated);
    }

    function setAllowedDeployer(address who, bool allowed) external onlyOwner {
        allowedDeployers[who] = allowed;
        emit DeployerAllowed(who, allowed);
    }

    function setBlocked(address who, bool blocked_) external onlyOwner {
        blocked[who] = blocked_;
        emit WalletBlocked(who, blocked_);
    }

    function setGraduationRouter(address router) external onlyOwner {
        graduationRouter = router;
    }
}

/// @dev Tiny one-shot helper that deploys the curve, then the token (minted
///      to itself), then wires them together — all inside a single external
///      call, so LuxyFactory.deploy() is genuinely one signature end to end.
contract LuxyCurveDeployer {
    function deployPair(
        string calldata name_,
        string calldata symbol_,
        uint256 totalSupply_,
        uint256 p0_,
        uint256 dP_,
        uint256 target_,
        uint256 feeBps_,
        address graduationRouter_
    ) external returns (address tokenAddr, address curveAddr) {
        LuxyCurve curve = new LuxyCurve(p0_, dP_, target_, feeBps_, graduationRouter_);
        LuxyToken tok = new LuxyToken(name_, symbol_, totalSupply_, address(this));

        tok.initCurve(address(curve));   // forwards full supply to the curve
        curve.setToken(address(tok));    // wires the curve's token reference

        return (address(tok), address(curve));
    }
}
