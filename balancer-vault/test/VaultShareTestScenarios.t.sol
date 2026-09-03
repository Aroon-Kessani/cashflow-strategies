// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/interfaces/IGauge.sol";
import "../src/interfaces/INative.sol";

contract VaultShareTestScenarios is Test {
    Vault vault;
    address constant GAUGE = 0x70A1c01902DAb7a45dcA1098Ca76A8314dd8aDbA;
    address constant POOL = 0x57c23c58B1D8C3292c15BEcF07c62C5c52457A42;
    address constant ROUTER = 0xb21A277466e7dB6934556a1Ce12eb3F032815c8A;
    address constant WNATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant batchRouter = 0x136f1EFcC3f8f88516B9E94110D56FDBfB1778d1;
    address constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant pesudoMinter = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant OSETH = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38;

    string constant NAME = "Test Vault Share Scenarios";
    string constant SYMBOL = "TVSS";
    IERC20[] public poolTokens;
    address owner = address(0xAB12);
    address feeReceiver = address(0xFEE);

    // Test users
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address charlie = address(0xC4A4);
    address david = address(0xDA71D);
    address eve = address(0xE7E);

    function setUp() public {
        poolTokens.push(IERC20(WETH));
        poolTokens.push(IERC20(OSETH));
        vault = new Vault(
            POOL, poolTokens, NAME, SYMBOL, ROUTER, batchRouter, WNATIVE, GAUGE, pesudoMinter, permit2, owner, feeReceiver
        );
        
        // Fund all test users with ETH and osETH
        for (uint i = 0; i < 5; i++) {
            address user = [alice, bob, charlie, david, eve][i];
            vm.deal(user, 1000 ether);
            deal(OSETH, user, 1000 ether);
        }
    }

    // Helper function for deposit parameters
    function getETHDepositParams() internal pure returns (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) {
        wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;  // WETH (wrap ETH)
        wrapUnderlying[1] = false; // osETH
        minBptAmountOut = 1e18;
        userData = "";
    }

    function getOsETHDepositParams() internal pure returns (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) {
        wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = false; // WETH
        wrapUnderlying[1] = false; // osETH
        minBptAmountOut = 1e18;
        userData = "";
    }

    // Scenario 1: Equal deposits, equal shares
    function testEqualDepositsEqualShares() public {
        uint256 depositAmount = 10 ether;
        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getETHDepositParams();
        
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = depositAmount;
        inputAmounts[1] = 0;

        // Alice deposits first
        vm.startPrank(alice);
        uint256 aliceShares = vault.depositUnbalanced{value: depositAmount}(
            alice, wrapUnderlying, inputAmounts, minBptAmountOut, true, userData
        );
        vm.stopPrank();

        // Bob deposits same amount
        vm.startPrank(bob);
        uint256 bobShares = vault.depositUnbalanced{value: depositAmount}(
            bob, wrapUnderlying, inputAmounts, minBptAmountOut, true, userData
        );
        vm.stopPrank();

        console.log("Alice shares:", aliceShares);
        console.log("Bob shares:", bobShares);
        console.log("Share ratio (bob/alice):", bobShares * 1e18 / aliceShares);

        // They should have approximately equal shares (within 1% due to pool dynamics)
        assertApproxEqRel(bobShares, aliceShares, 0.01e18, "Equal deposits should give approximately equal shares");
        
        // Test withdrawals
        vm.startPrank(alice);
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = true; // Unwrap to ETH
        unwrapWrapped[1] = false;

        uint256 ethBefore = alice.balance;
        uint256 osEthBefore = IERC20(OSETH).balanceOf(alice);
        
        vault.withdraw(aliceShares, minAmountsOut, unwrapWrapped, true, userData);
        
        uint256 ethReceived = alice.balance - ethBefore;
        uint256 osEthReceived = IERC20(OSETH).balanceOf(alice) - osEthBefore;
        
        console.log("Alice withdrew ETH:", ethReceived, "osETH:", osEthReceived);
        vm.stopPrank();

        vm.startPrank(bob);
        ethBefore = bob.balance;
        osEthBefore = IERC20(OSETH).balanceOf(bob);
        
        vault.withdraw(bobShares, minAmountsOut, unwrapWrapped, true, userData);
        
        uint256 bobEthReceived = bob.balance - ethBefore;
        uint256 bobOsEthReceived = IERC20(OSETH).balanceOf(bob) - osEthBefore;
        
        console.log("Bob withdrew ETH:", bobEthReceived, "osETH:", bobOsEthReceived);
        vm.stopPrank();

        // They should receive approximately equal amounts
        assertApproxEqRel(bobEthReceived, ethReceived, 0.05e18, "Equal shares should give approximately equal ETH");
        assertApproxEqRel(bobOsEthReceived, osEthReceived, 0.05e18, "Equal shares should give approximately equal osETH");
    }

    // Scenario 2: Different deposit ratios (2:1, 3:1, 4:1)
    function testDifferentDepositRatios() public {
        uint256 baseAmount = 5 ether;
        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getETHDepositParams();
        
        uint256[] memory deposits = new uint256[](4);
        deposits[0] = baseAmount;      // 5 ETH
        deposits[1] = baseAmount * 2;  // 10 ETH  
        deposits[2] = baseAmount * 3;  // 15 ETH
        deposits[3] = baseAmount * 4;  // 20 ETH

        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = david;

        uint256[] memory shares = new uint256[](4);
        
        // Sequential deposits
        for (uint i = 0; i < 4; i++) {
            vm.startPrank(users[i]);
            uint256[] memory inputAmounts = new uint256[](2);
            inputAmounts[0] = deposits[i];
            inputAmounts[1] = 0;
            
            shares[i] = vault.depositUnbalanced{value: deposits[i]}(
                users[i], wrapUnderlying, inputAmounts, minBptAmountOut, true, userData
            );
            vm.stopPrank();
            
            console.log("User deposited ETH and got shares");
        }

        // Check ratios
        uint256 ratio21 = shares[1] * 1e18 / shares[0]; // Should be ~2
        uint256 ratio31 = shares[2] * 1e18 / shares[0]; // Should be ~3  
        uint256 ratio41 = shares[3] * 1e18 / shares[0]; // Should be ~4

        console.log("Share ratios vs first user:");
        console.log("2x deposit ratio:", ratio21);
        console.log("3x deposit ratio:", ratio31); 
        console.log("4x deposit ratio:", ratio41);

        assertApproxEqRel(ratio21, 2e18, 0.05e18, "2x deposit should give ~2x shares");
        assertApproxEqRel(ratio31, 3e18, 0.05e18, "3x deposit should give ~3x shares");
        assertApproxEqRel(ratio41, 4e18, 0.05e18, "4x deposit should give ~4x shares");

        // Test proportional withdrawals
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = true;
        unwrapWrapped[1] = false;

        uint256[] memory ethWithdrawn = new uint256[](4);
        uint256[] memory osEthWithdrawn = new uint256[](4);

        for (uint i = 0; i < 4; i++) {
            vm.startPrank(users[i]);
            uint256 ethBefore = users[i].balance;
            uint256 osEthBefore = IERC20(OSETH).balanceOf(users[i]);
            
            vault.withdraw(shares[i], minAmountsOut, unwrapWrapped, true, userData);
            
            ethWithdrawn[i] = users[i].balance - ethBefore;
            osEthWithdrawn[i] = IERC20(OSETH).balanceOf(users[i]) - osEthBefore;
            
            console.log("User withdrew ETH and osETH");
            vm.stopPrank();
        }

        // Check withdrawal ratios match deposit ratios
        uint256 ethRatio21 = ethWithdrawn[1] * 1e18 / ethWithdrawn[0];
        uint256 ethRatio31 = ethWithdrawn[2] * 1e18 / ethWithdrawn[0];
        uint256 ethRatio41 = ethWithdrawn[3] * 1e18 / ethWithdrawn[0];

        assertApproxEqRel(ethRatio21, 2e18, 0.1e18, "2x depositor should withdraw ~2x ETH");
        assertApproxEqRel(ethRatio31, 3e18, 0.1e18, "3x depositor should withdraw ~3x ETH");
        assertApproxEqRel(ethRatio41, 4e18, 0.1e18, "4x depositor should withdraw ~4x ETH");
    }

    // Scenario 3: Mixed token deposits (ETH vs osETH)
    function testMixedTokenDeposits() public {
        uint256 depositAmount = 10 ether;

        // Alice deposits ETH
        vm.startPrank(alice);
        (bool[] memory wrapUnderlying1, uint256 minBptAmountOut1, bytes memory userData1) = getETHDepositParams();
        uint256[] memory inputAmounts1 = new uint256[](2);
        inputAmounts1[0] = depositAmount;
        inputAmounts1[1] = 0;
        
        uint256 aliceShares = vault.depositUnbalanced{value: depositAmount}(
            alice, wrapUnderlying1, inputAmounts1, minBptAmountOut1, true, userData1
        );
        vm.stopPrank();

        // Bob deposits osETH
        vm.startPrank(bob);
        (bool[] memory wrapUnderlying2, uint256 minBptAmountOut2, bytes memory userData2) = getOsETHDepositParams();
        uint256[] memory inputAmounts2 = new uint256[](2);
        inputAmounts2[0] = 0;
        inputAmounts2[1] = depositAmount;
        
        IERC20(OSETH).approve(address(vault), depositAmount);
        uint256 bobShares = vault.depositUnbalanced(
            bob, wrapUnderlying2, inputAmounts2, minBptAmountOut2, false, userData2
        );
        vm.stopPrank();

        console.log("Alice (ETH depositor) shares:", aliceShares);
        console.log("Bob (osETH depositor) shares:", bobShares);
        console.log("Share ratio (bob/alice):", bobShares * 1e18 / aliceShares);

        // Test withdrawals - both should get proportional amounts of both tokens
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = true;
        unwrapWrapped[1] = false;

        // Alice withdraws
        vm.startPrank(alice);
        uint256 aliceEthBefore = alice.balance;
        uint256 aliceOsEthBefore = IERC20(OSETH).balanceOf(alice);
        
        vault.withdraw(aliceShares, minAmountsOut, unwrapWrapped, true, userData1);
        
        uint256 aliceEthReceived = alice.balance - aliceEthBefore;
        uint256 aliceOsEthReceived = IERC20(OSETH).balanceOf(alice) - aliceOsEthBefore;
        vm.stopPrank();

        // Bob withdraws  
        vm.startPrank(bob);
        uint256 bobEthBefore = bob.balance;
        uint256 bobOsEthBefore = IERC20(OSETH).balanceOf(bob);
        
        vault.withdraw(bobShares, minAmountsOut, unwrapWrapped, true, userData2);
        
        uint256 bobEthReceived = bob.balance - bobEthBefore;
        uint256 bobOsEthReceived = IERC20(OSETH).balanceOf(bob) - bobOsEthBefore;
        vm.stopPrank();

        console.log("Alice received ETH:", aliceEthReceived, "osETH:", aliceOsEthReceived);
        console.log("Bob received ETH:", bobEthReceived, "osETH:", bobOsEthReceived);

        // Both should receive some of each token (due to pool composition)
        assertGt(aliceEthReceived, 0, "Alice should receive some ETH");
        assertGt(aliceOsEthReceived, 0, "Alice should receive some osETH");
        assertGt(bobEthReceived, 0, "Bob should receive some ETH");
        assertGt(bobOsEthReceived, 0, "Bob should receive some osETH");
    }

    // Scenario 4: Time-delayed deposits (simulating pool state changes)
    function testTimeDelayedDeposits() public {
        uint256 depositAmount = 10 ether;
        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getETHDepositParams();
        
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = depositAmount;
        inputAmounts[1] = 0;

        // Alice deposits first
        vm.startPrank(alice);
        uint256 aliceShares = vault.depositUnbalanced{value: depositAmount}(
            alice, wrapUnderlying, inputAmounts, minBptAmountOut, true, userData
        );
        vm.stopPrank();

        // Advance time by 1 day
        vm.warp(block.timestamp + 1 days);

        // Bob deposits after time delay
        vm.startPrank(bob);
        uint256 bobShares = vault.depositUnbalanced{value: depositAmount}(
            bob, wrapUnderlying, inputAmounts, minBptAmountOut, true, userData
        );
        vm.stopPrank();

        // Advance time by another day
        vm.warp(block.timestamp + 1 days);

        // Charlie deposits after more time
        vm.startPrank(charlie);
        uint256 charlieShares = vault.depositUnbalanced{value: depositAmount}(
            charlie, wrapUnderlying, inputAmounts, minBptAmountOut, true, userData
        );
        vm.stopPrank();

        console.log("Time-delayed deposits:");
        console.log("Alice (T+0) shares:", aliceShares);
        console.log("Bob (T+1d) shares:", bobShares);
        console.log("Charlie (T+2d) shares:", charlieShares);

        // All should have similar shares since deposits are equal
        assertApproxEqRel(bobShares, aliceShares, 0.02e18, "Time delay shouldn't significantly affect shares");
        assertApproxEqRel(charlieShares, aliceShares, 0.02e18, "Time delay shouldn't significantly affect shares");
    }

    // Scenario 5: Partial withdrawals and remaining balances
    function testPartialWithdrawalsAndBalances() public {
        uint256 depositAmount = 20 ether;
        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getETHDepositParams();
        
        // Alice and Bob make equal deposits
        vm.startPrank(alice);
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = depositAmount;
        inputAmounts[1] = 0;
        uint256 aliceShares = vault.depositUnbalanced{value: depositAmount}(
            alice, wrapUnderlying, inputAmounts, minBptAmountOut, true, userData
        );
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 bobShares = vault.depositUnbalanced{value: depositAmount}(
            bob, wrapUnderlying, inputAmounts, minBptAmountOut, true, userData
        );
        vm.stopPrank();

        // Alice withdraws 25%, Bob withdraws 50%
        uint256 aliceWithdraw = aliceShares * 25 / 100;
        uint256 bobWithdraw = bobShares * 50 / 100;

        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = true;
        unwrapWrapped[1] = false;

        // Alice partial withdraw
        vm.startPrank(alice);
        uint256 aliceEthBefore = alice.balance;
        vault.withdraw(aliceWithdraw, minAmountsOut, unwrapWrapped, true, userData);
        uint256 aliceEthReceived = alice.balance - aliceEthBefore;
        vm.stopPrank();

        // Bob partial withdraw
        vm.startPrank(bob);
        uint256 bobEthBefore = bob.balance;
        vault.withdraw(bobWithdraw, minAmountsOut, unwrapWrapped, true, userData);
        uint256 bobEthReceived = bob.balance - bobEthBefore;
        vm.stopPrank();

        console.log("Partial withdrawals:");
        console.log("Alice withdrew 25% shares, received ETH:", aliceEthReceived);
        console.log("Bob withdrew 50% shares, received ETH:", bobEthReceived);
        console.log("ETH ratio (bob/alice):", bobEthReceived * 1e18 / aliceEthReceived);

        // Bob should receive ~2x Alice's withdrawal (50% vs 25%)
        assertApproxEqRel(bobEthReceived, aliceEthReceived * 2, 0.05e18, "50% withdrawal should be ~2x 25% withdrawal");

        // Check remaining balances
        uint256 aliceRemaining = vault.balanceOf(alice);
        uint256 bobRemaining = vault.balanceOf(bob);
        
        assertEq(aliceRemaining, aliceShares - aliceWithdraw, "Alice remaining shares should be correct");
        assertEq(bobRemaining, bobShares - bobWithdraw, "Bob remaining shares should be correct");

        console.log("Remaining shares:");
        console.log("Alice remaining:", aliceRemaining);
        console.log("Bob remaining:", bobRemaining);

        // Final withdrawals should be proportional to remaining shares
        vm.startPrank(alice);
        aliceEthBefore = alice.balance;
        vault.withdraw(aliceRemaining, minAmountsOut, unwrapWrapped, true, userData);
        uint256 aliceFinalEth = alice.balance - aliceEthBefore;
        vm.stopPrank();

        vm.startPrank(bob);
        bobEthBefore = bob.balance;
        vault.withdraw(bobRemaining, minAmountsOut, unwrapWrapped, true, userData);
        uint256 bobFinalEth = bob.balance - bobEthBefore;
        vm.stopPrank();

        console.log("Final withdrawals:");
        console.log("Alice final ETH:", aliceFinalEth);
        console.log("Bob final ETH:", bobFinalEth);

        // Alice should get more in final withdrawal (75% vs 50% remaining)
        assertGt(aliceFinalEth, bobFinalEth, "Alice should get more in final withdrawal");
    }

    // Scenario 6: Large number of users with random deposit amounts
    function testManyUsersRandomDeposits() public {
        uint256 numUsers = 5;
        address[] memory users = new address[](numUsers);
        uint256[] memory deposits = new uint256[](numUsers);
        uint256[] memory shares = new uint256[](numUsers);
        
        // Create more users and set deposits (using pseudo-random but deterministic amounts)
        for (uint i = 0; i < numUsers; i++) {
            users[i] = address(uint160(0x1000 + i));
            vm.deal(users[i], 1000 ether);
            
            // Pseudo-random deposits between 1-50 ETH
            deposits[i] = (1 + (i * 7) % 50) * 1 ether;
        }

        (bool[] memory wrapUnderlying, uint256 minBptAmountOut, bytes memory userData) = getETHDepositParams();

        // All users deposit
        uint256 totalDeposited = 0;
        uint256 totalShares = 0;
        
        for (uint i = 0; i < numUsers; i++) {
            vm.startPrank(users[i]);
            uint256[] memory inputAmounts = new uint256[](2);
            inputAmounts[0] = deposits[i];
            inputAmounts[1] = 0;
            
            shares[i] = vault.depositUnbalanced{value: deposits[i]}(
                users[i], wrapUnderlying, inputAmounts, minBptAmountOut, true, userData
            );
            
            totalDeposited += deposits[i];
            totalShares += shares[i];
            vm.stopPrank();
            
            console.log("User deposited ETH and got shares");
        }

        console.log("Total deposited and total shares calculated");
        assertEq(vault.totalSupply(), totalShares, "Total supply should match sum of shares");

        // Test that share ratios match deposit ratios (compare first user to others)
        for (uint i = 1; i < numUsers; i++) {
            uint256 expectedShareRatio = deposits[i] * 1e18 / deposits[0];
            uint256 actualShareRatio = shares[i] * 1e18 / shares[0];
            
            // Allow for 5% tolerance due to pool dynamics with many users
            assertApproxEqRel(actualShareRatio, expectedShareRatio, 0.05e18, "Share ratio should match deposit ratio");
        }

        // Random withdrawals - some users withdraw all, some partial
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = true;
        unwrapWrapped[1] = false;

        uint256 totalWithdrawnEth = 0;
        
        for (uint i = 0; i < numUsers; i++) {
            vm.startPrank(users[i]);
            
            // Withdraw percentage based on user index (10% to 100%)
            uint256 withdrawPercent = 10 + (i * 10); // 10%, 20%, 30%... 100%
            if (withdrawPercent > 100) withdrawPercent = 100;
            
            uint256 sharesToWithdraw = shares[i] * withdrawPercent / 100;
            
            uint256 ethBefore = users[i].balance;
            vault.withdraw(sharesToWithdraw, minAmountsOut, unwrapWrapped, true, userData);
            uint256 ethReceived = users[i].balance - ethBefore;
            
            totalWithdrawnEth += ethReceived;
            
            console.log("User withdrew percent and ETH:", withdrawPercent, ethReceived);
            vm.stopPrank();
        }

        console.log("Total ETH withdrawn:", totalWithdrawnEth);
        
        // Verify total withdrawn is reasonable compared to total deposited
        // (Should be less due to some users not withdrawing 100%)
        assertLt(totalWithdrawnEth, totalDeposited, "Total withdrawn should be less than total deposited");
        assertGt(totalWithdrawnEth, totalDeposited / 2, "Total withdrawn should be substantial");
    }
}