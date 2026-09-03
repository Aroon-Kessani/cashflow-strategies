// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// --- Balancer and OpenZeppelin imports for DeFi operations and security ---
import "../lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/ICompositeLiquidityRouter.sol";
import "../lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IRouter.sol";
import "../lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IBatchRouter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IGauge.sol";
import "./interfaces/INative.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/balancer-v3-monorepo/pkg/interfaces/contracts/pool-utils/IPoolInfo.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IWRAPPED.sol";
import "./interfaces/IPermit2.sol";
import "./interfaces/IpesudoMinter.sol";

/**
 * @title Vault
 * @author Cashflowapp Team
 * @notice Automated liquidity management vault for Balancer pools that supports:
 * - Proportional and unbalanced token deposits/withdrawals
 * - Gauge staking for reward earning
 * - Automated harvesting and compound rewards via multicall
 * - Platform fee collection on rewards
 * - ETH/WETH handling for seamless user experience
 * @dev This contract manages liquidity in Balancer pools, allowing users to deposit tokens,
 * participate in gauge farming, and benefit from automated reward compounding. It issues ERC20 vault tokens
 * representing shares in the vault. The vault uses multicall functionality for advanced reward compounding
 * strategies executed by whitelisted addresses. Public addLiquidity functions are intended ONLY for
 * internal use via multicall for reward compounding - users should use deposit functions instead.
 *
 * Key Features:
 * - ERC4626-like vault mechanics with share-based accounting
 * - Balancer V3 integration with composite liquidity router
 * - Gauge integration for earning BAL and other rewards
 * - Permit2 support for gasless approvals
 * - Reentrancy protection on all external functions
 * - SafeERC20 usage for secure token operations
 * - Platform fee mechanism for sustainable operations
 */
