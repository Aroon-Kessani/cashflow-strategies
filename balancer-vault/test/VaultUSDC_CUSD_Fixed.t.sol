// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/interfaces/IGauge.sol";
import "../src/interfaces/INative.sol";

contract VaultUSDC_CUSDTestFixed is Test {
    Vault vault;
    address constant GAUGE = address(0);
    address constant POOL = 0x046dccb728c39F8aa69E47daC0eBDAD8d2CdDfE9;
    address constant ROUTER = 0xb21A277466e7dB6934556a1Ce12eb3F032815c8A;
    address constant WNATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant batchRouter = 0x136f1EFcC3f8f88516B9E94110D56FDBfB1778d1;
    address constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant pesudoMinter = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;

    string constant NAME = "CashFlow-cUSDC-USDC";
    string constant SYMBOL = "CF-cUSDC-USDC";
    IERC20[] public poolTokens;
    address user = address(0xABCD);
    address owner = address(0xAB12);

    function setUp() public {
        poolTokens.push(IERC20(0xaD55aebc9b8c03FC43cd9f62260391c13c23e7c0)); // CUSD
        poolTokens.push(IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)); // USDC
        vault = new Vault(
            POOL, poolTokens, NAME, SYMBOL, ROUTER, batchRouter, WNATIVE, GAUGE, pesudoMinter, permit2, owner, owner
        );
        vm.deal(user, 100 ether);
    }

    function testTwoUsersDepositWithdrawUSDC() public {
        address usdcWhale = 0xC94eBB328aC25b95DB0E0AA968371885Fa516215;
        address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address CUSD = 0xaD55aebc9b8c03FC43cd9f62260391c13c23e7c0;
        
        address user1 = address(0x1111);
        address user2 = address(0x2222);
        
        // Fund users with USDC from whale
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user1, 1000000); // 1 USDC (6 decimals)
        IERC20(USDC).transfer(user2, 20000000); // 20 USDC (6 decimals)
        vm.stopPrank();

        // User 1 deposits 1 USDC
        vm.startPrank(user1);
        IERC20(USDC).approve(address(vault), 1000000);
        
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = false; // CUSD
        wrapUnderlying[1] = true; // USDC
        
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = 0; // 0 CUSD
        inputAmounts[1] = 1000000; // 1 USDC
        
        uint256 minBptAmountOut = 1;
        bytes memory userData = "";
        
        uint256 shares1 = vault.depositUnbalanced(
            user1, wrapUnderlying, inputAmounts, minBptAmountOut, false, userData
        );
        
        console.log("After User1 deposit:");
        console.log("  User1 shares:", shares1);
        console.log("  Total supply:", vault.totalSupply());
        console.log("  Pool balance:", IERC20(POOL).balanceOf(address(vault)));
        console.log("  Vault USDC:", IERC20(USDC).balanceOf(address(vault)));
        console.log("  Vault CUSD:", IERC20(CUSD).balanceOf(address(vault)));
        
        assertGt(shares1, 0, "User1 should receive shares");
        assertEq(vault.balanceOf(user1), shares1, "User1 share balance should match");
        vm.stopPrank();

        // User 2 deposits 20 USDC
        vm.startPrank(user2);
        IERC20(USDC).approve(address(vault), 20000000);
        
        inputAmounts[1] = 20000000; // 20 USDC
        
        uint256 shares2 = vault.depositUnbalanced(
            user2, wrapUnderlying, inputAmounts, minBptAmountOut, false, userData
        );
        
        console.log("After User2 deposit:");
        console.log("  User2 shares:", shares2);
        console.log("  Total supply:", vault.totalSupply());
        console.log("  Pool balance:", IERC20(POOL).balanceOf(address(vault)));
        console.log("  Vault USDC:", IERC20(USDC).balanceOf(address(vault)));
        console.log("  Vault CUSD:", IERC20(CUSD).balanceOf(address(vault)));
        console.log("  Shares ratio (user2/user1):", shares2 * 1e18 / shares1);
        
        assertGt(shares2, 0, "User2 should receive shares");
        assertEq(vault.balanceOf(user2), shares2, "User2 share balance should match");
        vm.stopPrank();

        // Record initial balances before withdrawals
        uint256 user1USDCBefore = IERC20(USDC).balanceOf(user1);
        uint256 user1CUSDBefore = IERC20(CUSD).balanceOf(user1);
        uint256 user2USDCBefore = IERC20(USDC).balanceOf(user2);
        uint256 user2CUSDBefore = IERC20(CUSD).balanceOf(user2);

        // User 1 withdraws all shares
        vm.startPrank(user1);
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1; // Min CUSD
        minAmountsOut[1] = 1; // Min USDC
        
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = false; // CUSD
        unwrapWrapped[1] = true; // USDC
        
        vault.approve(address(vault), shares1);
        (address[] memory tokensOut1, uint256[] memory amountsOut1) = vault.withdraw(
            shares1, minAmountsOut, unwrapWrapped, false, userData
        );
        
        uint256 user1USDCReceived = IERC20(USDC).balanceOf(user1) - user1USDCBefore;
        uint256 user1CUSDReceived = IERC20(CUSD).balanceOf(user1) - user1CUSDBefore;
        
        console.log("User1 withdrawal:");
        console.log("  USDC received:", user1USDCReceived);
        console.log("  CUSD received:", user1CUSDReceived);
        
        assertGt(user1USDCReceived, 0, "User1 should receive USDC");
        assertEq(vault.balanceOf(user1), 0, "User1 shares should be burned");
        vm.stopPrank();

        // User 2 withdraws all shares
        vm.startPrank(user2);
        vault.approve(address(vault), shares2);
        (address[] memory tokensOut2, uint256[] memory amountsOut2) = vault.withdraw(
            shares2, minAmountsOut, unwrapWrapped, false, userData
        );
        
        uint256 user2USDCReceived = IERC20(USDC).balanceOf(user2) - user2USDCBefore;
        uint256 user2CUSDReceived = IERC20(CUSD).balanceOf(user2) - user2CUSDBefore;
        
        console.log("User2 withdrawal:");
        console.log("  USDC received:", user2USDCReceived);
        console.log("  CUSD received:", user2CUSDReceived);
        
        assertGt(user2USDCReceived, 0, "User2 should receive USDC");
        assertEq(vault.balanceOf(user2), 0, "User2 shares should be burned");
        vm.stopPrank();

        // Assert vault is empty after all withdrawals
        assertEq(vault.totalSupply(), 0, "Vault should have no shares after all withdrawals");
        assertEq(IERC20(POOL).balanceOf(address(vault)), 0, "Vault should not hold pool tokens");
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "Vault should not hold USDC");
        assertEq(IERC20(CUSD).balanceOf(address(vault)), 0, "Vault should not hold CUSD");
        
        console.log("=== SUMMARY ===");
        console.log("User1 deposited 1 USDC, received USDC:", user1USDCReceived, "CUSD:", user1CUSDReceived);
        console.log("User2 deposited 20 USDC, received USDC:", user2USDCReceived, "CUSD:", user2CUSDReceived);
    }
}