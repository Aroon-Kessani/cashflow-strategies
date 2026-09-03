// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/interfaces/IGauge.sol";
import "../src/interfaces/INative.sol";
import "./IBalancerV2Swap.sol";
import "./IEqualizerRouter.sol";

// abstract MockNative is INative {
//     function deposit() external payable override {}
//     function withdraw(uint256) external override {}
//     function transferFrom(address src, address dst, uint wad) external override returns (bool) {
//         require(src != address(0) && dst != address(0), "Invalid address");
//         require(wad > 0, "Amount must be greater than zero");
//         // Mock transfer logic
//         return true;
//     }
// }

contract VaultWethOsEthTest is Test {
    // weth 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
    Vault vault;
    // TODO: Fill these with user-provided addresses
    address constant GAUGE = 0x70A1c01902DAb7a45dcA1098Ca76A8314dd8aDbA;
    address constant POOL = 0x57c23c58B1D8C3292c15BEcF07c62C5c52457A42;
    address constant ROUTER = 0xb21A277466e7dB6934556a1Ce12eb3F032815c8A;
    address constant WNATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant batchRouter = 0x136f1EFcC3f8f88516B9E94110D56FDBfB1778d1;
    address constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    //address constant bal = address(0);
    //address constant axlop = address(0);
    address constant pesudoMinter = 0x239e55F427D44C3cc793f49bFB507ebe76638a2b;
    //address equalizerRouter = address(0);

    string constant NAME = "CashFlow-WETH-osETH";
    string constant SYMBOL = "CF-WETH-osETH";
    IERC20[] public poolTokens;
    address user = address(0xABCD);
    address owner = address(0xAB12);

    function setUp() public {
        // TODO: Replace with actual WETH and osETH addresses
        poolTokens.push(IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)); // WETH
        poolTokens.push(IERC20(0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38)); // osETH
        vault = new Vault(
            POOL, poolTokens, NAME, SYMBOL, ROUTER, batchRouter, WNATIVE, GAUGE, pesudoMinter, permit2, owner, owner
        );
        vm.deal(user, 100 ether);
    }

    function testInitialSetup() public {
        assertEq(vault.name(), NAME);
        assertEq(vault.symbol(), SYMBOL);
    }

    function testdepositunbalanced() public {
        vm.startPrank(user);
        address recipient = user; // or any recipient address
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true; // WETH (wrap ETH)
        wrapUnderlying[1] = false; // osETH (not wrapping)

        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = 10 ether; // 10 ETH as WETH
        inputAmounts[1] = 0; // 0 osETH

        uint256 minBptAmountOut = 1e18; // Accept any BPT > 0 for test

        bool wethIsEth = true; // Sending ETH directly

        bytes memory userData = ""; // If not using custom userData
        uint256 vaultBalanceBefore = address(vault).balance;

        // Call example:
        vault.depositUnbalanced{value: 10 ether}(
            recipient, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData
        );
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault should not hold WETH after deposit");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault should not hold osETH after deposit");
        // Assert vault's ETH balance is zero after withdraw
        assertEq(address(vault).balance, vaultBalanceBefore, "Vault ETH balance should be zero after deposit");
        vm.stopPrank();
    }

    function testdepositunbalancedWETH() public {
        vm.startPrank(user);
        address recipient = user; // or any recipient address
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true; // WETH (wrap ETH)
        wrapUnderlying[1] = false; // osETH (not wrapping)

        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = 0.0002 ether; // 10 ETH as WETH
        inputAmounts[1] = 0; // 0 osETH

        uint256 minBptAmountOut = 1; // Accept any BPT > 0 for test

        bool wethIsEth = false; // Sending ETH directly

        bytes memory userData = ""; // If not using custom userData
        uint256 vaultBalanceBefore = address(vault).balance;
        IERC20(WNATIVE).approve(address(vault), 10 ether);
        INative(WNATIVE).deposit{value: 10 ether}();
        // Call example:
        console.log(inputAmounts[0]);
        vault.depositUnbalanced{value: 0 ether}(
            recipient, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData
        );
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault should not hold WETH after deposit");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault should not hold osETH after deposit");
        // Assert vault's ETH balance is zero after withdraw
        assertEq(address(vault).balance, vaultBalanceBefore, "Vault ETH balance should be zero after deposit");
        vm.stopPrank();
    }

    function testWithdrawAfterDepositUnbalanced() public {
        // Assume setUp() has already deposited 10 ETH as WETH for user
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        uint256 depositAmount = 10 ether;
        // Prepare deposit
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true; // WETH (wrap ETH)
        wrapUnderlying[1] = false; // osETH
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = depositAmount;
        inputAmounts[1] = 0;
        uint256 minBptAmountOut = 1e18;
        bool wethIsEth = true;
        bytes memory userData = "";
        uint256 vaultBalanceBefore = address(vault).balance;
        vm.startPrank(user);
        // Deposit 10 ETH as WETH
        uint256 shares = vault.depositUnbalanced{value: depositAmount}(
            user, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData
        );
        assertGt(shares, 0, "User should receive shares");
        assertEq(vault.balanceOf(user), shares, "User's share balance should match returned shares");
        // Prepare withdraw
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1; // Accept any amount out for test
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = true; // Unwrap WETH to ETH
        unwrapWrapped[1] = false; // osETH stays as is
        // Record user balances before
        uint256 ethBefore = user.balance;
        uint256 osEthBefore = IERC20(OSETH).balanceOf(user);
        uint256 wethBefore = IERC20(WNATIVE).balanceOf(user);
        userData = ""; // If not using custom userData
        // Approve and withdraw
        // vault.approve(address(vault), shares);
        console.log(IERC20(OSETH).balanceOf(user));
        console.log(IERC20(WNATIVE).balanceOf(user));
        vault.withdraw(
            shares,
            minAmountsOut,
            unwrapWrapped,
            false,
            userData // Pass user address in userData
        );
        console.log(IERC20(OSETH).balanceOf(user));
        console.log(IERC20(WNATIVE).balanceOf(user));
        // Assert user balances after withdraw
        assertGt(IERC20(WNATIVE).balanceOf(user), wethBefore, "User should receive WETH after withdraw");
        // User should receive ETH and osETH
        //assertGt(user.balance - ethBefore, 0, "User should receive ETH after withdraw");
        assertGt(IERC20(OSETH).balanceOf(user), osEthBefore, "User should receive osETH");
        // Shares should be burned
        assertEq(vault.balanceOf(user), 0, "User's shares should be burned after withdraw");
        // Vault should not hold underlying tokens
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault should not hold WETH after withdraw");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault should not hold osETH after withdraw");
        // Assert vault's ETH balance is zero after withdraw
        assertEq(address(vault).balance, vaultBalanceBefore, "Vault ETH balance should be zero after withdraw");
        vm.stopPrank();
    }

    function testWithdrawETHAndosETHAfterDepositUnbalanced() public {
        // Assume setUp() has already deposited 10 ETH as WETH for user
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        uint256 depositAmount = 10 ether;
        // Prepare deposit
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true; // WETH (wrap ETH)
        wrapUnderlying[1] = false; // osETH
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = depositAmount;
        inputAmounts[1] = 0;
        uint256 minBptAmountOut = 1e18;
        bool wethIsEth = true;
        bytes memory userData = "";
        uint256 vaultBalanceBefore = address(vault).balance;
        vm.startPrank(user);
        // Deposit 10 ETH as WETH
        uint256 shares = vault.depositUnbalanced{value: depositAmount}(
            user, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData
        );
        assertGt(shares, 0, "User should receive shares");
        assertEq(vault.balanceOf(user), shares, "User's share balance should match returned shares");
        // Prepare withdraw
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1; // Accept any amount out for test
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = true; // Unwrap WETH to ETH
        unwrapWrapped[1] = false; // osETH stays as is
        // Record user balances before
        uint256 ethBefore = user.balance;
        uint256 osEthBefore = IERC20(OSETH).balanceOf(user);
        uint256 wethBefore = IERC20(WNATIVE).balanceOf(user);
        userData = ""; // If not using custom userData
        // Approve and withdraw
        // vault.approve(address(vault), shares);
        vault.withdraw(
            shares,
            minAmountsOut,
            unwrapWrapped,
            true,
            userData // Pass user address in userData
        );
        // Assert user balances after withdraw
        // assertGt(
        //     IERC20(WNATIVE).balanceOf(user),
        //     wethBefore,
        //     "User should receive WETH after withdraw"
        // );
        // User should receive ETH and osETH
        assertGt(user.balance - ethBefore, 0, "User should receive ETH after withdraw");
        assertGt(IERC20(OSETH).balanceOf(user), osEthBefore, "User should receive osETH");
        // Shares should be burned
        assertEq(vault.balanceOf(user), 0, "User's shares should be burned after withdraw");
        // Vault should not hold underlying tokens
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault should not hold WETH after withdraw");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault should not hold osETH after withdraw");
        // Assert vault's ETH balance is zero after withdraw
        assertEq(address(vault).balance, vaultBalanceBefore, "Vault ETH balance should be zero after withdraw");
        vm.stopPrank();
    }

    function testWithdrawWrappedETHAndosETHAfterDepositUnbalanced() public {
        // Assume setUp() has already deposited 10 ETH as WETH for user
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        uint256 depositAmount = 10 ether;
        // Prepare deposit
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true; // WETH (wrap ETH)
        wrapUnderlying[1] = false; // osETH
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = depositAmount;
        inputAmounts[1] = 0;
        uint256 minBptAmountOut = 1e18;
        bool wethIsEth = true;
        bytes memory userData = "";
        uint256 vaultBalanceBefore = address(vault).balance;
        vm.startPrank(user);
        // Deposit 10 ETH as WETH
        uint256 shares = vault.depositUnbalanced{value: depositAmount}(
            user, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData
        );
        assertGt(shares, 0, "User should receive shares");
        assertEq(vault.balanceOf(user), shares, "User's share balance should match returned shares");
        // Prepare withdraw
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1; // Accept any amount out for test
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = false; // Unwrap WETH to ETH
        unwrapWrapped[1] = false; // osETH stays as is
        // Record user balances before
        uint256 ethBefore = user.balance;
        uint256 osEthBefore = IERC20(OSETH).balanceOf(user);
        uint256 wethBefore = IERC20(0x0bfc9d54Fc184518A81162F8fB99c2eACa081202).balanceOf(user);
        userData = ""; // If not using custom userData
        // Approve and withdraw
        // vault.approve(address(vault), shares);
        vault.withdraw(
            shares,
            minAmountsOut,
            unwrapWrapped,
            false,
            userData // Pass user address in userData
        );
        // Assert user balances after withdraw
        assertGt(
            IERC20(0x0bfc9d54Fc184518A81162F8fB99c2eACa081202).balanceOf(user),
            wethBefore,
            "User should receive WETH after withdraw"
        );
        // User should receive ETH and osETH
        //assertGt(user.balance - ethBefore, 0, "User should receive ETH after withdraw");
        assertGt(IERC20(OSETH).balanceOf(user), osEthBefore, "User should receive osETH");
        // Shares should be burned
        assertEq(vault.balanceOf(user), 0, "User's shares should be burned after withdraw");
        // Vault should not hold underlying tokens
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault should not hold WETH after withdraw");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault should not hold osETH after withdraw");
        // Assert vault's ETH balance is zero after withdraw
        assertEq(address(vault).balance, vaultBalanceBefore, "Vault ETH balance should be zero after withdraw");
        vm.stopPrank();
    }

    function testDepositUnbalancedWithdrawThenDepositProportional() public {
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        uint256 depositAmount = 10 ether;
        // Step 1: Deposit unbalanced (10 ETH as WETH)
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true; // WETH (wrap ETH)
        wrapUnderlying[1] = false; // osETH
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = depositAmount;
        inputAmounts[1] = 0;
        uint256 minBptAmountOut = 1e18;
        bool wethIsEth = true;
        bytes memory userData = abi.encodePacked(user);
        uint256 vaultBalanceBefore = address(vault).balance;
        vm.startPrank(user);
        uint256 shares = vault.depositUnbalanced{value: depositAmount}(
            user, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData
        );
        assertGt(shares, 0, "User should receive shares after unbalanced deposit");
        assertEq(vault.balanceOf(user), shares, "User's share balance should match after unbalanced deposit");
        // Step 2: Withdraw all
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapWrapped = new bool[](2);
        unwrapWrapped[0] = true; // Unwrap WETH to ETH
        unwrapWrapped[1] = false; // osETH stays as is
        vault.approve(address(vault), shares);
        uint256 userBalBeforeWithdraw = user.balance;
        vault.withdraw(shares, minAmountsOut, unwrapWrapped, wethIsEth, userData);
        assertEq(vault.balanceOf(user), 0, "User's shares should be burned after withdraw");
        assertEq(address(vault).balance, vaultBalanceBefore, "Vault ETH balance should be zero after withdraw");
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault should not hold WETH after withdraw");
        assertEq(IERC20(WNATIVE).balanceOf(address(vault)), 0, "Vault should not hold WETH after withdraw");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault should not hold osETH after withdraw");
        assertGt(user.balance, userBalBeforeWithdraw, "User should receive all ETH back after withdraw");
        // Step 3: Deposit proportional (5 ETH as WETH, 5 osETH)
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = false;
        inputAmounts[0] = 5 ether;
        inputAmounts[1] = 5 ether; // assuming osETH has 18 decimals and user has osETH
        minBptAmountOut = 1e18;
        // Give user osETH for proportional deposit
        deal(OSETH, user, 5 ether);
        IERC20(OSETH).approve(address(vault), 5 ether);
        vaultBalanceBefore = address(vault).balance;
        shares = vault.depositProportional{value: 5 ether}(
            user, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData
        );
        assertGt(shares, 0, "User should receive shares after proportional deposit");
        assertEq(vault.balanceOf(user), shares, "User's share balance should match after proportional deposit");
        assertEq(
            address(vault).balance, vaultBalanceBefore, "Vault ETH balance should be zero after proportional deposit"
        );
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault should not hold WETH after proportional deposit");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault should not hold osETH after proportional deposit");
        vm.stopPrank();
    }

    function testDepositUnbalancedEthWithdrawWethOsethThenDepositProportional() public {
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        address userAddr = user;
        // --- 1. Deposit unbalanced: 10 ETH as WETH, 0 osETH ---
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true; // WETH (wrap ETH)
        wrapUnderlying[1] = false; // osETH
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = 10 ether;
        inputAmounts[1] = 0;
        uint256 minBptAmountOut = 1e18;
        bool wethIsEth = true;
        bytes memory userData = abi.encodePacked(userAddr);
        vm.startPrank(userAddr);
        uint256 shares = vault.depositUnbalanced{value: 10 ether}(
            userAddr, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData
        );
        assertGt(shares, 0, "Should mint shares on unbalanced deposit");
        assertEq(vault.balanceOf(userAddr), shares, "User's share balance should match after unbalanced deposit");
        // --- 2. Withdraw all shares as WETH and osETH ---
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapUnderlyingWithdraw = new bool[](2);
        unwrapUnderlyingWithdraw[0] = true; // Withdraw as WETH
        unwrapUnderlyingWithdraw[1] = false; // Withdraw as osETH
        vault.approve(address(vault), shares);
        uint256 wethBefore = IERC20(WETH).balanceOf(userAddr);
        uint256 ethBefore = userAddr.balance;
        uint256 osethBefore = IERC20(OSETH).balanceOf(userAddr);
        uint256 vaultEthBalanceBefore = address(vault).balance;
        vault.withdraw(shares, minAmountsOut, unwrapUnderlyingWithdraw, false, userData);
        assertEq(vault.balanceOf(userAddr), 0, "User should have no shares after withdraw");
        // If unwrapUnderlyingWithdraw[0] is false, user should get WETH
        assertGt(IERC20(WETH).balanceOf(userAddr), wethBefore, "User should receive WETH after withdraw");
        // If unwrapUnderlyingWithdraw[0] is true, user should get ETH (add this if you want to test ETH case)
        assertEq(userAddr.balance, ethBefore, "User should not receive ETH after withdraw");
        assertGe(
            IERC20(OSETH).balanceOf(userAddr), osethBefore, "User osETH balance should not decrease after withdraw"
        );
        assertEq(address(vault).balance, vaultEthBalanceBefore, "Vault ETH balance should not increase after withdraw");
        //     // --- 3. Deposit proportional: 5 WETH, 5 osETH ---
        IERC20(WETH).approve(address(vault), 5 ether);
        IERC20(OSETH).approve(address(vault), 5 ether);
        bool[] memory wrapUnderlying2 = new bool[](2);
        wrapUnderlying2[0] = true; // WETH (already WETH)
        wrapUnderlying2[1] = false; // osETH
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 0.5 ether;
        maxInputAmounts[1] = 0.5 ether;
        uint256 exactBptAmountOut = 0.4 ether;
        uint256 shares2 =
            vault.depositProportional(userAddr, wrapUnderlying2, maxInputAmounts, exactBptAmountOut, false, userData);
        assertGt(shares2, 0, "Should mint shares on proportional deposit");
        assertEq(vault.balanceOf(userAddr), shares2, "User's share balance should match after proportional deposit");
        assertEq(
            address(vault).balance,
            vaultEthBalanceBefore,
            "Vault ETH balance should not increase after proportional deposit"
        );
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault should not hold WETH after proportional deposit");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault should not hold osETH after proportional deposit");
        vm.stopPrank();
    }

    function testDepositUnbalancedETH() public {
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        address userAddr = user;
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true; // WETH (wrap ETH)
        wrapUnderlying[1] = false; // osETH
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = 2 ether;
        inputAmounts[1] = 0;
        uint256 minBptAmountOut = 1e18;
        bool wethIsEth = true;
        bytes memory userData = abi.encodePacked(userAddr);
        vm.startPrank(userAddr);
        uint256 vaultBalanceBefore = address(vault).balance;
        uint256 shares = vault.depositUnbalanced{value: 2 ether}(
            userAddr, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData
        );
        assertGt(shares, 0, "Should mint shares on unbalanced ETH deposit");
        assertEq(vault.balanceOf(userAddr), shares, "User's share balance should match after unbalanced ETH deposit");
        // Assert vault balances
        assertEq(address(vault).balance, vaultBalanceBefore, "Vault ETH balance should be zero after deposit");
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault WETH balance should be zero after deposit");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault osETH balance should be zero after deposit");
        vm.stopPrank();
    }

    function testDepositUnbalancedWETH() public {
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        address userAddr = user;
        // Give user WETH
        deal(WNATIVE, userAddr, 2 ether);
        console.log("User WETH balance before deposit:", IERC20(WNATIVE).balanceOf(userAddr));
        console.log("User osETH balance before deposit:", IERC20(OSETH).balanceOf(userAddr));
        console.log("User WETH balance before deposit:", IERC20(WETH).balanceOf(userAddr));

        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true; // WETH (already WETH)
        wrapUnderlying[1] = false; // osETH
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = 2 ether;
        inputAmounts[1] = 0;
        uint256 minBptAmountOut = 1e18;
        bool wethIsEth = false;
        bytes memory userData = ""; //abi.encodePacked(userAddr);
        vm.startPrank(userAddr);
        uint256 vaultBalanceBefore = address(vault).balance;
        IERC20(WNATIVE).approve(address(vault), 4 ether);
        console.log(IERC20(WNATIVE).allowance(userAddr, address(vault)), "User WETH allowance to vault before deposit");
        uint256 shares =
            vault.depositUnbalanced(userAddr, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData);
        assertGt(shares, 0, "Should mint shares on unbalanced WETH deposit");
        assertEq(vault.balanceOf(userAddr), shares, "User's share balance should match after unbalanced WETH deposit");
        // Assert vault balances
        assertEq(address(vault).balance, vaultBalanceBefore, "Vault ETH balance should be zero after deposit");
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault WETH balance should be zero after deposit");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault osETH balance should be zero after deposit");
        vm.stopPrank();
    }

    function testDepositUnbalancedOsETH() public {
        address WETH = address(poolTokens[0]);
        address OSETH = address(poolTokens[1]);
        address userAddr = user;
        // Give user osETH
        deal(OSETH, userAddr, 2 ether);

        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = false; // WETH
        wrapUnderlying[1] = false; // osETH
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[0] = 0;
        inputAmounts[1] = 2 ether;
        uint256 minBptAmountOut = 1e18;
        bool wethIsEth = false;
        bytes memory userData = abi.encodePacked(userAddr);
        vm.startPrank(userAddr);
        IERC20(OSETH).approve(address(vault), 2 ether);
        console.log("User osETH balance before deposit unbal:", IERC20(OSETH).balanceOf(userAddr));
        uint256 vaultEthBalanceBefore = address(vault).balance;
        uint256 shares =
            vault.depositUnbalanced(userAddr, wrapUnderlying, inputAmounts, minBptAmountOut, wethIsEth, userData);
        assertGt(shares, 0, "Should mint shares on unbalanced osETH deposit");
        assertEq(vault.balanceOf(userAddr), shares, "User's share balance should match after unbalanced osETH deposit");
        // Assert vault balances
        assertEq(address(vault).balance, vaultEthBalanceBefore, "Vault ETH balance should be zero after deposit");
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "Vault WETH balance should be zero after deposit");
        assertEq(IERC20(OSETH).balanceOf(address(vault)), 0, "Vault osETH balance should be zero after deposit");
        vm.stopPrank();
    }
}