contract Vault is IVault, ERC20, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // --- Constants and Immutables ---

    /// @notice Platform fee in basis points (e.g., 500 = 5%)
    uint256 public platformFeePercentage = 500;

    /// @notice Balancer router for liquidity operations
    ICompositeLiquidityRouter public immutable router;

    /// @notice Gauge for staking pool tokens and earning rewards
    IGauge public immutable gauge;

    /// @notice Minter for additional rewards
    IpesudoMinter public immutable pesudoMinter;

    /// @notice Balancer pool address
    address public immutable pool;

    /// @notice Underlying tokens in the pool
    IERC20[] public poolTokens;

    /// @notice Native token (e.g., WETH)
    address public immutable nativeToken;

    /// @notice Router for batch swaps
    IBatchRouter public immutable batchRouter;

    /// @notice protocol fee receiver address
    address public feeReceiver;

    /// @notice Access control for multicall
    mapping(address => bool) public multicallWhitelist;

    // --- Events ---

    /// @notice Emitted when a token approval is set
    event Approve(
        address indexed token,
        address indexed spender,
        uint256 amount
    );

    /// @notice Emitted when a Permit2 approval is set
    event Permit2Approve(
        address indexed permit2,
        address indexed token,
        address indexed spender,
        uint160 amount,
        uint48 expiration
    );

    /// @notice Emitted when the multicall whitelist is updated
    event MulticallWhitelistUpdated(address indexed target, bool allowed);

    /// @notice Emitted when the platform fee percentage is updated
    event FeePercentageUpdated(uint256 newFeePercentage);

    /// @notice Emitted when a deposit is made
    event Deposit(
        address indexed sender,
        address indexed recipient,
        uint256 bptAmount,
        uint256 shareAmount,
        bool proportional,
        uint256[] inputAmounts
    );

    /// @notice Emitted when a withdrawal is made
    event Withdraw(
        address indexed sender,
        uint256 sharesBurned,
        address[] tokensOut,
        uint256[] amountsOut
    );

    /// @notice Emitted when a multicall is executed
    event Multicall(address[] targets, bytes[] data);

    /// @notice Emitted when fees are deducted
    event FeeDeducted(address indexed token, uint256 amount);

    /// @notice Emitted when protocol fee receiver address updated
    event UpdatedFeeReceiver(address indexed feeReceiver);

    // --- Modifiers ---

    /// @dev Modifier to restrict access to only whitelisted multicall addresses
    modifier onlyWhitelisted() {
        if (!multicallWhitelist[msg.sender]) revert NotWhitelisted(msg.sender);
        _;
    }

    // --- Receive Ether ---

    /// @notice Receive function to accept ETH
    receive() external payable {}

    // --- Constructor ---

    /// @notice Vault constructor sets up all required contract references and approvals
    /// @param _pool Balancer pool address
    /// @param _poolTokens Array of pool token addresses
    /// @param name ERC20 name
    /// @param symbol ERC20 symbol
    /// @param _router Balancer router address
    /// @param _batchRouter Batch router address
    /// @param _nativeToken Native token address (e.g., WETH)
    /// @param _gauge Gauge address for staking
    /// @param _pesudoMinter Pseudo minter address for rewards
    /// @param _permit2 Permit2 contract address
    /// @param _owner Owner address
    constructor(
        address _pool,
        IERC20[] memory _poolTokens,
        string memory name,
        string memory symbol,
        address _router,
        address _batchRouter,
        address _nativeToken,
        address _gauge,
        address _pesudoMinter,
        address _permit2,
        address _owner,
        address _feeReceiver
    ) ERC20(name, symbol) Ownable(_owner) {
        if (
            _pool == address(0) ||
            _router == address(0) ||
            _batchRouter == address(0) ||
            _nativeToken == address(0) ||
            _pesudoMinter == address(0) ||
            _permit2 == address(0) ||
            _owner == address(0) ||
            _feeReceiver == address(0)
        ) revert ZeroAddress();
        if (_poolTokens.length == 0) revert ArrayLengthMismatch();

        pool = _pool;
        router = ICompositeLiquidityRouter(_router);
        gauge = IGauge(_gauge);
        poolTokens = _poolTokens;
        pesudoMinter = IpesudoMinter(_pesudoMinter);
        batchRouter = IBatchRouter(_batchRouter);
        nativeToken = _nativeToken;
        feeReceiver = _feeReceiver;

        // Approve pool tokens and routers for maximum allowance
        if (address(gauge) != address(0)) {
            IERC20(_pool).approve(_gauge, type(uint256).max);
        }
        IERC20(_pool).approve(address(router), type(uint256).max);
        for (uint256 i = 0; i < _poolTokens.length; ++i) {
            address token = address(_poolTokens[i]);
            if (token == address(0)) revert PoolTokenIsZero();
            IERC20(token).approve(_permit2, type(uint256).max);
            IPermit2(_permit2).approve(
                token,
                address(router),
                type(uint160).max,
                type(uint48).max
            );
            IPermit2(_permit2).approve(
                token,
                address(batchRouter),
                type(uint160).max,
                type(uint48).max
            );
            IERC20(token).approve(address(batchRouter), type(uint256).max);
        }
    }

    // --- External Functions ---

    /// @notice Approve a token for a spender (owner only)
    /// @param token The ERC20 token address
    /// @param spender The address allowed to spend the tokens
    /// @param amount The amount to approve
    function approve(
        address token,
        address spender,
        uint256 amount
    ) external override onlyOwner {
        IERC20(token).approve(spender, amount);
        emit Approve(token, spender, amount);
    }

    /// @notice Approve a token for a spender using Permit2 (owner only)
    /// @param permit2 The Permit2 contract address
    /// @param token The ERC20 token address
    /// @param spender The address allowed to spend the tokens
    /// @param amount The amount to approve
    /// @param expiration The expiration timestamp for the approval
    function permit2Approve(
        address permit2,
        address token,
        address spender,
        uint160 amount,
        uint48 expiration
    ) external override onlyOwner {
        IPermit2(permit2).approve(token, spender, amount, expiration);
        emit Permit2Approve(permit2, token, spender, amount, expiration);
    }

    /// @notice Set or unset an address as whitelisted for multicall
    /// @param target The address to whitelist or remove
    /// @param allowed True to whitelist, false to remove
    function setMulticallWhitelist(
        address target,
        bool allowed
    ) external override onlyOwner {
        if (target == address(0)) revert ZeroAddress();
        if (target == address(gauge)) revert GaugeTargetForbidden();
        multicallWhitelist[target] = allowed;
        emit MulticallWhitelistUpdated(target, allowed);
    }

    /// @notice Update the platform fee percentage (owner only)
    /// @param _platformFeePercentage New fee percentage in basis points (max 2000 = 20%)
    function updateFeePercentage(
        uint256 _platformFeePercentage
    ) external override onlyOwner {
        if (_platformFeePercentage > 2000) revert("Max 20% (2000 bps)");
        platformFeePercentage = _platformFeePercentage;
        emit FeePercentageUpdated(_platformFeePercentage);
    }

    /**
     * @notice update protocol fee receiver address
     * @param _feeReceiver new fee receiver address
     */
    function updateFeeReceiverAddress(
        address _feeReceiver
    ) external override onlyOwner {
        feeReceiver = _feeReceiver;
        emit UpdatedFeeReceiver(_feeReceiver);
    }

    /// @notice Deposit tokens in an unbalanced way (custom ratios)
    /// @param recipient The address to receive vault shares
    /// @param wrapUnderlying Array indicating if each token should be wrapped
    /// @param inputAmounts The amounts of each token to deposit
    /// @param minBptAmountOut Minimum BPT to receive from the pool
    /// @param wethIsEth Whether WETH should be treated as ETH
    /// @param userData Additional user data for the router
    /// @return shareAmount Amount of vault shares minted
    function depositUnbalanced(
        address recipient,
        bool[] memory wrapUnderlying,
        uint256[] memory inputAmounts,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable override nonReentrant returns (uint256 shareAmount) {
        _validateDeposit(
            recipient,
            wrapUnderlying,
            inputAmounts,
            minBptAmountOut
        );

        uint256[] memory balancesBefore = _collectAndSnapshot(
            inputAmounts,
            _collectPayment
        );
        // Capture backing before adding liquidity for correct share calculation
        uint256 backingBefore = totalSupply() == 0 ? 0 : (
            address(gauge) != address(0)
                ? IERC20(address(gauge)).balanceOf(address(this))
                : IERC20(pool).balanceOf(address(this))
        );
        uint256 bptAmountOut = addLiquidityUnbalanced(
            wrapUnderlying,
            inputAmounts,
            minBptAmountOut,
            wethIsEth,
            userData,
            msg.value
        );
        shareAmount = calculateDepositShares(bptAmountOut, backingBefore);
        _mint(recipient, shareAmount);
        _refundExcessAll(balancesBefore);
        emit Deposit(
            msg.sender,
            recipient,
            bptAmountOut,
            shareAmount,
            false,
            inputAmounts
        );
    }

    /// @notice Deposit tokens in a proportional way (fixed pool ratio)
    /// @param recipient The address to receive vault shares
    /// @param wrapUnderlying Array indicating if each token should be wrapped
    /// @param maxInputAmounts The max amounts of each token to deposit
    /// @param exactBptAmountOut Exact BPT to receive from the pool
    /// @param wethIsEth Whether WETH should be treated as ETH
    /// @param userData Additional user data for the router
    /// @return shareAmount Amount of vault shares minted
    function depositProportional(
        address recipient,
        bool[] memory wrapUnderlying,
        uint256[] memory maxInputAmounts,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable override nonReentrant returns (uint256 shareAmount) {
        _validateDeposit(
            recipient,
            wrapUnderlying,
            maxInputAmounts,
            exactBptAmountOut
        );
        uint256[] memory balancesBefore = _collectAndSnapshot(
            maxInputAmounts,
            _collectPayment
        );
        // Capture backing before adding liquidity for correct share calculation
        uint256 backingBefore = totalSupply() == 0 ? 0 : (
            address(gauge) != address(0)
                ? IERC20(address(gauge)).balanceOf(address(this))
                : IERC20(pool).balanceOf(address(this))
        );
        uint256[] memory actualInputAmounts = addLiquidityProportional(
            wrapUnderlying,
            maxInputAmounts,
            exactBptAmountOut,
            wethIsEth,
            userData,
            msg.value
        );
        shareAmount = calculateDepositShares(exactBptAmountOut, backingBefore);
        _mint(recipient, shareAmount);
        _refundExcessAll(balancesBefore);
        emit Deposit(
            msg.sender,
            recipient,
            exactBptAmountOut,
            shareAmount,
            true,
            actualInputAmounts
        );
    }

    /// @notice Withdraw tokens from the vault, burning shares
    /// @param sharesToBurn Amount of vault shares to burn
    /// @param minAmountsOut Minimum amounts of each token to withdraw
    /// @param unwrapWrapped Array indicating if each token should be unwrapped
    /// @param wethIsEth Whether WETH should be treated as ETH
    /// @param userData Additional user data for the router
    /// @return tokensOut The addresses of tokens withdrawn
    /// @return amountsOut The amounts of tokens withdrawn
    function withdraw(
        uint256 sharesToBurn,
        uint256[] memory minAmountsOut,
        bool[] memory unwrapWrapped,
        bool wethIsEth,
        bytes memory userData
    )
        external
        override
        nonReentrant
        returns (address[] memory tokensOut, uint256[] memory amountsOut)
    {
        if (sharesToBurn == 0) revert InvalidAmount();
        if (
            minAmountsOut.length != poolTokens.length ||
            unwrapWrapped.length != poolTokens.length
        ) {
            revert ArrayLengthMismatch();
        }
        (tokensOut, amountsOut) = _withdrawAndRemoveLiquidity(
            sharesToBurn,
            minAmountsOut,
            unwrapWrapped,
            wethIsEth,
            userData
        );
        for (uint256 i = 0; i < tokensOut.length; ) {
            if (wethIsEth && tokensOut[i] == nativeToken) {
                (bool success, ) = msg.sender.call{value: amountsOut[i]}("");
                if (!success) revert ETHRefundFailed();
            } else {
                IERC20(tokensOut[i]).safeTransfer(msg.sender, amountsOut[i]);
            }

            unchecked {
                ++i;
            }
        }
        emit Withdraw(msg.sender, sharesToBurn, tokensOut, amountsOut);
    }

    /// @notice Claim rewards from the gauge and minter
    function claimRewards() external override nonReentrant {
        if (address(gauge) != address(0)) gauge.claim_rewards();
        if (address(pesudoMinter) != address(0)) {
            pesudoMinter.mint(address(gauge));
        }
    }

    /// @notice Multicall for batch execution of whitelisted contract calls (owner only)
    /// @dev Only whitelisted addresses can call this function. Each target must also be whitelisted.
    /// @param targets The contract addresses to call
    /// @param data The calldata for each call
    /// @return results The return data from each call
    function multicall(
        address[] calldata targets,
        bytes[] calldata data
    )
        external
        override
        nonReentrant
        onlyWhitelisted
        returns (bytes[] memory results)
    {
        if (targets.length != data.length) revert ArrayLengthMismatch();
        results = new bytes[](targets.length);
        for (uint256 i = 0; i < targets.length; ++i) {
            if (!multicallWhitelist[targets[i]]) {
                revert NotWhitelisted(targets[i]);  //bal, gho, weth-oseth //bal-weth gh
            }
            (bool success, bytes memory result) = targets[i].call(data[i]);
            if (!success) revert MulticallSubcallFailed(targets[i], data[i]);
            results[i] = result;
        }
        emit Multicall(targets, data);
    }

    /// @notice Deduct platform fees from a token balance
    /// @dev Only callable by the contract itself (e.g., via multicall)
    /// @param token The token address to deduct fees from
    function deductFees(address token) external override {
        if (msg.sender != address(this)) revert("NA");
        if (token == address(gauge) || token == pool) revert("NA");
        if (token == address(0)) revert ZeroAddress();
        //if token guage  then reward
        uint256 feesAmount = (IERC20(token).balanceOf(address(this)) *
            platformFeePercentage) / 10000;
        IERC20(token).safeTransfer(feeReceiver, feesAmount);
        emit FeeDeducted(token, feesAmount);
    }

    // --- Public Functions for Direct Pool Interaction ---
    // NOTE: These functions are intended for internal use (e.g., reward compounding via multicall)
    // and should NOT be called directly by users.

    /// @notice Add liquidity in a proportional way
    /// @dev For internal use (e.g., reward compounding via multicall). Users should not call directly.
    /// @param wrapUnderlying Array indicating if each token should be wrapped
    /// @param maxInputAmounts The max amounts of each token to deposit
    /// @param exactBptAmountOut Exact BPT to receive from the pool
    /// @param wethIsEth Whether WETH should be treated as ETH
    /// @param userData Additional user data
    /// @param ethAmount Amount of ETH sent (if any)
    /// @return actualInputAmounts The actual amounts of tokens deposited
    function addLiquidityProportional(
        bool[] memory wrapUnderlying,
        uint256[] memory maxInputAmounts,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData,
        uint256 ethAmount
    ) public returns (uint256[] memory actualInputAmounts) {
        // This function is intended for internal use (e.g., reward compounding via multicall).
        // Users should not call this directly.
        (, actualInputAmounts) = router.addLiquidityProportionalToERC4626Pool{
            value: ethAmount
        }(
            pool,
            wrapUnderlying,
            maxInputAmounts,
            exactBptAmountOut,
            wethIsEth,
            userData
        );
        // Only deposit into gauge if a gauge is configured
        if (address(gauge) != address(0)) {
            gauge.deposit(exactBptAmountOut);
        }
    }

    /// @notice Add liquidity in an unbalanced way
    /// @dev For internal use (e.g., reward compounding via multicall). Users should not call directly.
    /// @param wrapUnderlying Array indicating if each token should be wrapped
    /// @param inputAmounts The amounts of each token to deposit
    /// @param minBptAmountOut Minimum BPT to receive from the pool
    /// @param wethIsEth Whether WETH should be treated as ETH
    /// @param userData Additional user data
    /// @param ethAmount Amount of ETH sent (if any)
    /// @return bptAmountOut The amount of BPT received
    function addLiquidityUnbalanced(
        bool[] memory wrapUnderlying,
        uint256[] memory inputAmounts,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData,
        uint256 ethAmount
    ) public returns (uint256 bptAmountOut) {
        // This function is intended for internal use (e.g., reward compounding via multicall).
        // Users should not call this directly.
        bptAmountOut = router.addLiquidityUnbalancedToERC4626Pool{
            value: ethAmount
        }(
            pool,
            wrapUnderlying,
            inputAmounts,
            minBptAmountOut,
            wethIsEth,
            userData
        );
        // Only deposit into gauge if a gauge is configured
        if (address(gauge) != address(0)) {
            gauge.deposit(bptAmountOut);
        }
    }

    /// @notice Internal function to calculate shares with a pre-captured backing amount
    /// @param bptAmountOut The amount of BPT received
    /// @param backingBefore The backing amount before adding liquidity
    /// @return shares The amount of shares to mint
    function calculateDepositShares(
        uint256 bptAmountOut,
        uint256 backingBefore
    ) public view returns (uint256 shares) {
        if (totalSupply() == 0) {
            shares = bptAmountOut;
        } else {
            shares = (bptAmountOut * totalSupply()) / backingBefore;
        }
    }

    /// @notice Calculate BPT amount to withdraw for a given share amount
    /// @param sharesToBurn The amount of shares to burn
    /// @return bptAmount The amount of BPT to withdraw
    function calculateWithdrawShares(
        uint256 sharesToBurn
    ) public view returns (uint256 bptAmount) {
        uint256 backing = address(gauge) != address(0)
            ? IERC20(address(gauge)).balanceOf(address(this))
            : IERC20(pool).balanceOf(address(this));
        bptAmount = (backing * sharesToBurn) / totalSupply();
    }

    // --- Internal Helper Functions ---

    /// @dev Collect payment from user and snapshot balances
    /// @param token Token address to collect
    /// @param amount Amount to collect
    function _collectPayment(address token, uint256 amount) internal {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (token == nativeToken && msg.value > 0) {
            if (msg.value != amount) revert IncorrectETHSent();
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    /// @dev Refund any excess tokens to the user
    /// @param token Token address to refund
    /// @param amount Amount to refund
    function _refundExcess(address token, uint256 amount) internal {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) return;
        if (token == nativeToken && msg.value > 0) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert ETHRefundFailed();
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    /// @dev Collect tokens and snapshot balances before deposit
    /// @param inputAmounts Amounts to collect for each token
    /// @param collectFn Function to call for collecting tokens
    /// @return balancesBefore Array of balances before collection
    function _collectAndSnapshot(
        uint256[] memory inputAmounts,
        function(address, uint256) internal collectFn
    ) internal returns (uint256[] memory) {
        uint256[] memory balancesBefore = new uint256[](poolTokens.length);
        for (uint256 i = 0; i < poolTokens.length; ) {
            address token = address(poolTokens[i]);
            if (token == nativeToken && msg.value > 0) {
                balancesBefore[i] = address(this).balance - msg.value;
            } else {
                balancesBefore[i] = IERC20(token).balanceOf(address(this));
            }

            if (inputAmounts[i] > 0) {
                collectFn(token, inputAmounts[i]);
            }
            unchecked {
                ++i;
            }
        }
        return balancesBefore;
    }

    /// @dev Refund all excess tokens after deposit
    /// @param balancesBefore Array of balances before deposit
    function _refundExcessAll(uint256[] memory balancesBefore) internal {
        for (uint256 i = 0; i < poolTokens.length; ) {
            address token = address(poolTokens[i]);
            uint256 balanceAfter;
            if (token == nativeToken && msg.value > 0) {
                balanceAfter = address(this).balance;
            } else {
                balanceAfter = IERC20(token).balanceOf(address(this));
            }
            uint256 excess = balanceAfter > balancesBefore[i]
                ? balanceAfter - balancesBefore[i]
                : 0;
            if (excess > 0) {
                _refundExcess(token, excess);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Withdraw and remove liquidity from the pool, burning shares
    /// @param sharesToBurn Amount of shares to burn
    /// @param minAmountsOut Minimum amounts to withdraw
    /// @param unwrapWrapped Array indicating if each token should be unwrapped
    /// @param wethIsEth Whether WETH should be treated as ETH
    /// @param userData Additional user data
    /// @return tokensOut Array of token addresses withdrawn
    /// @return amountsOut Array of amounts withdrawn
    function _withdrawAndRemoveLiquidity(
        uint256 sharesToBurn,
        uint256[] memory minAmountsOut,
        bool[] memory unwrapWrapped,
        bool wethIsEth,
        bytes memory userData
    )
        internal
        returns (address[] memory tokensOut, uint256[] memory amountsOut)
    {
        uint256 bptAmount = calculateWithdrawShares(sharesToBurn);

        // If gauge exists, withdraw staked BPT from gauge and remove the delta
        if (address(gauge) != address(0)) {
            uint256 lpAmountBefore = IERC20(pool).balanceOf(address(this));
            gauge.withdraw(bptAmount);
            uint256 lpAmountAfter = IERC20(pool).balanceOf(address(this));
            uint256 lpDiff = lpAmountAfter > lpAmountBefore
                ? lpAmountAfter - lpAmountBefore
                : 0;
            (tokensOut, amountsOut) = router.removeLiquidityProportionalFromERC4626Pool(
                pool,
                unwrapWrapped,
                lpDiff,
                minAmountsOut,
                wethIsEth,
                userData
            );
        } else {
            // No gauge configured: remove directly from pool using bptAmount
            (tokensOut, amountsOut) = router.removeLiquidityProportionalFromERC4626Pool(
                pool,
                unwrapWrapped,
                bptAmount,
                minAmountsOut,
                wethIsEth,
                userData
            );
        }

        _burn(msg.sender, sharesToBurn);
    }

    /// @dev Validate deposit input arrays and amounts
    /// @param recipient Recipient address
    /// @param wrapUnderlying Array indicating if each token should be wrapped
    /// @param maxInputAmounts Array of max input amounts
    /// @param exactBptAmountOut Exact BPT amount out
    function _validateDeposit(
        address recipient,
        bool[] memory wrapUnderlying,
        uint256[] memory maxInputAmounts,
        uint256 exactBptAmountOut
    ) internal view {
        if (recipient == address(0)) revert ZeroAddress();
        if (
            wrapUnderlying.length != poolTokens.length ||
            maxInputAmounts.length != poolTokens.length
        ) {
            revert ArrayLengthMismatch();
        }
        if (exactBptAmountOut == 0) revert InvalidAmount();
    }
}
