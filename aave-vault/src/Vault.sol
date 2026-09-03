// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IWNative.sol";

/**
 * @title Vault - AAVE Yield Vault
 * @author Cashflow Protocol
 * @notice A vault contract that automatically deposits ERC20 tokens into AAVE to earn yield
 * @dev This contract implements an ERC4626-like vault that:
 *      - Accepts deposits of a specific ERC20 token (including native tokens via WETH)
 *      - Automatically supplies deposited tokens to AAVE lending pool
 *      - Mints vault shares to depositors representing their claim on underlying assets
 *      - Allows withdrawals by burning shares and retrieving assets from AAVE
 *      - Maintains a 1:1 relationship between vault shares and AAVE aTokens
 *
 * @custom:security-contact security@cashflow.com
 */
contract Vault is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when attempting to deposit/withdraw zero amount
    error ZeroAmount();

    /// @notice Thrown when a zero address is provided where a valid address is required
    error ZeroAddress();

    /// @notice Thrown when user has insufficient token balance for the operation
    error InsufficientBalance();

    /// @notice Thrown when user has insufficient vault shares for withdrawal
    error InsufficientShares();

    /// @notice Thrown when a token transfer operation fails
    error TransferFailed();

    /// @notice Thrown when the provided token is not supported by AAVE
    error InvalidToken();

    /// @notice Thrown when user hasn't approved sufficient tokens for the operation
    error InsufficientAllowance();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The underlying ERC20 token that this vault accepts for deposits
    IERC20 public immutable asset;

    /// @notice Address of the wrapped native token (WETH/WMATIC etc.) for native token support
    address public immutable wnative;

    /// @notice The AAVE lending pool contract interface
    IPool public immutable aavePool;

    /// @notice The AAVE aToken received when supplying assets to AAVE
    /// @dev This represents the vault's claim on the underlying assets in AAVE
    IERC20 public immutable aToken;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a user deposits assets into the vault
    /// @param user The address of the depositor
    /// @param assetAmount The amount of underlying assets deposited
    /// @param sharesReceived The amount of vault shares minted to the user
    event Deposited(address indexed user, uint256 assetAmount, uint256 sharesReceived);

    /// @notice Emitted when a user withdraws assets from the vault
    /// @param user The address of the withdrawer
    /// @param sharesAmount The amount of vault shares burned
    /// @param assetReceived The amount of underlying assets received
    event Withdrawn(address indexed user, uint256 sharesAmount, uint256 assetReceived);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the vault with the specified parameters
     * @dev Sets up the vault to work with a specific ERC20 token and AAVE pool
     * @param _assetAddress Address of the ERC20 token that this vault will accept
     * @param _aavePoolAddress Address of the AAVE lending pool contract
     * @param _wnative Address of the wrapped native token (WETH/WMATIC etc.)
     * @param _name Human-readable name for the vault share token (e.g., "AAVE USDC Vault")
     * @param _symbol Symbol for the vault share token (e.g., "aUSDC-V")
     *
     * @custom:requirements
     * - All addresses must be non-zero
     * - The asset must be supported by the AAVE pool (have a valid aToken)
     * - The vault will have maximum approval to the AAVE pool for gas efficiency
     */
    constructor(
        address _assetAddress,
        address _aavePoolAddress,
        address _wnative,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        // Validate input parameters
        if (_assetAddress == address(0)) revert ZeroAddress();
        if (_aavePoolAddress == address(0)) revert ZeroAddress();
        if (_wnative == address(0)) revert ZeroAddress();

        // Initialize immutable state variables
        wnative = _wnative;
        asset = IERC20(_assetAddress);
        aavePool = IPool(_aavePoolAddress);

        // Retrieve the corresponding aToken address from AAVE
        // The aToken represents the vault's claim on deposited assets in AAVE
        (,,,,,,,, address aTokenAddress,,,,,,) = aavePool.getReserveData(_assetAddress);
        if (aTokenAddress == address(0)) revert InvalidToken();
        aToken = IERC20(aTokenAddress);

        // Pre-approve AAVE pool for maximum efficiency
        // This eliminates the need for approval transactions on each deposit
        asset.forceApprove(_aavePoolAddress, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits assets into the vault and mints shares to the caller
     * @dev This function supports both ERC20 tokens and native tokens (via WETH wrapping)
     * @param amount The amount of assets to deposit
     *
     * @custom:flow
     * 1. Validates the deposit amount is non-zero
     * 2. Handles payment (either ERC20 transfer or native token wrapping)
     * 3. Supplies assets to AAVE lending pool
     * 4. Mints vault shares 1:1 with received aTokens
     * 5. Emits Deposited event
     *
     * @custom:security Protected by reentrancy guard
     */
    function deposit(uint256 amount) external payable nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Record aToken balance before deposit to calculate exact shares to mint
        uint256 aTokenBalanceBefore = aToken.balanceOf(address(this));

        // Handle payment: either transfer ERC20 tokens or wrap native tokens
        _pay(address(asset), amount);

        // Supply the assets to AAVE lending pool
        // This will mint aTokens to this vault contract
        aavePool.supply(address(asset), amount, address(this), 0);

        // Calculate the exact amount of aTokens received
        uint256 aTokenBalanceAfter = aToken.balanceOf(address(this));
        uint256 aTokensReceived = aTokenBalanceAfter - aTokenBalanceBefore;

        // Mint vault shares 1:1 with aTokens received
        // This maintains the invariant: vault shares = aToken balance
        _mint(msg.sender, aTokensReceived);

        emit Deposited(msg.sender, amount, aTokensReceived);
    }

    /**
     * @notice Withdraws assets from the vault by burning shares
     * @dev Burns the specified amount of shares and withdraws corresponding assets from AAVE
     * @param sharesAmount The amount of vault shares to burn
     *
     * @custom:flow
     * 1. Validates the withdrawal amount and user's share balance
     * 2. Burns the specified amount of vault shares
     * 3. Withdraws corresponding assets from AAVE (1:1 ratio)
     * 4. Transfers assets directly to the user
     * 5. Emits Withdrawn event
     *
     * @custom:security Protected by reentrancy guard
     */
    function withdraw(uint256 sharesAmount) external nonReentrant {
        if (sharesAmount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < sharesAmount) revert InsufficientShares();

        // Burn vault shares first (checks-effects-interactions pattern)
        _burn(msg.sender, sharesAmount);

        // Withdraw from AAVE: 1 share = 1 aToken = ~1 underlying asset
        // Assets are sent directly to the user
        uint256 tokensReceived = aavePool.withdraw(address(asset), sharesAmount, msg.sender);

        emit Withdrawn(msg.sender, sharesAmount, tokensReceived);
    }

    /**
     * @notice Withdraws all of the caller's shares from the vault
     * @dev Convenience function that withdraws the user's entire position
     *
     * @custom:flow
     * 1. Gets the user's total share balance
     * 2. Burns all user shares
     * 3. Withdraws all corresponding assets from AAVE
     * 4. Transfers all assets to the user
     *
     * @custom:security Protected by reentrancy guard
     */
    function withdrawAll() external nonReentrant {
        uint256 userShares = balanceOf(msg.sender);
        if (userShares == 0) revert InsufficientShares();

        // Burn all user's vault shares
        _burn(msg.sender, userShares);

        // Withdraw all corresponding assets from AAVE
        uint256 tokensReceived = aavePool.withdraw(address(asset), userShares, msg.sender);

        emit Withdrawn(msg.sender, userShares, tokensReceived);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of underlying assets held by the vault
     * @dev This represents the total value locked in the vault via AAVE aTokens
     * @return The total amount of underlying assets (equivalent to aToken balance)
     */
    function totalAssets() external view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /**
     * @notice Converts vault shares to their equivalent underlying asset amount
     * @dev Uses the current exchange rate between shares and assets
     * @param shares The amount of vault shares to convert
     * @return The equivalent amount of underlying assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return 0;

        return (shares * aToken.balanceOf(address(this))) / totalShares;
    }

    /**
     * @notice Converts underlying assets to their equivalent vault share amount
     * @dev Uses the current exchange rate between assets and shares
     * @param assets The amount of underlying assets to convert
     * @return The equivalent amount of vault shares
     */
    function convertToShares(uint256 assets) external view returns (uint256) {
        uint256 totalVaultAssets = aToken.balanceOf(address(this));
        if (totalVaultAssets == 0) return assets; // 1:1 ratio when vault is empty

        return (assets * totalSupply()) / totalVaultAssets;
    }

    /**
     * @notice Returns the underlying asset value of a user's vault shares
     * @dev Calculates the user's proportional claim on the vault's total assets
     * @param user The address of the user to query
     * @return The underlying asset value of the user's shares
     */
    function getUserBalance(address user) external view returns (uint256) {
        uint256 userShares = balanceOf(user);
        uint256 totalShares = totalSupply();

        if (totalShares == 0) return 0;

        return (userShares * aToken.balanceOf(address(this))) / totalShares;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if a user has sufficient token allowance for a deposit
     * @dev Useful for frontend applications to validate before attempting deposit
     * @param user The address of the user to check
     * @param amount The amount to check allowance for
     * @return True if the user has sufficient allowance, false otherwise
     */
    function hasAllowance(address user, uint256 amount) external view returns (bool) {
        return asset.allowance(user, address(this)) >= amount;
    }

    /**
     * @notice Returns the maximum amount a user can deposit
     * @dev Returns the minimum of the user's token balance and their allowance to this contract
     * @param user The address of the user to query
     * @return The maximum amount the user can deposit
     */
    function maxDeposit(address user) external view returns (uint256) {
        uint256 balance = asset.balanceOf(user);
        uint256 allowance = asset.allowance(user, address(this));
        return balance < allowance ? balance : allowance;
    }

    /**
     * @notice Previews the amount of shares that would be minted for a deposit
     * @dev Simulates a deposit without executing it - useful for UI calculations
     * @param assets The amount of assets to simulate depositing
     * @return The amount of shares that would be minted
     */
    function previewDeposit(uint256 assets) external view returns (uint256) {
        uint256 totalVaultAssets = aToken.balanceOf(address(this));
        if (totalVaultAssets == 0) return assets; // 1:1 ratio when vault is empty

        return (assets * totalSupply()) / totalVaultAssets;
    }

    /**
     * @notice Previews the amount of assets that would be received for a withdrawal
     * @dev Simulates a withdrawal without executing it - useful for UI calculations
     * @param shares The amount of shares to simulate burning
     * @return The amount of assets that would be received
     */
    function previewWithdraw(uint256 shares) external view returns (uint256) {
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return 0;

        return (shares * aToken.balanceOf(address(this))) / totalShares;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Handles payment for deposits, supporting both ERC20 and native tokens
     * @dev Internal function that either transfers ERC20 tokens or wraps native tokens
     * @param _token The token address to handle payment for
     * @param _amount The amount to pay
     *
     * @custom:behavior
     * - If token is wnative and msg.value > 0: wraps native tokens to WETH
     * - Otherwise: transfers ERC20 tokens from user to vault
     *
     * @custom:security
     * - Validates msg.value matches amount for native token deposits
     * - Uses SafeERC20 for secure token transfers
     */
    function _pay(address _token, uint256 _amount) internal {
        if (_token == wnative && msg.value > 0) {
            // Handle native token deposits by wrapping to WETH
            require(msg.value == _amount, "Incorrect value sent");
            IWNative(_token).deposit{value: _amount}();
        } else {
            // Handle ERC20 token deposits
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }
    }
}
