// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

/**
 * @title Vault
 * @author Cashflowapp Team
 * @notice Automated liquidity management vault for Algebra pools that supports:
 * - Single and dual token deposits/withdrawals (zap functionality)
 * - Concentrated liquidity position management
 * - Merkl farming integration for reward earning
 * - Automated harvesting and compound rewards via multicall
 * - Platform fee collection on rewards (basis points system)
 * - MATIC/WMATIC handling for seamless user experience
 * @dev This contract manages concentrated liquidity positions in Algebra pools, allowing users to deposit tokens,
 * participate in Merkl farming, and benefit from automated reward compounding. It issues ERC20 vault tokens
 * representing shares in the vault. The vault uses multicall functionality for advanced reward compounding
 * strategies executed by whitelisted addresses. Public addLiquidity functions are intended ONLY for
 * internal use via multicall for reward compounding - users should use zapIn functions instead.
 *
 * Key Features:
 * - ERC20 vault token mechanics with share-based accounting
 * - Algebra V3 integration with concentrated liquidity positions
 * - Merkl distributor integration for earning protocol rewards
 * - Single-token zap functionality with automatic optimal swapping
 * - Dual-token deposits with slippage protection
 * - Reentrancy protection on all external functions
 * - SafeERC20 usage for secure token operations
 * - Basis points fee system for precise fee management
 * - Multicall whitelist system for authorized compound operations
 * - NFT position management through Algebra's position manager
 * - Automated fee collection from liquidity positions
 * - WMATIC wrapping/unwrapping for native MATIC support
 */
import "@cryptoalgebra/periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@cryptoalgebra/periphery/contracts/interfaces/ISwapRouter.sol";
import "@cryptoalgebra/core/contracts/interfaces/IAlgebraPool.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/common/IWMATIC.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IMerklDistributor.sol";
import "./libraries/Swap.sol";
import "./libraries/Liquidity.sol";
import "forge-std/console.sol";

