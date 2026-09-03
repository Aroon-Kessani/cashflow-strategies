# AAVE Vault Contracts

A collection of secure vault contracts that allow users to deposit assets (ETH or ERC20 tokens) into AAVE V3 and receive tradeable ERC20 share tokens representing their stake in the vault.

## Contracts

### ETH_VAULT
A vault specifically designed for ETH deposits that automatically converts to WETH for AAVE integration.

### TOKEN_VAULT  
A generic vault for any ERC20 token supported by AAVE V3.

## Features

### Common Features (Both Vaults)
- **1:1 Share Ratio**: Users receive vault shares equal to the aTokens received from AAVE
- **Yield Earning**: Users earn AAVE lending yields on their deposited assets
- **Tradeable Shares**: Vault shares are ERC20 tokens that can be transferred or traded
- **Secure Withdrawals**: Users can withdraw their assets by burning vault shares
- **Non-Reentrancy Protection**: All state-changing functions are protected against reentrancy attacks
- **Custom Errors**: Gas-efficient error handling using custom errors instead of require statements
- **Emergency Functions**: Owner-only emergency withdrawal capabilities
- **Comprehensive View Functions**: Asset conversion, balance checking, and preview functions

### ETH_VAULT Specific
- **ETH Deposits**: Users can deposit ETH directly into the vault
- **Automatic WETH Conversion**: ETH is automatically converted to WETH for AAVE integration
- **ETH Withdrawals**: Automatic WETH to ETH conversion on withdrawal

### TOKEN_VAULT Specific  
- **ERC20 Token Support**: Supports any ERC20 token that's supported by AAVE V3
- **Allowance Checking**: Built-in functions to check user allowances and maximum deposit amounts
- **Asset Information**: Functions to get detailed information about the underlying asset and aToken
- **Preview Functions**: Preview deposit/withdrawal amounts before executing transactions

## Contract Architecture

### Core Components

1. **ETH_VAULT**: Main vault contract inheriting from:
   - `ERC20`: For vault share tokens
   - `ReentrancyGuard`: For reentrancy protection
   - `Ownable`: For administrative functions

2. **AAVE Integration**: 
   - Interfaces with AAVE V3 Pool for lending
   - Automatically discovers aToken addresses
   - Handles WETH conversion for ETH deposits

3. **Security Features**:
   - OpenZeppelin's SafeERC20 for secure token transfers
   - Custom errors for gas efficiency
   - Non-reentrancy locks on all critical functions

## Key Functions

### User Functions

#### `deposit()` - Payable
Deposit ETH into the vault and receive shares.
```solidity
// Deposit 1 ETH
vault.deposit{value: 1 ether}();
```

#### `withdraw(uint256 sharesAmount)`
Withdraw ETH by burning vault shares.
```solidity
// Withdraw 0.5 ETH worth of shares
vault.withdraw(500000000000000000); // 0.5 ether in wei
```

#### `withdrawAll()`
Convenience function to withdraw all user's shares at once.
```solidity
vault.withdrawAll();
```

### View Functions

#### `totalAssets()`
Get the total ETH value held in the vault.

#### `getUserBalance(address user)`
Get a user's ETH balance in the vault.

#### `convertToAssets(uint256 shares)`
Convert vault shares to ETH value.

#### `convertToShares(uint256 assets)`
Convert ETH amount to vault shares.

### Administrative Functions

#### `emergencyWithdraw(uint256 amount)` - Owner Only
Emergency function for the owner to withdraw funds if needed.

## Deployment

### Prerequisites

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Install dependencies:
```bash
forge install
```

### Compile

```bash
forge build
```

### Deploy

1. Set up environment variables:
```bash
export PRIVATE_KEY=your_private_key
export RPC_URL=your_ethereum_rpc_url
```

2. Deploy to mainnet:
```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## Usage Examples

### ETH_VAULT Usage

```solidity
// Deploy the ETH vault
ETH_VAULT ethVault = new ETH_VAULT(
    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
    0x87870BCEd4C6C8C8c8C8c8c8C8c8c8C8c8c8c8c8, // AAVE V3 Pool
    "AAVE ETH Vault Shares",
    "aETH-VAULT"
);

// User deposits 1 ETH
ethVault.deposit{value: 1 ether}();

// Check user's shares
uint256 userShares = ethVault.balanceOf(user);

// Check user's ETH balance in vault
uint256 userEthBalance = ethVault.getUserBalance(user);

// User withdraws all shares
ethVault.withdrawAll();
```

### TOKEN_VAULT Usage

```solidity
// Deploy the TOKEN vault for USDC
TOKEN_VAULT usdcVault = new TOKEN_VAULT(
    0xA0b86a33E6441c8C06DD2b7c94b7E6E8b8b8b8b8, // USDC
    0x87870BCEd4C6C8C8c8C8c8c8C8c8c8C8c8c8c8c8, // AAVE V3 Pool
    "AAVE USDC Vault Shares",
    "aUSDC-VAULT"
);

// User approves USDC spending
IERC20(usdcAddress).approve(address(usdcVault), 1000 * 1e6); // 1000 USDC

// Check maximum deposit amount
uint256 maxDeposit = usdcVault.maxDeposit(user);

// Preview shares to be received
uint256 expectedShares = usdcVault.previewDeposit(1000 * 1e6);

// User deposits 1000 USDC
usdcVault.deposit(1000 * 1e6);

// Check user's shares and balance
uint256 userShares = usdcVault.balanceOf(user);
uint256 userBalance = usdcVault.getUserBalance(user);

// Get asset information
(address assetAddr, string memory symbol, string memory name, uint8 decimals) = usdcVault.getAssetInfo();

// User withdraws specific amount
usdcVault.withdraw(500 * 1e6); // Withdraw 500 USDC worth of shares
```

## Security Considerations

1. **Reentrancy Protection**: All state-changing functions use `nonReentrant` modifier
2. **Safe Token Transfers**: Uses OpenZeppelin's SafeERC20 for all token operations
3. **Input Validation**: All functions validate inputs and use custom errors
4. **Access Control**: Administrative functions are restricted to the owner
5. **Emergency Functions**: Owner can perform emergency withdrawals if needed

## Contract Addresses

### Mainnet
- WETH: `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2`
- AAVE V3 Pool: `0x87870Bced4c6c8c8c8c8c8c8c8c8c8c8c8c8c8c8`

### Testnet (Sepolia)
- WETH: `0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14`
- AAVE V3 Pool: `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951`

## Events

```solidity
event Deposited(address indexed user, uint256 ethAmount, uint256 sharesReceived);
event Withdrawn(address indexed user, uint256 sharesAmount, uint256 ethReceived);
event EmergencyWithdraw(address indexed owner, uint256 amount);
```

## Custom Errors

```solidity
error ZeroAmount();
error ZeroAddress();
error InsufficientBalance();
error InsufficientShares();
error TransferFailed();
error InvalidToken();
```

## License

MIT License - see LICENSE file for details.