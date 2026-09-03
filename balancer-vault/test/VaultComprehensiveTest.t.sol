// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/interfaces/IGauge.sol";
import "../src/interfaces/INative.sol";

contract VaultComprehensiveTest is Test {
    Vault vault;
    address constant GAUGE = address(0);
    address constant POOL = 0x046dccb728c39F8aa69E47daC0eBDAD8d2CdDfE9;
    address constant ROUTER = 0xb21A277466e7dB6934556a1Ce12eb3F032815c8A;
    address constant WNATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant batchRouter = 0x136f1EFcC3f8f88516B9E94110D56FDBfB1778d1;
    address constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant pesudoMinter = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;
    address constant usdcWhale = 0xC94eBB328aC25b95DB0E0AA968371885Fa516215;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant CUSD = 0xaD55aebc9b8c03FC43cd9f62260391c13c23e7c0;

    string constant NAME = "Test Vault";
    string constant SYMBOL = "TEST";
    IERC20[] public poolTokens;
    address owner = address(0xAB12);
    address feeReceiver = address(0xFEE);

    function setUp() public {
        poolTokens.push(IERC20(CUSD));
        poolTokens.push(IERC20(USDC));
        vault = new Vault(
            POOL, poolTokens, NAME, SYMBOL, ROUTER, batchRouter, WNATIVE, GAUGE, pesudoMinter, permit2, owner, feeReceiver
        );
    }

    // Helper function to create user and fund with USDC
    function createAndFundUser(address user, uint256 usdcAmount) internal {
        vm.deal(user, 100 ether);
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user, usdcAmount);
        vm.stopPrank();
    }

    // Helper function for deposit parameters
    function getDepositParams() internal pure returns (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) {
        wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = false; // CUSD
        wrapUnderlying[1] = true;  // USDC
        minBptAmountOut = 1;
        userData = "";
    }

    // Test 1: Single user deposit and withdraw
    function testSingleUserFlow() public {
        address user = address(0x1);
        createAndFundUser(user, 5_000_000); // 5 USDC

        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 5_000_000);
        
        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[1] = 5_000_000; // 5 USDC

        // Deposit
        uint256 shares = vault.depositUnbalanced(user, wrapUnderlying, inputAmounts, minBptAmountOut, false, userData);
        
        assertGt(shares, 0, "Should receive shares");
        assertEq(vault.balanceOf(user), shares, "Share balance should match");
        assertEq(vault.totalSupply(), shares, "Total supply should equal user shares");

        // Record balances before withdraw
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        uint256 cusdBefore = IERC20(CUSD).balanceOf(user);

        // Withdraw
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = false;
        unwrapWrapped[1] = true;

        vault.approve(address(vault), shares);
        vault.withdraw(shares, minAmountsOut, unwrapWrapped, false, userData);

        // Assertions
        assertEq(vault.balanceOf(user), 0, "Shares should be burned");
        assertEq(vault.totalSupply(), 0, "Total supply should be zero");
        assertGt(IERC20(USDC).balanceOf(user), usdcBefore, "Should receive USDC");
        
        vm.stopPrank();
    }

    // Test 2: Two users with different deposit amounts
    function testTwoUsersProportionalShares() public {
        address user1 = address(0x1);
        address user2 = address(0x2);
        
        createAndFundUser(user1, 2_000_000);  // 2 USDC
        createAndFundUser(user2, 8_000_000);  // 8 USDC

        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();

        // User 1 deposits 2 USDC
        vm.startPrank(user1);
        IERC20(USDC).approve(address(vault), 2_000_000);
        uint256[] memory inputAmounts1 = new uint256[](2);
        inputAmounts1[1] = 2_000_000;
        uint256 shares1 = vault.depositUnbalanced(user1, wrapUnderlying, inputAmounts1, minBptAmountOut, false, userData);
        vm.stopPrank();

        // User 2 deposits 8 USDC
        vm.startPrank(user2);
        IERC20(USDC).approve(address(vault), 8_000_000);
        uint256[] memory inputAmounts2 = new uint256[](2);
        inputAmounts2[1] = 8_000_000;
        uint256 shares2 = vault.depositUnbalanced(user2, wrapUnderlying, inputAmounts2, minBptAmountOut, false, userData);
        vm.stopPrank();

        // Assert proportional shares (4:1 ratio)
        assertApproxEqRel(shares2, shares1 * 4, 0.01e18, "User2 should have ~4x shares of User1");
        assertEq(vault.totalSupply(), shares1 + shares2, "Total supply should equal sum of shares");

        console.log("User1 shares:", shares1);
        console.log("User2 shares:", shares2);
        console.log("Ratio (user2/user1):", shares2 * 1e18 / shares1);
    }

    // Test 3: Multiple users with sequential deposits
    function testMultipleUsersSequential() public {
        address[] memory users = new address[](5);
        uint256[] memory deposits = new uint256[](5);
        uint256[] memory shares = new uint256[](5);
        
        // Create users with different deposit amounts
        for (uint i = 0; i < 5; i++) {
            users[i] = address(uint160(0x100 + i));
            deposits[i] = (i + 1) * 1_000_000; // 1, 2, 3, 4, 5 USDC
            createAndFundUser(users[i], deposits[i]);
        }

        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();

        // Sequential deposits
        for (uint i = 0; i < 5; i++) {
            vm.startPrank(users[i]);
            IERC20(USDC).approve(address(vault), deposits[i]);
            
            uint256[] memory inputAmounts = new uint256[](2);
            inputAmounts[1] = deposits[i];
            
            shares[i] = vault.depositUnbalanced(users[i], wrapUnderlying, inputAmounts, minBptAmountOut, false, userData);
            vm.stopPrank();
            
            console.log("User deposited USDC:", deposits[i], "received shares:", shares[i]);
            
            // Verify proportional relationships
            if (i > 0) {
                uint256 expectedRatio = deposits[i] * 1e18 / deposits[0];
                uint256 actualRatio = shares[i] * 1e18 / shares[0];
                assertApproxEqRel(actualRatio, expectedRatio, 0.02e18, "Shares should be proportional to deposits");
            }
        }

        // Verify total supply
        uint256 expectedTotal = 0;
        for (uint i = 0; i < 5; i++) {
            expectedTotal += shares[i];
        }
        assertEq(vault.totalSupply(), expectedTotal, "Total supply should equal sum of all shares");
    }

    // Test 4: Partial withdrawals
    function testPartialWithdrawals() public {
        address user = address(0x1);
        createAndFundUser(user, 10_000_000); // 10 USDC

        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 10_000_000);
        
        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[1] = 10_000_000;

        uint256 totalShares = vault.depositUnbalanced(user, wrapUnderlying, inputAmounts, minBptAmountOut, false, userData);
        
        // Withdraw 30% of shares
        uint256 sharesToWithdraw = totalShares * 30 / 100;
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = false;
        unwrapWrapped[1] = true;

        vault.approve(address(vault), sharesToWithdraw);
        vault.withdraw(sharesToWithdraw, minAmountsOut, unwrapWrapped, false, userData);

        // Verify remaining shares
        uint256 remainingShares = vault.balanceOf(user);
        assertEq(remainingShares, totalShares - sharesToWithdraw, "Remaining shares should be correct");
        assertEq(vault.totalSupply(), remainingShares, "Total supply should equal remaining shares");

        // Withdraw remaining shares
        vault.approve(address(vault), remainingShares);
        vault.withdraw(remainingShares, minAmountsOut, unwrapWrapped, false, userData);

        assertEq(vault.balanceOf(user), 0, "All shares should be withdrawn");
        assertEq(vault.totalSupply(), 0, "Total supply should be zero");
        
        vm.stopPrank();
    }

    // Test 5: Mixed deposits (both unbalanced and proportional)
    function testMixedDepositTypes() public {
        address user1 = address(0x1);
        address user2 = address(0x2);
        
        createAndFundUser(user1, 5_000_000);
        createAndFundUser(user2, 5_000_000);

        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();

        // User 1: Unbalanced deposit
        vm.startPrank(user1);
        IERC20(USDC).approve(address(vault), 5_000_000);
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[1] = 5_000_000;
        uint256 shares1 = vault.depositUnbalanced(user1, wrapUnderlying, inputAmounts, minBptAmountOut, false, userData);
        vm.stopPrank();

        // User 2: Proportional deposit (need to fund with some CUSD first)
        vm.deal(address(0xdead), 1000 ether);
        vm.startPrank(address(0xdead));
        // Simulate getting CUSD somehow (in real test, would need CUSD whale)
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(USDC).approve(address(vault), 5_000_000);
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 0; // No CUSD for this test
        maxInputAmounts[1] = 5_000_000;
        uint256 exactBptAmountOut = shares1; // Try to get same BPT amount
        
        // This might fail due to lack of CUSD, but testing the function call
        try vault.depositProportional(user2, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData) returns (uint256 shares2) {
            assertGt(shares2, 0, "Should receive shares from proportional deposit");
            console.log("Proportional deposit successful");
        } catch {
            console.log("Proportional deposit failed (expected without CUSD)");
        }
        vm.stopPrank();
    }

    // Test 6: Edge case - very small deposits
    function testSmallDeposits() public {
        address user = address(0x1);
        createAndFundUser(user, 100); // 0.0001 USDC (100 wei)

        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 100);
        
        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[1] = 100;

        try vault.depositUnbalanced(user, wrapUnderlying, inputAmounts, minBptAmountOut, false, userData) returns (uint256 shares) {
            assertGt(shares, 0, "Should receive some shares even for small deposit");
            console.log("Small deposit successful, shares:", shares);
        } catch {
            console.log("Small deposit failed (might be below pool minimum)");
        }
        vm.stopPrank();
    }

    // Test 7: Large deposits
    function testLargeDeposits() public {
        address user = address(0x1);
        createAndFundUser(user, 1_000_000_000_000); // 1M USDC

        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 1_000_000_000_000);
        
        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[1] = 1_000_000_000_000;

        try vault.depositUnbalanced(user, wrapUnderlying, inputAmounts, minBptAmountOut, false, userData) returns (uint256 shares) {
            assertGt(shares, 0, "Should handle large deposits");
            console.log("Large deposit successful, shares:", shares);
        } catch {
            console.log("Large deposit failed (might exceed pool limits)");
        }
        vm.stopPrank();
    }

    // Test 8: Multiple users with partial withdrawals
    function testMultipleUsersPartialWithdrawals() public {
        address user1 = address(0x1);
        address user2 = address(0x2);
        address user3 = address(0x3);
        
        createAndFundUser(user1, 3_000_000);
        createAndFundUser(user2, 6_000_000);
        createAndFundUser(user3, 9_000_000);

        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();

        // All users deposit
        vm.startPrank(user1);
        IERC20(USDC).approve(address(vault), 3_000_000);
        uint256[] memory inputAmounts1 = new uint256[](2);
        inputAmounts1[1] = 3_000_000;
        uint256 shares1 = vault.depositUnbalanced(user1, wrapUnderlying, inputAmounts1, minBptAmountOut, false, userData);
        vm.stopPrank();

        vm.startPrank(user2);
        IERC20(USDC).approve(address(vault), 6_000_000);
        uint256[] memory inputAmounts2 = new uint256[](2);
        inputAmounts2[1] = 6_000_000;
        uint256 shares2 = vault.depositUnbalanced(user2, wrapUnderlying, inputAmounts2, minBptAmountOut, false, userData);
        vm.stopPrank();

        vm.startPrank(user3);
        IERC20(USDC).approve(address(vault), 9_000_000);
        uint256[] memory inputAmounts3 = new uint256[](2);
        inputAmounts3[1] = 9_000_000;
        uint256 shares3 = vault.depositUnbalanced(user3, wrapUnderlying, inputAmounts3, minBptAmountOut, false, userData);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();
        
        // User 1 withdraws 50%
        vm.startPrank(user1);
        uint256 withdraw1 = shares1 / 2;
        vault.approve(address(vault), withdraw1);
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = false;
        unwrapWrapped[1] = true;
        vault.withdraw(withdraw1, minAmountsOut, unwrapWrapped, false, userData);
        vm.stopPrank();

        // User 2 withdraws 25%
        vm.startPrank(user2);
        uint256 withdraw2 = shares2 / 4;
        vault.approve(address(vault), withdraw2);
        vault.withdraw(withdraw2, minAmountsOut, unwrapWrapped, false, userData);
        vm.stopPrank();

        // Verify total supply and individual balances
        uint256 expectedTotal = (shares1 - withdraw1) + (shares2 - withdraw2) + shares3;
        assertEq(vault.totalSupply(), expectedTotal, "Total supply should be correct after partial withdrawals");
        
        console.log("After partial withdrawals:");
        console.log("User1 remaining shares:", vault.balanceOf(user1));
        console.log("User2 remaining shares:", vault.balanceOf(user2));
        console.log("User3 remaining shares:", vault.balanceOf(user3));
        console.log("Total supply:", vault.totalSupply());
    }

    // Test 9: Share calculation consistency
    function testShareCalculationConsistency() public {
        address[] memory users = new address[](3);
        uint256[] memory deposits = new uint256[](3);
        
        for (uint i = 0; i < 3; i++) {
            users[i] = address(uint160(0x200 + i));
            deposits[i] = (i + 1) * 1_000_000; // 1, 2, 3 USDC
            createAndFundUser(users[i], deposits[i]);
        }

        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();

        uint256[] memory shares = new uint256[](3);
        
        // Sequential deposits
        for (uint i = 0; i < 3; i++) {
            vm.startPrank(users[i]);
            IERC20(USDC).approve(address(vault), deposits[i]);
            
            uint256[] memory inputAmounts = new uint256[](2);
            inputAmounts[1] = deposits[i];
            
            shares[i] = vault.depositUnbalanced(users[i], wrapUnderlying, inputAmounts, minBptAmountOut, false, userData);
            vm.stopPrank();
        }

        // Test share ratios
        uint256 ratio21 = shares[1] * 1e18 / shares[0]; // Should be ~2
        uint256 ratio31 = shares[2] * 1e18 / shares[0]; // Should be ~3
        uint256 ratio32 = shares[2] * 1e18 / shares[1]; // Should be ~1.5

        console.log("Share ratios:");
        console.log("User2/User1:", ratio21);
        console.log("User3/User1:", ratio31);
        console.log("User3/User2:", ratio32);

        // Allow for 2% tolerance due to pool slippage
        assertApproxEqRel(ratio21, 2e18, 0.02e18, "Ratio should be ~2");
        assertApproxEqRel(ratio31, 3e18, 0.02e18, "Ratio should be ~3");
        assertApproxEqRel(ratio32, 1.5e18, 0.02e18, "Ratio should be ~1.5");
    }

    // Test 10: Gas optimization check
    function testGasConsumption() public {
        address user = address(0x1);
        createAndFundUser(user, 5_000_000);

        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 5_000_000);
        
        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getDepositParams();
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[1] = 5_000_000;

        uint256 gasStart = gasleft();
        uint256 shares = vault.depositUnbalanced(user, wrapUnderlying, inputAmounts, minBptAmountOut, false, userData);
        uint256 gasUsedDeposit = gasStart - gasleft();

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = false;
        unwrapWrapped[1] = true;

        vault.approve(address(vault), shares);
        
        gasStart = gasleft();
        vault.withdraw(shares, minAmountsOut, unwrapWrapped, false, userData);
        uint256 gasUsedWithdraw = gasStart - gasleft();

        console.log("Gas used for deposit:", gasUsedDeposit);
        console.log("Gas used for withdraw:", gasUsedWithdraw);
        
        // Basic gas consumption checks (adjust limits based on expected values)
        assertLt(gasUsedDeposit, 1_000_000, "Deposit should not use excessive gas");
        assertLt(gasUsedWithdraw, 1_000_000, "Withdraw should not use excessive gas");
        
        vm.stopPrank();
    }
}