contract Vault is IVault, ERC20, ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // =========================================================================
    // State Variables
    // =========================================================================

    /// @notice Platform fee percentage in basis points (1 bps = 0.01%, max 2000 = 20%)
    uint256 public platformFeePercentage = 500; // 5%

    /// @notice Algebra NFT position manager contract address
    address public immutable nonfungiblePositionManager = 0x8eF88E4c7CfbbaC1C163f7eddd4B578792201de6;

    /// @notice Wrapped MATIC token address
    address public immutable wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    /// @notice Algebra router contract address
    address public immutable router = 0xf5b509bB0909a69B1c207E495f687a596C168E12;

    /// @notice Algebra pool address this vault interacts with
    address public pool;

    /// @notice Lower tick bound of the liquidity position
    int24 public tickLower;

    /// @notice Upper tick bound of the liquidity position
    int24 public tickUpper;

    /// @notice NFT token ID of vault's liquidity position
    uint256 public tokenId;

    /// @notice Pool's token0 address
    address public token0;

    /// @notice Pool's token1 address
    address public token1;

    /// @notice protocol fee receiver address
    address public feeReceiver;

    /// @notice Mapping of addresses whitelisted for multicall functionality
    mapping(address => bool) public multicallWhitelist;

    // =========================================================================
    // Events
    // =========================================================================

    /// @notice Emitted when tokens are deposited into the vault
    event Deposited(address indexed user, uint256 amount0, uint256 amount1, uint256 shareAmount);

    /// @notice Emitted when tokens are withdrawn from the vault
    event Withdrawn(uint256 shareAmount, address indexed user, uint256 amount0, uint256 amount1);

    /// @notice Emitted when fees are collected from the position
    event FeeCollected(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    /// @notice Emitted when platform fees are deducted
    event FeeDeducted(address indexed token, uint256 amount);

    /// @notice Emitted when multicall whitelist is updated
    event MulticallWhitelistUpdated(address indexed target, bool allowed);

    /// @notice Emitted when token approval is set
    event ApprovalSet(address indexed token, address indexed spender, uint256 amount);

    /// @notice Emitted when multicall is executed
    event Multicall(address[] targets, bytes[] data);

    /// @notice Emitted when platform fee percentage is updated
    event FeePercentageUpdated(uint256 newFeeBps);

    /// @notice Emitted when protocol fee receiver address updated
    event UpdatedFeeReceiver(address indexed feeReceiver);

    // =========================================================================
    // Constructor
    // =========================================================================

    /**
     * @notice Initialize the vault with name, symbol and management addresses
     * @param _name Name of vault's LP token
     * @param _symbol Symbol of vault's LP token
     * @param _owner Owner address for admin functions
     */
    constructor(string memory _name, string memory _symbol, address _owner, address _feeReceiver)
        ERC20(_name, _symbol)
        Ownable()
    {
        transferOwnership(_owner);
        feeReceiver = _feeReceiver;
    }

    // =========================================================================
    // Receive Function
    // =========================================================================

    /**
     * @notice Allow contract to receive ETH
     * @dev Required for WMATIC unwrapping functionality
     */
    receive() external payable {}

    // =========================================================================
    // External Functions
    // =========================================================================

    /**
     * @notice Handle receipt of ERC721 token (position NFT)
     * @dev Required to receive NFT from position manager
     * @return bytes4 ERC721 receive selector
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice Initialize vault by creating the first liquidity position
     * @dev Can only be called once. Sets up the vault's pool, tokens, and initial position
     * @param amount0 Amount of token0 to deposit
     * @param amount1 Amount of token1 to deposit
     * @param amount0Min Minimum token0 amount to accept (slippage protection)
     * @param amount1Min Minimum token1 amount to accept (slippage protection)
     * @param _tickLower Lower tick bound of position
     * @param _tickUpper Upper tick bound of position
     * @param _pool Address of the Algebra pool
     */
    function initializeVault(
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min,
        int24 _tickLower,
        int24 _tickUpper,
        address _pool
    ) external payable override {
        require(amount0Min > 0 && amount1Min > 0, "ZA");
        require(pool == address(0), "vault already initialized");

        // Set pool and token addresses
        pool = _pool;
        token0 = IAlgebraPool(_pool).token0();
        token1 = IAlgebraPool(_pool).token1();
        tickLower = _tickLower;
        tickUpper = _tickUpper;
        console.log(token0);
        console.log(token1);
        // Handle token payments (including WMATIC wrapping if needed)
        _pay(token0, amount0);
        _pay(token1, amount1);

        // Approve tokens for position manager and router
        IERC20(token0).safeApprove(nonfungiblePositionManager, uint256(type(uint256).max));
        IERC20(token1).safeApprove(nonfungiblePositionManager, uint256(type(uint256).max));
        IERC20(token0).safeApprove(router, uint256(type(uint256).max));
        IERC20(token1).safeApprove(router, uint256(type(uint256).max));

        // Create initial liquidity position
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 _tokenId,, uint256 _amount0, uint256 _amount1) =
            INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
        tokenId = _tokenId;

        // Refund any unused tokens
        uint256 token0Left = amount0 - _amount0;
        uint256 token1Left = amount1 - _amount1;
        if (token0Left > 0) _refund(msg.sender, token0, token0Left);
        if (token1Left > 0) _refund(msg.sender, token1, token1Left);

        // Mint initial shares (burn to dead address to prevent zero supply issues)
        uint256 _shareAmount = Swap.sqrt(_amount0.mul(_amount1));
        _mint(0x000000000000000000000000000000000000dEaD, _shareAmount);
        emit Deposited(msg.sender, amount0, amount1, _shareAmount);
    }

    /**
     * @notice Set or unset an address as whitelisted for multicall
     * @dev Only owner can call this function
     * @param target The address to whitelist or remove
     * @param allowed True to whitelist, false to remove
     */
    function setMulticallWhitelist(address target, bool allowed) external override onlyOwner {
        require(target != address(nonfungiblePositionManager), "NA");
        require(target != address(0), "ZA");
        multicallWhitelist[target] = allowed;
        emit MulticallWhitelistUpdated(target, allowed);
    }

    /**
     * @notice Update the platform fee percentage in basis points
     * @dev Only owner can call this function. 1 bps = 0.01%, max 2000 bps = 20%
     * @param _platformFeeBps New fee in basis points (max 2000)
     */
    function updateFeePercentage(uint256 _platformFeeBps) external override onlyOwner {
        require(_platformFeeBps <= 2000, "Max 20% (2000 bps)");
        platformFeePercentage = _platformFeeBps;
        emit FeePercentageUpdated(_platformFeeBps);
    }

    /**
     * @notice update protocol fee receiver address
     * @param _feeReceiver new fee receiver address
     */
    function updateFeeReceiverAddress(address _feeReceiver) external override onlyOwner {
        feeReceiver = _feeReceiver;
        emit UpdatedFeeReceiver(_feeReceiver);
    }

    /**
     * @notice Approve a spender for a given token
     * @dev Only owner can call this function
     * @param token Token address to approve
     * @param spender Spender address to approve
     * @param amount Amount to approve
     */
    function approve(address token, address spender, uint256 amount) external override onlyOwner {
        IERC20(token).safeApprove(spender, amount);
        emit ApprovalSet(token, spender, amount);
    }

    /**
     * @notice Deposit both tokens into the vault and mint LP shares
     * @dev Requires both tokens to be provided in the correct ratio
     * @param recipient Address to receive LP shares
     * @param amount0 Amount of token0 to deposit
     * @param amount1 Amount of token1 to deposit
     * @param amount0Min Minimum token0 to accept (slippage protection)
     * @param amount1Min Minimum token1 to accept (slippage protection)
     * @return _shareAmount Amount of LP shares minted
     */
    function zapInDual(address recipient, uint256 amount0, uint256 amount1, uint256 amount0Min, uint256 amount1Min)
        external
        payable
        override
        nonReentrant
        returns (uint256 _shareAmount)
    {
        require(amount0Min > 0 && amount1Min > 0, "ZA");
        require(amount0 > 0 && amount1 > 0, "ZA");

        address _token0 = token0;
        address _token1 = token1;

        // Handle token payments
        _pay(_token0, amount0);
        _pay(_token1, amount1);

        // Add liquidity to position
        (uint256 _amount0, uint256 _amount1) = addLiquidity(amount0, amount1, amount0Min, amount1Min);

        // Refund any unused tokens
        uint256 token0Left = amount0 - _amount0;
        uint256 token1Left = amount1 - _amount1;
        if (token0Left > 0) _refund(recipient, _token0, token0Left);
        if (token1Left > 0) _refund(recipient, _token1, token1Left);

        // Calculate and mint shares
        _shareAmount = calculateShareAmount(_amount0, _amount1);
        _mint(recipient, _shareAmount);
        emit Deposited(recipient, _amount0, _amount1, _shareAmount);
    }

    /**
     * @notice Deposit a single token, swap for optimal ratio, and mint LP shares
     * @dev Automatically swaps part of the input token to achieve optimal ratio
     * @param recipient Address to receive LP shares
     * @param tokenIn Input token address (must be token0 or token1)
     * @param amountIn Amount of input token
     * @param amountOutMin Minimum output from swap (slippage protection)
     * @param amount0Min Minimum token0 to accept for liquidity addition
     * @param amount1Min Minimum token1 to accept for liquidity addition
     * @return _shareAmount Amount of LP shares minted
     */
    function zapInSingle(
        address recipient,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable override nonReentrant returns (uint256 _shareAmount) {
        address _token0 = token0;
        address _token1 = token1;
        require(tokenIn == _token1 || tokenIn == _token0, "TNS");
        require(amountOutMin > 0 && amountIn > 0, "ZA");

        // Handle token payment
        _pay(tokenIn, amountIn);
        console.log("Amount in:", amountIn);
        // Calculate optimal swap and execute
        (uint256 amount0, uint256 amount1) = _getOptimalDualAssets(tokenIn, _token0, _token1, amountIn, amountOutMin);
        console.log("amount0", amount0);
        console.log("amount1", amount1);
        // Add liquidity to position
        (uint256 _amount0, uint256 _amount1) = addLiquidity(amount0, amount1, amount0Min, amount1Min);
        console.log("_amount0", _amount0);
        console.log("_amount1", _amount1);
        // Refund any unused tokens
        uint256 token0Left = amount0 - _amount0;
        uint256 token1Left = amount1 - _amount1;
        console.log("token0Left", token0Left);
        console.log("token1Left", token1Left);
        if (token0Left > 0) _refund(recipient, _token0, token0Left);
        if (token1Left > 0) _refund(recipient, _token1, token1Left);

        // Calculate and mint shares
        _shareAmount = calculateShareAmount(_amount0, _amount1);
        _mint(recipient, _shareAmount);
        emit Deposited(recipient, _amount0, _amount1, _shareAmount);
    }

    /**
     * @notice Withdraw liquidity from the vault and burn LP shares
     * @dev Burns user's LP shares and returns proportional amounts of both tokens
     * @param amount Amount of LP shares to burn
     * @param amount0Min Minimum token0 to receive (slippage protection)
     * @param amount1Min Minimum token1 to receive (slippage protection)
     * @return amount0 Amount of token0 withdrawn
     * @return amount1 Amount of token1 withdrawn
     */
    function zapOut(uint128 amount, uint256 amount0Min, uint256 amount1Min)
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        require(amount0Min > 0 && amount1Min > 0, "ZA");
        (amount0, amount1) = _removeLiquidity(calculateWithdrawShare(amount), amount0Min, amount1Min, msg.sender);
        _burn(msg.sender, amount);
        emit Withdrawn(amount, msg.sender, amount0, amount1);
    }

    /**
     * @notice Withdraw liquidity and swap to a single desired token
     * @dev Burns LP shares, withdraws liquidity, and swaps one token for the desired token
     * @param amount Amount of LP shares to burn
     * @param amount0Min Minimum token0 to receive from liquidity withdrawal
     * @param amount1Min Minimum token1 to receive from liquidity withdrawal
     * @param desiredToken Token to receive after swap (must be token0 or token1)
     * @param amountOutMin Minimum output from swap (slippage protection)
     */
    function zapOutAndSwap(
        uint128 amount,
        uint256 amount0Min,
        uint256 amount1Min,
        address desiredToken,
        uint256 amountOutMin
    ) external override nonReentrant {
        address _token0 = token0;
        address _token1 = token1;
        require(amount0Min > 0 && amount1Min > 0, "ZA");
        require(desiredToken == _token0 || desiredToken == _token1, "TNS");

        // Remove liquidity to this contract
        (uint256 _amount0, uint256 _amount1) =
            _removeLiquidity(calculateWithdrawShare(amount), amount0Min, amount1Min, address(this));

        // Swap unwanted token for desired token and transfer total to user
        IERC20(desiredToken).safeTransfer(
            msg.sender,
            _swap(
                _token0 == desiredToken ? _token1 : _token0,
                desiredToken,
                desiredToken == _token0 ? _amount1 : _amount0,
                amountOutMin
            ) + (desiredToken == _token0 ? _amount0 : _amount1)
        );

        _burn(msg.sender, amount);
        emit Withdrawn(amount, msg.sender, _amount0, _amount1);
    }

    /**
     * @notice Set the address allowed to claim farming rewards
     * @dev Only owner can call this function
     * @param rewardDistributor Merkl distributor contract address
     * @param claimer Address to set as operator for reward claiming
     */
    function setFarmingRewardClaimer(address rewardDistributor, address claimer) external override onlyOwner {
        IMerklDistributor(rewardDistributor).toggleOperator(address(this), claimer);
    }

    /**
     * @notice Claim farming rewards from Merkl distributor
     * @dev Only owner can call this function
     * @param users Array of user addresses
     * @param tokens Array of token addresses
     * @param amounts Array of amounts to claim
     * @param proofs Array of Merkle proofs
     * @param rewardDistributor Merkl distributor contract address
     */
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address rewardDistributor
    ) external override onlyOwner {
        IMerklDistributor(rewardDistributor).claim(users, tokens, amounts, proofs);
    }

    /**
     * @notice Collect fees from the position NFT
     * @dev Collects all available fees from the liquidity position
     */
    function collectFees() external override {
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: uint128(type(uint128).max),
            amount1Max: uint128(type(uint128).max)
        });
        (uint256 amount0, uint256 amount1) =
            INonfungiblePositionManager(nonfungiblePositionManager).collect(collectParams);
        emit FeeCollected(tokenId, amount0, amount1);
    }

    /**
     * @notice Multicall for batch execution of whitelisted contract calls
     * @dev Only whitelisted addresses can call this function. Used for complex operations like reward compounding
     * @param targets The contract addresses to call
     * @param data The calldata for each call
     * @return results The return data from each call
     */
    function multicall(address[] calldata targets, bytes[] calldata data)
        external
        override
        nonReentrant
        returns (bytes[] memory results)
    {
        require(targets.length == data.length, "length mismatch");
        require(multicallWhitelist[msg.sender], "NotWhitelisted");

        results = new bytes[](targets.length);
        for (uint256 i = 0; i < targets.length; ++i) {
            require(multicallWhitelist[targets[i]], "NotWhitelisted");
            (bool success, bytes memory result) = targets[i].call(data[i]);
            if (!success) revert("MulticallSubcallFailed");
            results[i] = result;
        }
        emit Multicall(targets, data);
    }

    /**
     * @notice Deduct platform fees from token balance in basis points
     * @dev Can only be called by the contract itself (typically through multicall)
     * @param token Token address to deduct fees from
     */
    function deductFees(address token) external override {
        require(msg.sender == address(this), "NA");
        uint256 feesAmount = (IERC20(token).balanceOf(address(this)) * platformFeePercentage) / 10000;
        IERC20(token).safeTransfer(feeReceiver, feesAmount);
        emit FeeDeducted(token, feesAmount);
    }

    // =========================================================================
    // Public Functions
    // =========================================================================

    /**
     * @notice Add liquidity to the vault's position
     * @dev WARNING: This function is intended ONLY for reward compounding through multicall.
     *      Users should NOT call this directly - use zapInDual or zapInSingle instead.
     *      This function is public to allow multicall operations for automated reward compounding.
     * @param amount0 Amount of token0 to add
     * @param amount1 Amount of token1 to add
     * @param amount0Min Minimum token0 to add (slippage protection)
     * @param amount1Min Minimum token1 to add (slippage protection)
     * @return _amount0 Actual amount of token0 added
     * @return _amount1 Actual amount of token1 added
     */
    function addLiquidity(uint256 amount0, uint256 amount1, uint256 amount0Min, uint256 amount1Min)
        public
        returns (uint256 _amount0, uint256 _amount1)
    {
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = INonfungiblePositionManager
            .IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp
        });
        (, _amount0, _amount1) =
            INonfungiblePositionManager(nonfungiblePositionManager).increaseLiquidity(increaseLiquidityParams);
    }

    /**
     * @notice Calculate the amount of LP shares to mint for a given deposit
     * @dev Uses proportional share calculation based on current reserves
     * @param amount0 Amount of token0 deposited
     * @param amount1 Amount of token1 deposited
     * @return share Amount of LP shares to mint
     */
    function calculateShareAmount(uint256 amount0, uint256 amount1) public view returns (uint256 share) {
        uint256 supply = totalSupply();
        (uint256 res0, uint256 res1) = getReservers();
        share = Math.min(amount0.mul(supply) / (res0.sub(amount0)), amount1.mul(supply) / (res1.sub(amount1)));
    }

    /**
     * @notice Calculate the share of liquidity to withdraw for a given LP amount
     * @dev Calculates proportional liquidity based on LP token ownership
     * @param amount Amount of LP shares to burn
     * @return liquidityShare Amount of liquidity to withdraw
     */
    function calculateWithdrawShare(uint128 amount) public view returns (uint128 liquidityShare) {
        (,,,,,, uint128 liquidity,,,,) = INonfungiblePositionManager(nonfungiblePositionManager).positions(tokenId);
        liquidityShare = (liquidity * amount) / uint128(totalSupply());
    }

    /**
     * @notice Get the current reserves of token0 and token1 in the vault's position
     * @dev Returns the current token amounts that would be received if all liquidity was withdrawn
     * @return res0 Reserve of token0
     * @return res1 Reserve of token1
     */
    function getReservers() public view returns (uint256 res0, uint256 res1) {
        (res0, res1) = Liquidity.getAmountsForLiquidity(pool, nonfungiblePositionManager, tokenId, tickLower, tickUpper);
    }

    // =========================================================================
    // Internal Functions
    // =========================================================================

    /**
     * @notice Remove liquidity from position and collect tokens
     * @dev Internal function to handle liquidity removal and token collection
     * @param amount Liquidity amount to remove
     * @param amount0Min Minimum token0 to receive
     * @param amount1Min Minimum token1 to receive
     * @param to Recipient address for withdrawn tokens
     * @return amount0 Amount of token0 withdrawn
     * @return amount1 Amount of token1 withdrawn
     */
    function _removeLiquidity(uint128 amount, uint256 amount0Min, uint256 amount1Min, address to)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        // Decrease liquidity in the position
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: amount,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp
        });
        (amount0, amount1) =
            INonfungiblePositionManager(nonfungiblePositionManager).decreaseLiquidity(decreaseLiquidityParams);

        // Collect the tokens from the position
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: to,
            amount0Max: uint128(amount0),
            amount1Max: uint128(amount1)
        });
        (amount0, amount1) = INonfungiblePositionManager(nonfungiblePositionManager).collect(collectParams);
    }

    /**
     * @notice Internal function to swap tokens using the Algebra router
     * @dev Executes a single token swap with slippage protection
     * @param tokenIn Input token address
     * @param _tokenOut Output token address
     * @param amountIn Amount of input token
     * @param amountOutMin Minimum output amount (slippage protection)
     * @return Amount of output token received
     */
    function _swap(address tokenIn, address _tokenOut, uint256 amountIn, uint256 amountOutMin)
        internal
        returns (uint256)
    {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: _tokenOut,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            limitSqrtPrice: 0
        });
        return ISwapRouter(router).exactInputSingle(params);
    }

    /**
     * @notice Calculate optimal token split for single-token entry
     * @dev Determines how much of the input token to swap to achieve optimal liquidity ratio
     * @param tokenIn Input token address
     * @param _token0 Pool token0 address
     * @param _token1 Pool token1 address
     * @param amountIn Total input amount
     * @param amountOutMin Minimum swap output
     * @return amount0 Amount of token0 after swap
     * @return amount1 Amount of token1 after swap
     */
    function _getOptimalDualAssets(
        address tokenIn,
        address _token0,
        address _token1,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amount0, uint256 amount1) {
        address _pool = pool;
        (,, uint16 _fee,,,,) = IAlgebraPool(_pool).globalState();

        // Calculate optimal amount to swap
        uint256 _amountToSwap = _token0 == tokenIn
            ? Swap.calculateSwapInAmount(IERC20(_token0).balanceOf(_pool), amountIn, _fee)
            : Swap.calculateSwapInAmount(IERC20(_token1).balanceOf(_pool), amountIn, _fee);

        // Execute swap and set amounts
        if (_token0 == tokenIn) {
            amount0 = amountIn.sub(_amountToSwap);
            amount1 = _swap(tokenIn, _token1, _amountToSwap, amountOutMin);
        } else {
            amount0 = _swap(tokenIn, _token0, _amountToSwap, amountOutMin);
            amount1 = amountIn.sub(_amountToSwap);
        }
    }

    /**
     * @notice Internal function to handle token payments (including WMATIC wrapping)
     * @dev Handles both ERC20 transfers and ETH payments (wrapping to WMATIC)
     * @param _token Token address
     * @param _amount Amount to pay
     */
    function _pay(address _token, uint256 _amount) internal {
        if (_token == wmatic && msg.value > 0) {
            require(msg.value == _amount, "Incorrect value sent");
            IWMATIC(_token).deposit{value: _amount}();
        } else {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }

    /**
     * @notice Refund tokens to user, unwrapping WMATIC to ETH if needed
     * @dev Handles both ERC20 transfers and ETH refunds (unwrapping WMATIC)
     * @param _to Recipient address
     * @param _token Token to refund
     * @param _amount Amount to refund
     */
    function _refund(address _to, address _token, uint256 _amount) internal {
        if (_token == wmatic && msg.value > 0) {
            IWMATIC(_token).withdraw(_amount);
            (bool success,) = _to.call{value: _amount}("");
            require(success, "ETH refund failed");
        } else {
            IERC20(_token).safeTransfer(_to, _amount);
        }
    }
}
