// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LuxyToken} from "./LuxyToken.sol";
import {LuxyCurve} from "./LuxyCurve.sol";

/// @title LuxyFactory — Deploys token + curve in one transaction
/// @notice Governance sets fee recipient and default curve params.
///         Anyone can deploy, one signature only.
contract LuxyFactory {
    // Default curve parameters
    uint256 public defaultP0 = 1e12;          // 0.000001 ETH per token
    uint256 public defaultDeltaP = 1e8;       // steepness
    uint256 public defaultTargetETH = 3.96 ether;

    address public feeRecipient;
    address public governance;

    // Track all deployed tokens
    LuxyToken[] public tokens;
    mapping(address => bool) public isLuxyToken;

    event TokenDeployed(
        address indexed token,
        address indexed curve,
        address indexed creator,
        string name,
        string symbol
    );

    modifier onlyGovernance() {
        require(msg.sender == governance, "LuxyFactory: only governance");
        _;
    }

    constructor(address _feeRecipient) {
        governance = msg.sender;
        feeRecipient = _feeRecipient;
    }

    /// @notice Deploy a new token + bonding curve in one transaction
    /// @param name Token name
    /// @param symbol Token ticker
    /// @return tokenAddr Address of the deployed token
    /// @return curveAddr Address of the deployed curve
    function deploy(
        string memory name,
        string memory symbol
    ) external returns (address tokenAddr, address curveAddr) {
        return _deploy(name, symbol, defaultP0, defaultDeltaP, defaultTargetETH);
    }

    /// @notice Deploy with custom curve parameters
    function deployCustom(
        string memory name,
        string memory symbol,
        uint256 _P0,
        uint256 _deltaP,
        uint256 _targetETH
    ) external returns (address tokenAddr, address curveAddr) {
        return _deploy(name, symbol, _P0, _deltaP, _targetETH);
    }

    function _deploy(
        string memory name,
        string memory symbol,
        uint256 _P0,
        uint256 _deltaP,
        uint256 _targetETH
    ) internal returns (address tokenAddr, address curveAddr) {
        // Deploy token with no curve set yet
        LuxyToken token = new LuxyToken(
            name,
            symbol,
            address(0),
            address(this)
        );

        LuxyCurve curve = new LuxyCurve(
            address(token),
            _P0,
            _deltaP,
            _targetETH,
            address(this),
            feeRecipient
        );

        // Set the real curve address on the token
        token.setCurve(address(curve));

        tokens.push(token);
        isLuxyToken[address(token)] = true;

        emit TokenDeployed(address(token), address(curve), msg.sender, name, symbol);

        return (address(token), address(curve));
    }

    // ── Governance ──

    function setGovernance(address _gov) external onlyGovernance {
        governance = _gov;
    }

    function setFeeRecipient(address _recipient) external onlyGovernance {
        feeRecipient = _recipient;
    }

    function setDefaultParams(
        uint256 _P0,
        uint256 _deltaP,
        uint256 _targetETH
    ) external onlyGovernance {
        defaultP0 = _P0;
        defaultDeltaP = _deltaP;
        defaultTargetETH = _targetETH;
    }

    function tokenCount() external view returns (uint256) {
        return tokens.length;
    }
}
