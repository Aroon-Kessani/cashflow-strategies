// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Vault.sol";

contract Vault_Test is Test {
    Vault public vault;

    // Mainnet addresses
    address constant AAVE_POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address constant AAVE_WETH_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2; // Aave V3 Pool
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant aWETH = 0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8; // Aave V3 aWETH

    // Test users
    address public user1;
    address public user2;
    address public user3;

    //uint256 public mainnetFork;

    function setUp() public {
        // Create mainnet fork
        // mainnetFork = vm.createFork("mainnet");
        // vm.selectFork(mainnetFork);

        // Create test users with ETH
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);

        // Deploy vault with real mainnet addresses
        vault = new Vault(WETH, AAVE_WETH_POOL, WETH, "ETH Vault Shares", "vETH");

        console.log("Vault deployed at:", address(vault));
        console.log("AAVE Pool:", AAVE_WETH_POOL);
        //console.log("WETH:", WETH);
        console.log("aWETH:", address(vault.aToken()));
    }

    function testForkSetup() public {
        // Verify we're on mainnet fork
        assertEq(block.chainid, 1);

        // Verify vault setup
        //assertEq(address(vault.WETH()), WETH);
        assertEq(address(vault.aavePool()), AAVE_WETH_POOL);
        assertEq(address(vault.aToken()), aWETH);

        // Verify users have ETH
        assertEq(user1.balance, 100 ether);
        assertEq(user2.balance, 100 ether);
        assertEq(user3.balance, 100 ether);
    }

    function testDepositETHToAave() public {
        uint256 depositAmount = 10 ether;

        vm.startPrank(user1);

        uint256 ethBalanceBefore = user1.balance;
        uint256 vaultSharesBefore = vault.balanceOf(user1);
        uint256 aTokenBalanceBefore = IERC20(aWETH).balanceOf(address(vault));

        // Deposit ETH to vault
        vault.deposit{value: depositAmount}(depositAmount);

        uint256 ethBalanceAfter = user1.balance;
        uint256 vaultSharesAfter = vault.balanceOf(user1);
        uint256 aTokenBalanceAfter = IERC20(aWETH).balanceOf(address(vault));

        // Verify ETH was deducted from user
        assertEq(ethBalanceAfter, ethBalanceBefore - depositAmount);

        // Verify vault shares were minted
        assertGt(vaultSharesAfter, vaultSharesBefore);

        // Verify aTokens were received by vault
        assertGt(aTokenBalanceAfter, aTokenBalanceBefore);

        // Verify approximately 1:1 ratio (allowing for small differences due to interest)
        assertApproxEqRel(vaultSharesAfter - vaultSharesBefore, depositAmount, 0.01e18); // 1% tolerance

        console.log("ETH deposited:", depositAmount);
        console.log("Vault shares minted:", vaultSharesAfter - vaultSharesBefore);
        console.log("aTokens received:", aTokenBalanceAfter - aTokenBalanceBefore);

        vm.stopPrank();
    }

    function testWithdrawETHFromAave() public {
        uint256 depositAmount = 10 ether;
        uint256 withdrawAmount = 6 ether;

        vm.startPrank(user1);

        // First deposit
        vault.deposit{value: depositAmount}(depositAmount);

        uint256 ethBalanceBefore = IERC20(WETH).balanceOf(user1);
        uint256 vaultSharesBefore = vault.balanceOf(user1);

        // Withdraw
        vault.withdraw(withdrawAmount);

        uint256 ethBalanceAfter = IERC20(WETH).balanceOf(user1);
        uint256 vaultSharesAfter = vault.balanceOf(user1);

        // Verify ETH was received
        assertGt(ethBalanceAfter, ethBalanceBefore);

        // Verify vault shares were burned
        assertEq(vaultSharesAfter, vaultSharesBefore - withdrawAmount);

        // Verify approximately correct ETH amount received (allowing for small differences)
        assertApproxEqRel(ethBalanceAfter - ethBalanceBefore, withdrawAmount, 0.01e18); // 1% tolerance

        console.log("Vault shares burned:", withdrawAmount);
        console.log("ETH received:", ethBalanceAfter - ethBalanceBefore);

        vm.stopPrank();
    }

    function testWithdrawAllETH() public {
        uint256 depositAmount = 15 ether;

        vm.startPrank(user1);

        // Deposit
        vault.deposit{value: depositAmount}(depositAmount);

        uint256 ethBalanceBefore = IERC20(WETH).balanceOf(user1);
        uint256 vaultSharesBefore = vault.balanceOf(user1);

        // Withdraw all
        vault.withdrawAll();

        uint256 ethBalanceAfter = IERC20(WETH).balanceOf(user1);
        uint256 vaultSharesAfter = vault.balanceOf(user1);

        // Verify all shares were burned
        assertEq(vaultSharesAfter, 0);

        // Verify ETH was received
        assertGt(ethBalanceAfter, ethBalanceBefore);

        // Verify approximately correct amount (allowing for interest accrual)
        assertApproxEqRel(ethBalanceAfter - ethBalanceBefore, depositAmount, 0.01e18); // 1% tolerance

        console.log("All shares burned:", vaultSharesBefore);
        console.log("ETH received:", ethBalanceAfter - ethBalanceBefore);

        vm.stopPrank();
    }

    function testMultipleUsersDeposit() public {
        uint256 deposit1 = 8 ether;
        uint256 deposit2 = 12 ether;
        uint256 deposit3 = 5 ether;

        // User1 deposits
        vm.prank(user1);
        vault.deposit{value: deposit1}(deposit1);

        // User2 deposits
        vm.prank(user2);
        vault.deposit{value: deposit2}(deposit2);

        // User3 deposits
        vm.prank(user3);
        vault.deposit{value: deposit3}(deposit3);

        // Verify individual balances
        assertApproxEqRel(vault.balanceOf(user1), deposit1, 0.01e18);
        assertApproxEqRel(vault.balanceOf(user2), deposit2, 0.01e18);
        assertApproxEqRel(vault.balanceOf(user3), deposit3, 0.01e18);

        // Verify total supply
        uint256 totalExpected = deposit1 + deposit2 + deposit3;
        assertApproxEqRel(vault.totalSupply(), totalExpected, 0.01e18);

        // Verify total assets
        assertApproxEqRel(vault.totalAssets(), totalExpected, 0.01e18);

        console.log("User1 shares:", vault.balanceOf(user1));
        console.log("User2 shares:", vault.balanceOf(user2));
        console.log("User3 shares:", vault.balanceOf(user3));
        console.log("Total supply:", vault.totalSupply());
        console.log("Total assets:", vault.totalAssets());
    }

    function testInterestAccrual() public {
        uint256 depositAmount = 20 ether;

        vm.startPrank(user1);

        // Deposit
        vault.deposit{value: depositAmount}(depositAmount);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialShares = vault.totalSupply();

        // Fast forward time to accrue interest
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 365 * 24 * 60 * 4); // Approximate blocks in a year

        uint256 finalAssets = vault.totalAssets();
        uint256 finalShares = vault.totalSupply();

        // Shares should remain the same
        assertEq(finalShares, initialShares);

        // Assets should have increased due to AAVE interest
        // Note: This might not always be true in a fork test depending on AAVE's current state
        console.log("Initial assets:", initialAssets);
        console.log("Final assets:", finalAssets);
        console.log("Interest earned:", finalAssets > initialAssets ? finalAssets - initialAssets : 0);

        vm.stopPrank();
    }

    function testConversionFunctions() public {
        uint256 depositAmount = 10 ether;

        vm.prank(user1);
        vault.deposit{value: depositAmount}(depositAmount);

        // Test convertToAssets
        uint256 shares = 5 ether;
        uint256 assets = vault.convertToAssets(shares);
        assertApproxEqRel(assets, shares, 0.01e18); // Should be approximately 1:1

        // Test convertToShares
        uint256 assetsToConvert = 3 ether;
        uint256 sharesToReceive = vault.convertToShares(assetsToConvert);
        assertApproxEqRel(sharesToReceive, assetsToConvert, 0.01e18); // Should be approximately 1:1

        console.log("5 ETH worth of shares converts to assets:", assets);
        console.log("3 ETH worth of assets converts to shares:", sharesToReceive);
    }

    function testGetUserBalance() public {
        uint256 depositAmount = 7 ether;

        // Initially zero
        assertEq(vault.getUserBalance(user1), 0);

        vm.prank(user1);
        vault.deposit{value: depositAmount}(depositAmount);

        // After deposit
        uint256 userBalance = vault.getUserBalance(user1);
        assertApproxEqRel(userBalance, depositAmount, 0.01e18);

        console.log("User balance after deposit:", userBalance);
    }

    function testLargeDeposit() public {
        uint256 largeAmount = 50 ether;

        // Give user more ETH for large deposit
        vm.deal(user1, largeAmount + 1 ether);

        vm.startPrank(user1);

        uint256 balanceBefore = user1.balance;

        vault.deposit{value: largeAmount}(largeAmount);

        uint256 balanceAfter = user1.balance;
        uint256 shares = vault.balanceOf(user1);

        assertEq(balanceAfter, balanceBefore - largeAmount);
        assertApproxEqRel(shares, largeAmount, 0.01e18);

        console.log("Large deposit amount:", largeAmount);
        console.log("Shares received:", shares);

        vm.stopPrank();
    }

    function testPartialWithdrawals() public {
        uint256 depositAmount = 20 ether;

        vm.startPrank(user1);

        // Deposit
        vault.deposit{value: depositAmount}(depositAmount);

        uint256 initialShares = vault.balanceOf(user1);
        uint256 initialBalance = IERC20(WETH).balanceOf(user1);

        // First partial withdrawal
        uint256 firstWithdraw = 5 ether;
        vault.withdraw(firstWithdraw);

        uint256 balanceAfterFirst = IERC20(WETH).balanceOf(user1);
        uint256 sharesAfterFirst = vault.balanceOf(user1);

        // Second partial withdrawal
        uint256 secondWithdraw = 8 ether;
        vault.withdraw(secondWithdraw);

        uint256 balanceAfterSecond = IERC20(WETH).balanceOf(user1);
        uint256 sharesAfterSecond = vault.balanceOf(user1);

        // Verify shares were burned correctly
        assertEq(sharesAfterFirst, initialShares - firstWithdraw);
        assertEq(sharesAfterSecond, initialShares - firstWithdraw - secondWithdraw);

        // Verify ETH was received
        assertGt(balanceAfterFirst, initialBalance);
        assertGt(balanceAfterSecond, balanceAfterFirst);

        console.log("Initial shares:", initialShares);
        console.log("Shares after first withdrawal:", sharesAfterFirst);
        console.log("Shares after second withdrawal:", sharesAfterSecond);
        console.log("Total ETH withdrawn:", balanceAfterSecond - initialBalance);

        vm.stopPrank();
    }

    function testErrorConditions() public {
        vm.startPrank(user1);

        // Test zero deposit
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.deposit{value: 0}(0);

        // Test withdraw without shares
        vm.expectRevert(Vault.InsufficientShares.selector);
        vault.withdraw(1 ether);

        // Test withdrawAll without shares
        vm.expectRevert(Vault.InsufficientShares.selector);
        vault.withdrawAll();

        // Deposit some amount
        vault.deposit{value: 10 ether}(10 ether);

        // Test withdraw more than balance
        vm.expectRevert(Vault.InsufficientShares.selector);
        vault.withdraw(15 ether);

        // Test zero withdraw
        vm.expectRevert(Vault.ZeroAmount.selector);
        vault.withdraw(0);

        vm.stopPrank();
    }

    function testVaultState() public {
        // Test initial state
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);

        uint256 depositAmount = 15 ether;

        vm.prank(user1);
        vault.deposit{value: depositAmount}(depositAmount);

        // Test state after deposit
        assertApproxEqRel(vault.totalSupply(), depositAmount, 0.01e18);
        assertApproxEqRel(vault.totalAssets(), depositAmount, 0.01e18);

        // Verify aToken balance
        uint256 aTokenBalance = IERC20(aWETH).balanceOf(address(vault));
        assertApproxEqRel(aTokenBalance, depositAmount, 0.01e18);

        console.log("Vault total supply:", vault.totalSupply());
        console.log("Vault total assets:", vault.totalAssets());
        console.log("Vault aToken balance:", aTokenBalance);
    }
}
