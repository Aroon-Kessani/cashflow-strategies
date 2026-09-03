// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Vault.sol";

interface IERC20Extended {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
}

contract TOKEN_VAULT_Test is Test {
    Vault public usdtVault;
    Vault public wethVault;

    // Mainnet addresses
    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // Aave V3 Pool
    //address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // Aave V3 WETH Pool
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDT = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDT on Ethereum

    // Aave V3 aTokens
    address constant aWETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8;
    address constant aUSDT = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;

    // Whale addresses for token transfers (addresses with large balances)
    address constant USDT_WHALE = 0x935f64B44B5C48A1539C4AdA5161D27ace4205b5; // Compound cUSDT
    address constant WETH_WHALE = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28; // Avalanche Bridge

    // Test users
    address public user1;
    address public user2;
    address public user3;

    function setUp() public {
        // Create mainnet fork
        // string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://eth-mainnet.g.alchemy.com/v2/demo"));
        // mainnetFork = vm.createFork(rpcUrl);
        // vm.selectFork(mainnetFork);

        // Create test users
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Give users some ETH for gas
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);

        // Deploy USDT vault
        usdtVault = new Vault(USDT, AAVE_POOL, WETH, "USDT Vault Shares", "vUSDT");

        // Deploy WETH vault
        wethVault = new Vault(WETH, AAVE_POOL, WETH, "WETH Vault Shares", "vWETH");

        // Fund test users with tokens
        _fundUsersWithTokens();

        console.log("USDT Vault deployed at:", address(usdtVault));
        console.log("WETH Vault deployed at:", address(wethVault));
        console.log("AAVE Pool:", AAVE_POOL);
        console.log("USDT aToken:", address(usdtVault.aToken()));
        console.log("WETH aToken:", address(wethVault.aToken()));
    }

    function _fundUsersWithTokens() internal {
        // Fund users with USDT (6 decimals)
        uint256 usdtAmount = 10000 * 10 ** 6; // 10,000 USDT

        vm.startPrank(USDT_WHALE);
        IERC20Extended(USDT).transfer(user1, usdtAmount);
        IERC20Extended(USDT).transfer(user2, usdtAmount);
        IERC20Extended(USDT).transfer(user3, usdtAmount);
        vm.stopPrank();

        // Fund users with WETH (18 decimals)
        uint256 wethAmount = 50 * 10 ** 18; // 50 WETH

        vm.startPrank(WETH_WHALE);
        IERC20Extended(WETH).transfer(user1, wethAmount);
        IERC20Extended(WETH).transfer(user2, wethAmount);
        IERC20Extended(WETH).transfer(user3, wethAmount);
        vm.stopPrank();

        console.log("Users funded with tokens");
        console.log("User1 USDT balance:", IERC20Extended(USDT).balanceOf(user1));
        console.log("User1 WETH balance:", IERC20Extended(WETH).balanceOf(user1));
    }

    function testForkSetup() public {
        // Verify we're on mainnet fork
        assertEq(block.chainid, 1);

        // Verify vault setup
        assertEq(address(usdtVault.asset()), USDT);
        assertEq(address(usdtVault.aavePool()), AAVE_POOL);
        assertEq(address(usdtVault.aToken()), aUSDT);

        assertEq(address(wethVault.asset()), WETH);
        assertEq(address(wethVault.aavePool()), AAVE_POOL);
        assertEq(address(wethVault.aToken()), aWETH);

        // Verify users have tokens
        assertGt(IERC20Extended(USDT).balanceOf(user1), 0);
        assertGt(IERC20Extended(WETH).balanceOf(user1), 0);
    }

    function testUSDTDeposit() public {
        uint256 depositAmount = 1000 * 10 ** 6; // 1,000 USDT

        vm.startPrank(user1);

        // Approve vault to spend USDT
        IERC20Extended(USDT).approve(address(usdtVault), depositAmount);

        uint256 usdtBalanceBefore = IERC20Extended(USDT).balanceOf(user1);
        uint256 vaultSharesBefore = usdtVault.balanceOf(user1);
        uint256 aTokenBalanceBefore = IERC20Extended(aUSDT).balanceOf(address(usdtVault));

        // Deposit USDT to vault
        usdtVault.deposit(depositAmount);

        uint256 usdtBalanceAfter = IERC20Extended(USDT).balanceOf(user1);
        uint256 vaultSharesAfter = usdtVault.balanceOf(user1);
        uint256 aTokenBalanceAfter = IERC20Extended(aUSDT).balanceOf(address(usdtVault));

        // Verify USDT was deducted from user
        assertEq(usdtBalanceAfter, usdtBalanceBefore - depositAmount);

        // Verify vault shares were minted
        assertGt(vaultSharesAfter, vaultSharesBefore);

        // Verify aTokens were received by vault
        assertGt(aTokenBalanceAfter, aTokenBalanceBefore);

        // Verify approximately 1:1 ratio (allowing for small differences due to interest)
        assertApproxEqRel(vaultSharesAfter - vaultSharesBefore, depositAmount, 0.01e18); // 1% tolerance

        console.log("USDT deposited:", depositAmount);
        console.log("Vault shares minted:", vaultSharesAfter - vaultSharesBefore);
        console.log("aTokens received:", aTokenBalanceAfter - aTokenBalanceBefore);

        vm.stopPrank();
    }

    function testWETHDeposit() public {
        uint256 depositAmount = 5 * 10 ** 18; // 5 WETH

        vm.startPrank(user1);

        // Approve vault to spend WETH
        IERC20Extended(WETH).approve(address(wethVault), depositAmount);

        uint256 wethBalanceBefore = IERC20Extended(WETH).balanceOf(user1);
        uint256 vaultSharesBefore = wethVault.balanceOf(user1);
        uint256 aTokenBalanceBefore = IERC20Extended(aWETH).balanceOf(address(wethVault));

        // Deposit WETH to vault
        wethVault.deposit(depositAmount);

        uint256 wethBalanceAfter = IERC20Extended(WETH).balanceOf(user1);
        uint256 vaultSharesAfter = wethVault.balanceOf(user1);
        uint256 aTokenBalanceAfter = IERC20Extended(aWETH).balanceOf(address(wethVault));

        // Verify WETH was deducted from user
        assertEq(wethBalanceAfter, wethBalanceBefore - depositAmount);

        // Verify vault shares were minted
        assertGt(vaultSharesAfter, vaultSharesBefore);

        // Verify aTokens were received by vault
        assertGt(aTokenBalanceAfter, aTokenBalanceBefore);

        // Verify approximately 1:1 ratio
        assertApproxEqRel(vaultSharesAfter - vaultSharesBefore, depositAmount, 0.01e18);

        console.log("WETH deposited:", depositAmount);
        console.log("Vault shares minted:", vaultSharesAfter - vaultSharesBefore);
        console.log("aTokens received:", aTokenBalanceAfter - aTokenBalanceBefore);

        vm.stopPrank();
    }

    function testUSDTWithdraw() public {
        uint256 depositAmount = 2000 * 10 ** 6; // 2,000 USDT
        uint256 withdrawAmount = 800 * 10 ** 6; // 800 USDT

        vm.startPrank(user1);

        // First deposit
        IERC20Extended(USDT).approve(address(usdtVault), depositAmount);
        usdtVault.deposit(depositAmount);

        uint256 usdtBalanceBefore = IERC20Extended(USDT).balanceOf(user1);
        uint256 vaultSharesBefore = usdtVault.balanceOf(user1);

        // Withdraw
        usdtVault.withdraw(withdrawAmount);

        uint256 usdtBalanceAfter = IERC20Extended(USDT).balanceOf(user1);
        uint256 vaultSharesAfter = usdtVault.balanceOf(user1);

        // Verify USDT was received
        assertGt(usdtBalanceAfter, usdtBalanceBefore);

        // Verify vault shares were burned
        assertEq(vaultSharesAfter, vaultSharesBefore - withdrawAmount);

        // Verify approximately correct USDT amount received
        assertApproxEqRel(usdtBalanceAfter - usdtBalanceBefore, withdrawAmount, 0.01e18);

        console.log("Vault shares burned:", withdrawAmount);
        console.log("USDT received:", usdtBalanceAfter - usdtBalanceBefore);

        vm.stopPrank();
    }

    function testWETHWithdraw() public {
        uint256 depositAmount = 10 * 10 ** 18; // 10 WETH
        uint256 withdrawAmount = 3 * 10 ** 18; // 3 WETH

        vm.startPrank(user1);

        // First deposit
        IERC20Extended(WETH).approve(address(wethVault), depositAmount);
        wethVault.deposit(depositAmount);

        uint256 wethBalanceBefore = IERC20Extended(WETH).balanceOf(user1);
        uint256 vaultSharesBefore = wethVault.balanceOf(user1);

        // Withdraw
        wethVault.withdraw(withdrawAmount);

        uint256 wethBalanceAfter = IERC20Extended(WETH).balanceOf(user1);
        uint256 vaultSharesAfter = wethVault.balanceOf(user1);

        // Verify WETH was received
        assertGt(wethBalanceAfter, wethBalanceBefore);

        // Verify vault shares were burned
        assertEq(vaultSharesAfter, vaultSharesBefore - withdrawAmount);

        // Verify approximately correct WETH amount received
        assertApproxEqRel(wethBalanceAfter - wethBalanceBefore, withdrawAmount, 0.01e18);

        console.log("Vault shares burned:", withdrawAmount);
        console.log("WETH received:", wethBalanceAfter - wethBalanceBefore);

        vm.stopPrank();
    }

    function testWithdrawAllUSDT() public {
        uint256 depositAmount = 1500 * 10 ** 6; // 1,500 USDT

        vm.startPrank(user1);

        // Deposit
        IERC20Extended(USDT).approve(address(usdtVault), depositAmount);
        usdtVault.deposit(depositAmount);

        uint256 usdtBalanceBefore = IERC20Extended(USDT).balanceOf(user1);
        uint256 vaultSharesBefore = usdtVault.balanceOf(user1);

        // Withdraw all
        usdtVault.withdrawAll();

        uint256 usdtBalanceAfter = IERC20Extended(USDT).balanceOf(user1);
        uint256 vaultSharesAfter = usdtVault.balanceOf(user1);

        // Verify all shares were burned
        assertEq(vaultSharesAfter, 0);

        // Verify USDT was received
        assertGt(usdtBalanceAfter, usdtBalanceBefore);

        // Verify approximately correct amount
        assertApproxEqRel(usdtBalanceAfter - usdtBalanceBefore, depositAmount, 0.01e18);

        console.log("All USDT shares burned:", vaultSharesBefore);
        console.log("USDT received:", usdtBalanceAfter - usdtBalanceBefore);

        vm.stopPrank();
    }

    function testWithdrawAllWETH() public {
        uint256 depositAmount = 8 * 10 ** 18; // 8 WETH

        vm.startPrank(user1);

        // Deposit
        IERC20Extended(WETH).approve(address(wethVault), depositAmount);
        wethVault.deposit(depositAmount);

        uint256 wethBalanceBefore = IERC20Extended(WETH).balanceOf(user1);
        uint256 vaultSharesBefore = wethVault.balanceOf(user1);

        // Withdraw all
        wethVault.withdrawAll();

        uint256 wethBalanceAfter = IERC20Extended(WETH).balanceOf(user1);
        uint256 vaultSharesAfter = wethVault.balanceOf(user1);

        // Verify all shares were burned
        assertEq(vaultSharesAfter, 0);

        // Verify WETH was received
        assertGt(wethBalanceAfter, wethBalanceBefore);

        // Verify approximately correct amount
        assertApproxEqRel(wethBalanceAfter - wethBalanceBefore, depositAmount, 0.01e18);

        console.log("All WETH shares burned:", vaultSharesBefore);
        console.log("WETH received:", wethBalanceAfter - wethBalanceBefore);

        vm.stopPrank();
    }

    function testMultipleUsersUSDT() public {
        uint256 deposit1 = 500 * 10 ** 6; // 500 USDT
        uint256 deposit2 = 1200 * 10 ** 6; // 1,200 USDT
        uint256 deposit3 = 300 * 10 ** 6; // 300 USDT

        // User1 deposits
        vm.startPrank(user1);
        IERC20Extended(USDT).approve(address(usdtVault), deposit1);
        usdtVault.deposit(deposit1);
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        IERC20Extended(USDT).approve(address(usdtVault), deposit2);
        usdtVault.deposit(deposit2);
        vm.stopPrank();

        // User3 deposits
        vm.startPrank(user3);
        IERC20Extended(USDT).approve(address(usdtVault), deposit3);
        usdtVault.deposit(deposit3);
        vm.stopPrank();

        // Verify individual balances
        assertApproxEqRel(usdtVault.balanceOf(user1), deposit1, 0.01e18);
        assertApproxEqRel(usdtVault.balanceOf(user2), deposit2, 0.01e18);
        assertApproxEqRel(usdtVault.balanceOf(user3), deposit3, 0.01e18);

        // Verify total supply
        uint256 totalExpected = deposit1 + deposit2 + deposit3;
        assertApproxEqRel(usdtVault.totalSupply(), totalExpected, 0.01e18);

        // Verify total assets
        assertApproxEqRel(usdtVault.totalAssets(), totalExpected, 0.01e18);

        console.log("User1 USDT shares:", usdtVault.balanceOf(user1));
        console.log("User2 USDT shares:", usdtVault.balanceOf(user2));
        console.log("User3 USDT shares:", usdtVault.balanceOf(user3));
        console.log("Total USDT supply:", usdtVault.totalSupply());
        console.log("Total USDT assets:", usdtVault.totalAssets());
    }

    function testMultipleUsersWETH() public {
        uint256 deposit1 = 2 * 10 ** 18; // 2 WETH
        uint256 deposit2 = 5 * 10 ** 18; // 5 WETH
        uint256 deposit3 = 1 * 10 ** 18; // 1 WETH

        // User1 deposits
        vm.startPrank(user1);
        IERC20Extended(WETH).approve(address(wethVault), deposit1);
        wethVault.deposit(deposit1);
        vm.stopPrank();

        // User2 deposits
        vm.startPrank(user2);
        IERC20Extended(WETH).approve(address(wethVault), deposit2);
        wethVault.deposit(deposit2);
        vm.stopPrank();

        // User3 deposits
        vm.startPrank(user3);
        IERC20Extended(WETH).approve(address(wethVault), deposit3);
        wethVault.deposit(deposit3);
        vm.stopPrank();

        // Verify individual balances
        assertApproxEqRel(wethVault.balanceOf(user1), deposit1, 0.01e18);
        assertApproxEqRel(wethVault.balanceOf(user2), deposit2, 0.01e18);
        assertApproxEqRel(wethVault.balanceOf(user3), deposit3, 0.01e18);

        // Verify total supply
        uint256 totalExpected = deposit1 + deposit2 + deposit3;
        assertApproxEqRel(wethVault.totalSupply(), totalExpected, 0.01e18);

        // Verify total assets
        assertApproxEqRel(wethVault.totalAssets(), totalExpected, 0.01e18);

        console.log("User1 WETH shares:", wethVault.balanceOf(user1));
        console.log("User2 WETH shares:", wethVault.balanceOf(user2));
        console.log("User3 WETH shares:", wethVault.balanceOf(user3));
        console.log("Total WETH supply:", wethVault.totalSupply());
        console.log("Total WETH assets:", wethVault.totalAssets());
    }

    function testConversionFunctionsUSDT() public {
        uint256 depositAmount = 1000 * 10 ** 6; // 1,000 USDT

        vm.startPrank(user1);
        IERC20Extended(USDT).approve(address(usdtVault), depositAmount);
        usdtVault.deposit(depositAmount);
        vm.stopPrank();

        // Test convertToAssets
        uint256 shares = 500 * 10 ** 6; // 500 shares
        uint256 assets = usdtVault.convertToAssets(shares);
        assertApproxEqRel(assets, shares, 0.01e18); // Should be approximately 1:1

        // Test convertToShares
        uint256 assetsToConvert = 300 * 10 ** 6; // 300 USDT
        uint256 sharesToReceive = usdtVault.convertToShares(assetsToConvert);
        assertApproxEqRel(sharesToReceive, assetsToConvert, 0.01e18); // Should be approximately 1:1

        console.log("500 USDT worth of shares converts to assets:", assets);
        console.log("300 USDT worth of assets converts to shares:", sharesToReceive);
    }

    function testConversionFunctionsWETH() public {
        uint256 depositAmount = 5 * 10 ** 18; // 5 WETH

        vm.startPrank(user1);
        IERC20Extended(WETH).approve(address(wethVault), depositAmount);
        wethVault.deposit(depositAmount);
        vm.stopPrank();

        // Test convertToAssets
        uint256 shares = 2 * 10 ** 18; // 2 shares
        uint256 assets = wethVault.convertToAssets(shares);
        assertApproxEqRel(assets, shares, 0.01e18); // Should be approximately 1:1

        // Test convertToShares
        uint256 assetsToConvert = 1 * 10 ** 18; // 1 WETH
        uint256 sharesToReceive = wethVault.convertToShares(assetsToConvert);
        assertApproxEqRel(sharesToReceive, assetsToConvert, 0.01e18); // Should be approximately 1:1

        console.log("2 WETH worth of shares converts to assets:", assets);
        console.log("1 WETH worth of assets converts to shares:", sharesToReceive);
    }

    function testErrorConditions() public {
        vm.startPrank(user1);

        // Test zero deposit for USDT
        vm.expectRevert(Vault.ZeroAmount.selector);
        usdtVault.deposit(0);

        // Test zero deposit for WETH
        vm.expectRevert(Vault.ZeroAmount.selector);
        wethVault.deposit(0);

        // Test withdraw without shares for USDT
        vm.expectRevert(Vault.InsufficientShares.selector);
        usdtVault.withdraw(100 * 10 ** 6);

        // Test withdraw without shares for WETH
        vm.expectRevert(Vault.InsufficientShares.selector);
        wethVault.withdraw(1 * 10 ** 18);

        // Test withdrawAll without shares
        vm.expectRevert(Vault.InsufficientShares.selector);
        usdtVault.withdrawAll();

        vm.expectRevert(Vault.InsufficientShares.selector);
        wethVault.withdrawAll();

        // Deposit some USDT
        uint256 usdtDeposit = 1000 * 10 ** 6;
        IERC20Extended(USDT).approve(address(usdtVault), usdtDeposit);
        usdtVault.deposit(usdtDeposit);

        // Deposit some WETH
        uint256 wethDeposit = 5 * 10 ** 18;
        IERC20Extended(WETH).approve(address(wethVault), wethDeposit);
        wethVault.deposit(wethDeposit);

        // Test withdraw more than balance for USDT
        vm.expectRevert(Vault.InsufficientShares.selector);
        usdtVault.withdraw(1500 * 10 ** 6);

        // Test withdraw more than balance for WETH
        vm.expectRevert(Vault.InsufficientShares.selector);
        wethVault.withdraw(10 * 10 ** 18);

        // Test zero withdraw
        vm.expectRevert(Vault.ZeroAmount.selector);
        usdtVault.withdraw(0);

        vm.expectRevert(Vault.ZeroAmount.selector);
        wethVault.withdraw(0);

        vm.stopPrank();
    }

    function testGetUserBalance() public {
        uint256 usdtDepositAmount = 750 * 10 ** 6; // 750 USDT
        uint256 wethDepositAmount = 3 * 10 ** 18; // 3 WETH

        // Initially zero
        assertEq(usdtVault.getUserBalance(user1), 0);
        assertEq(wethVault.getUserBalance(user1), 0);

        vm.startPrank(user1);

        // Deposit USDT
        IERC20Extended(USDT).approve(address(usdtVault), usdtDepositAmount);
        usdtVault.deposit(usdtDepositAmount);

        // Deposit WETH
        IERC20Extended(WETH).approve(address(wethVault), wethDepositAmount);
        wethVault.deposit(wethDepositAmount);

        vm.stopPrank();

        // After deposit
        uint256 usdtUserBalance = usdtVault.getUserBalance(user1);
        uint256 wethUserBalance = wethVault.getUserBalance(user1);

        assertApproxEqRel(usdtUserBalance, usdtDepositAmount, 0.01e18);
        assertApproxEqRel(wethUserBalance, wethDepositAmount, 0.01e18);

        console.log("User USDT balance after deposit:", usdtUserBalance);
        console.log("User WETH balance after deposit:", wethUserBalance);
    }

    function testVaultState() public {
        // Test initial state
        assertEq(usdtVault.totalSupply(), 0);
        assertEq(usdtVault.totalAssets(), 0);
        assertEq(wethVault.totalSupply(), 0);
        assertEq(wethVault.totalAssets(), 0);

        uint256 usdtDepositAmount = 1000 * 10 ** 6; // 1,000 USDT
        uint256 wethDepositAmount = 5 * 10 ** 18; // 5 WETH

        vm.startPrank(user1);

        // Deposit USDT
        IERC20Extended(USDT).approve(address(usdtVault), usdtDepositAmount);
        usdtVault.deposit(usdtDepositAmount);

        // Deposit WETH
        IERC20Extended(WETH).approve(address(wethVault), wethDepositAmount);
        wethVault.deposit(wethDepositAmount);

        vm.stopPrank();

        // Test state after deposits
        assertApproxEqRel(usdtVault.totalSupply(), usdtDepositAmount, 0.01e18);
        assertApproxEqRel(usdtVault.totalAssets(), usdtDepositAmount, 0.01e18);
        assertApproxEqRel(wethVault.totalSupply(), wethDepositAmount, 0.01e18);
        assertApproxEqRel(wethVault.totalAssets(), wethDepositAmount, 0.01e18);

        // Verify aToken balances
        uint256 aUSDTBalance = IERC20Extended(aUSDT).balanceOf(address(usdtVault));
        uint256 aWETHBalance = IERC20Extended(aWETH).balanceOf(address(wethVault));

        assertApproxEqRel(aUSDTBalance, usdtDepositAmount, 0.01e18);
        assertApproxEqRel(aWETHBalance, wethDepositAmount, 0.01e18);

        console.log("USDT Vault total supply:", usdtVault.totalSupply());
        console.log("USDT Vault total assets:", usdtVault.totalAssets());
        console.log("USDT Vault aToken balance:", aUSDTBalance);
        console.log("WETH Vault total supply:", wethVault.totalSupply());
        console.log("WETH Vault total assets:", wethVault.totalAssets());
        console.log("WETH Vault aToken balance:", aWETHBalance);
    }

    function testPreviewFunctions() public {
        uint256 usdtDepositAmount = 1000 * 10 ** 6; // 1,000 USDT
        uint256 wethDepositAmount = 5 * 10 ** 18; // 5 WETH

        vm.startPrank(user1);

        // Test preview deposit when vault is empty (should be 1:1)
        uint256 usdtPreviewShares = usdtVault.previewDeposit(usdtDepositAmount);
        uint256 wethPreviewShares = wethVault.previewDeposit(wethDepositAmount);

        assertEq(usdtPreviewShares, usdtDepositAmount);
        assertEq(wethPreviewShares, wethDepositAmount);

        // Deposit USDT
        IERC20Extended(USDT).approve(address(usdtVault), usdtDepositAmount);
        usdtVault.deposit(usdtDepositAmount);

        // Deposit WETH
        IERC20Extended(WETH).approve(address(wethVault), wethDepositAmount);
        wethVault.deposit(wethDepositAmount);

        // Test preview withdraw
        uint256 usdtWithdrawAmount = 500 * 10 ** 6; // 500 USDT
        uint256 wethWithdrawAmount = 2 * 10 ** 18; // 2 WETH

        uint256 usdtPreviewAssets = usdtVault.previewWithdraw(usdtWithdrawAmount);
        uint256 wethPreviewAssets = wethVault.previewWithdraw(wethWithdrawAmount);

        assertApproxEqRel(usdtPreviewAssets, usdtWithdrawAmount, 0.01e18);
        assertApproxEqRel(wethPreviewAssets, wethWithdrawAmount, 0.01e18);

        console.log("USDT preview deposit shares:", usdtPreviewShares);
        console.log("WETH preview deposit shares:", wethPreviewShares);
        console.log("USDT preview withdraw assets:", usdtPreviewAssets);
        console.log("WETH preview withdraw assets:", wethPreviewAssets);

        vm.stopPrank();
    }

    function testMaxDeposit() public {
        vm.startPrank(user1);

        // Test max deposit without approval (should be 0)
        uint256 usdtMaxBefore = usdtVault.maxDeposit(user1);
        uint256 wethMaxBefore = wethVault.maxDeposit(user1);

        assertEq(usdtMaxBefore, 0);
        assertEq(wethMaxBefore, 0);

        // Approve some amount
        uint256 usdtApproval = 500 * 10 ** 6; // 500 USDT
        uint256 wethApproval = 3 * 10 ** 18; // 3 WETH

        IERC20Extended(USDT).approve(address(usdtVault), usdtApproval);
        IERC20Extended(WETH).approve(address(wethVault), wethApproval);

        // Test max deposit with approval
        uint256 usdtMaxAfter = usdtVault.maxDeposit(user1);
        uint256 wethMaxAfter = wethVault.maxDeposit(user1);

        assertEq(usdtMaxAfter, usdtApproval);
        assertEq(wethMaxAfter, wethApproval);

        console.log("USDT max deposit before approval:", usdtMaxBefore);
        console.log("USDT max deposit after approval:", usdtMaxAfter);
        console.log("WETH max deposit before approval:", wethMaxBefore);
        console.log("WETH max deposit after approval:", wethMaxAfter);

        vm.stopPrank();
    }

    function testHasAllowance() public {
        vm.startPrank(user1);

        uint256 usdtAmount = 1000 * 10 ** 6; // 1,000 USDT
        uint256 wethAmount = 5 * 10 ** 18; // 5 WETH

        // Test without approval
        assertFalse(usdtVault.hasAllowance(user1, usdtAmount));
        assertFalse(wethVault.hasAllowance(user1, wethAmount));

        // Approve
        IERC20Extended(USDT).approve(address(usdtVault), usdtAmount);
        IERC20Extended(WETH).approve(address(wethVault), wethAmount);

        // Test with approval
        assertTrue(usdtVault.hasAllowance(user1, usdtAmount));
        assertTrue(wethVault.hasAllowance(user1, wethAmount));

        // Test with amount greater than approval
        assertFalse(usdtVault.hasAllowance(user1, usdtAmount + 1));
        assertFalse(wethVault.hasAllowance(user1, wethAmount + 1));

        vm.stopPrank();
    }
}
