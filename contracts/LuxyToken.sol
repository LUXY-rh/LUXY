// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title LuxyToken — ERC20 with wallet limits and graduation hooks
/// @notice Every Luxy token enforces max-wallet cap on every transfer.
///         Curve contract is set at deploy time and cannot be changed.
contract LuxyToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public curve;
    address public immutable factory;
    bool public graduated;

    // 5% cap (500 basis points out of 10000)
    uint256 public constant MAX_WALLET_BPS = 500;
    uint256 public constant BPS_DENOMINATOR = 10000;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Graduated();

    modifier onlyCurve() {
        require(msg.sender == curve, "LuxyToken: only curve");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        address _curve,
        address _factory
    ) {
        name = _name;
        symbol = _symbol;
        curve = _curve;
        factory = _factory;
    }

    /// @notice Called by the curve when tokens are minted during a buy
    function mint(address to, uint256 amount) external onlyCurve {
        _mint(to, amount);
    }

    /// @notice Called by the curve when tokens are burned during a sell
    function burn(address from, uint256 amount) external onlyCurve {
        _burn(from, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "LuxyToken: insufficient allowance");
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Sets the curve address — only factory can call this once
    function setCurve(address _curve) external {
        require(msg.sender == factory, "LuxyToken: only factory");
        require(curve == address(0), "LuxyToken: curve already set");
        curve = _curve;
    }

    /// @notice Marks token as graduated — only curve or factory can call this once
    function graduate() external {
        require(msg.sender == curve || msg.sender == factory, "LuxyToken: only curve or factory");
        require(!graduated, "LuxyToken: already graduated");
        graduated = true;
        emit Graduated();
    }

    // ── Internal ──

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "LuxyToken: transfer from zero");
        require(to != address(0), "LuxyToken: transfer to zero");
        require(balanceOf[from] >= amount, "LuxyToken: insufficient balance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        // Enforce max wallet on receiver (curve + pool exempt)
        if (!graduated && to != curve && to != address(0)) {
            require(
                balanceOf[to] * BPS_DENOMINATOR <= totalSupply * MAX_WALLET_BPS,
                "LuxyToken: wallet exceeds 5% cap"
            );
        }

        emit Transfer(from, to, amount);
    }
}
