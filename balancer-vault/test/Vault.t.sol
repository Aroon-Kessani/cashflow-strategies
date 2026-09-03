// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/Vault.sol";
import "../src/interfaces/IGauge.sol";
import "../src/interfaces/INative.sol";
import "./IBalancerV2Swap.sol";
import "./IEqualizerRouter.sol";

contract VaultTest is Test {
    Vault vault;
    address constant GAUGE = 0x70DB188E5953f67a4B16979a2ceA26248b315401;
    address constant POOL = 0x7AB124EC4029316c2A42F713828ddf2a192B36db;
    address constant ROUTER = 0x9dA18982a33FD0c7051B19F0d7C76F2d5E7e017c;
    address constant WNATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant batchRouter = 0x85a80afee867aDf27B50BdB7b76DA70f1E853062;
    address constant permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant bal = 0x4158734D47Fc9692176B5085E0F52ee0Da5d47F1;
    address constant axlop = 0x994ac01750047B9d35431a7Ae4Ed312ee955E030;
    address constant pesudoMinter = 0x0c5538098EBe88175078972F514C9e101D325D4F;
    address equalizerRouter = 0x2F87Bf58D5A9b2eFadE55Cdbd46153a0902be6FA;

    string constant NAME = "CashFlow-GHO-USDC";
    string constant SYMBOL = "CF-GHO-USDC";
    IERC20[] public poolTokens;

    address user = address(0xABCD);
    address owner = address(0xAB12);

    function setUp() public {
        poolTokens.push(IERC20(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee));
        poolTokens.push(IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913));
        vault = new Vault(
            POOL, poolTokens, NAME, SYMBOL, ROUTER, batchRouter, WNATIVE, GAUGE, pesudoMinter, permit2, owner, owner
        );
        vm.deal(user, 100 ether);
    }

    function testImpersonateAndDepositUnbalancedUSDC() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        vm.startPrank(usdcWhale);
        uint256 usdcBalanceBefore = IERC20(USDC).balanceOf(usdcWhale);
        IERC20(USDC).approve(address(vault), usdcBalanceBefore);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory inputAmounts = new uint256[](2);
        inputAmounts[1] = usdcBalanceBefore;
        uint256 minBptAmountOut = 1e18;
        bytes memory userData = "";
        // revert because pool is surgiging
        vm.expectRevert();
        vault.depositUnbalanced(usdcWhale, wrapUnderlying, inputAmounts, minBptAmountOut, false, userData);
        vm.stopPrank();
        // Assert vault and user state after revert (should be unchanged)
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "Vault should not hold USDC after failed deposit");
        assertEq(IERC20(USDC).balanceOf(usdcWhale), usdcBalanceBefore, "User should retain USDC after failed deposit");
        assertEq(vault.totalSupply(), 0, "No shares should be minted after failed deposit");
    }

    function testdepositProportional() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user, 200e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user, 400e18);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 200e6);
        IERC20(GHO).approve(address(vault), 400e18);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 4e18;
        maxInputAmounts[1] = 2e6;
        uint256 exactBptAmountOut = 1e18;
        bytes memory userData = "";
        uint256 shares =
            vault.depositProportional(user, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        // Assert user received shares
        assertGt(shares, 0, "User should receive shares");
        assertEq(vault.balanceOf(user), shares, "User's share balance should match returned shares");
        // Assert vault does not hold underlying tokens
        assertEq(IERC20(GHO).balanceOf(address(vault)), 0, "Vault should not hold GHO");
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "Vault should not hold USDC");
        // Assert vault does not hold pool tokens
        assertEq(IERC20(POOL).balanceOf(address(vault)), 0, "Vault should not hold pool tokens");
        // Assert gauge holds pool tokens
        assertGt(IERC20(POOL).balanceOf(address(GAUGE)), 0, "Gauge should hold pool tokens");
        // Assert vault holds gauge tokens
        assertGt(IERC20(GAUGE).balanceOf(address(vault)), 0, "Vault should hold gauge tokens");
        // Assert user does not hold pool tokens
        assertEq(IERC20(POOL).balanceOf(user), 0, "User should not hold pool tokens");
        // Assert user does not hold gauge tokens
        assertEq(IERC20(GAUGE).balanceOf(user), 0, "User should not hold gauge tokens");
        // Assert total supply matches shares
        assertEq(vault.totalSupply(), shares, "Total supply should match shares after single deposit");
        vm.stopPrank();
    }

    function testWithdraw() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user, 2e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user, 4e18);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 2e6);
        IERC20(GHO).approve(address(vault), 4e18);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 4e18;
        maxInputAmounts[1] = 2e6;
        uint256 exactBptAmountOut = 1e18;
        bytes memory userData = "";
        vault.depositProportional(user, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);

        // Verify state after deposit
        assertEq(IERC20(GHO).balanceOf(address(vault)), 0, "Vault should not hold GHO after deposit");
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "Vault should not hold USDC after deposit");
        assertEq(IERC20(POOL).balanceOf(address(vault)), 0, "vault should not hold pool tokens after deposit");
        assertGt(IERC20(GAUGE).balanceOf(address(vault)), 0, "vault should hold guage tokens after deposit");
        uint256 shares = vault.balanceOf(user);
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        vault.approve(address(vault), shares);
        bool[] memory unwrapUnderlying = new bool[](2);
        unwrapUnderlying[0] = true;
        unwrapUnderlying[1] = true;

        // Initial user balances before withdraw
        uint256 ghoBeforeWithdraw = IERC20(GHO).balanceOf(user);
        uint256 usdcBeforeWithdraw = IERC20(USDC).balanceOf(user);

        (address[] memory tokensOut, uint256[] memory amountsOut) =
            vault.withdraw(shares, minAmountsOut, unwrapUnderlying, false, userData);

        // Assert user received tokens
        assertGt(IERC20(GHO).balanceOf(user) - ghoBeforeWithdraw, 0, "User should receive GHO");
        assertGt(IERC20(USDC).balanceOf(user) - usdcBeforeWithdraw, 0, "User should receive USDC");
        // Assert vault does not hold underlying tokens
        assertEq(IERC20(GHO).balanceOf(address(vault)), 0, "Vault should not hold GHO after withdraw");
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "Vault should not hold USDC after withdraw");
        // Assert vault does not hold pool or gauge tokens
        assertEq(IERC20(POOL).balanceOf(address(vault)), 0, "Vault should have no pool tokens after withdraw");
        assertEq(IERC20(GAUGE).balanceOf(address(vault)), 0, "Vault should not hold gauge tokens after withdraw");
        // Assert user does not hold pool or gauge tokens
        assertEq(IERC20(POOL).balanceOf(user), 0, "User should not hold pool tokens after withdraw");
        assertEq(IERC20(GAUGE).balanceOf(user), 0, "User should not hold gauge tokens after withdraw");
        // Assert shares burned
        assertEq(vault.balanceOf(user), 0, "User's shares should be burned after withdraw");
        // Assert correct output array lengths
        assertEq(tokensOut.length, 2, "Should return 2 tokens");
        assertEq(amountsOut.length, 2, "Should return 2 amounts");
        // Assert vault is empty
        assertEq(vault.totalSupply(), 0, "Vault should have no shares after full withdraw");
        vm.stopPrank();
    }

    // function testWithdrawAndSwap_GHOtoUSDC() public {
    //     address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
    //     address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
    //     address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    //     address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
    //     vm.startPrank(usdcWhale);
    //     IERC20(USDC).transfer(user, 200e6);
    //     vm.stopPrank();
    //     vm.startPrank(ghoWhale);
    //     IERC20(GHO).transfer(user, 400e18);
    //     vm.stopPrank();
    //     vm.startPrank(user);
    //     IERC20(USDC).approve(address(vault), 200e6);
    //     IERC20(GHO).approve(address(vault), 400e18);
    //     bool[] memory wrapUnderlying = new bool[](2);
    //     wrapUnderlying[0] = true;
    //     wrapUnderlying[1] = true;
    //     uint256[] memory maxInputAmounts = new uint256[](2);
    //     maxInputAmounts[0] = 400e18;
    //     maxInputAmounts[1] = 200e6;
    //     uint256 exactBptAmountOut = 10e18;
    //     bytes memory userData = "";
    //     vault.depositProportional(user, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);

    //     // Verify state after deposit
    //     assertEq(IERC20(GHO).balanceOf(address(vault)), 0, "Vault should not hold GHO after deposit");
    //     assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "Vault should not hold USDC after deposit");
    //     assertEq(IERC20(POOL).balanceOf(address(vault)), 0, "vault should not hold pool tokens after deposit");
    //     assertGt(IERC20(GAUGE).balanceOf(address(vault)), 0, "vault should hold guage tokens after deposit");

    //     uint256 shares = vault.balanceOf(user);
    //     uint256[] memory minAmountsOut = new uint256[](2);
    //     minAmountsOut[0] = 1;
    //     minAmountsOut[1] = 1;
    //     bool[] memory unwrapUnderlying = new bool[](2);
    //     unwrapUnderlying[0] = true;
    //     unwrapUnderlying[1] = true;
    //     IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](5);
    //     steps[0] = IBatchRouter.SwapPathStep({
    //         pool: 0xE0fC89d4971794128255F35739428a64A839C5cB,
    //         tokenOut: IERC20(0x4200000000000000000000000000000000000006),
    //         isBuffer: false
    //     });
    //     steps[1] = IBatchRouter.SwapPathStep({
    //         pool: 0xe298b938631f750DD409fB18227C4a23dCdaab9b,
    //         tokenOut: IERC20(0xe298b938631f750DD409fB18227C4a23dCdaab9b),
    //         isBuffer: true
    //     });
    //     steps[2] = IBatchRouter.SwapPathStep({
    //         pool: 0x4Fbb7870DBE7A7Ef4866A33c0eED73D395730dc0,
    //         tokenOut: IERC20(0xC768c589647798a6EE01A91FdE98EF2ed046DBD6),
    //         isBuffer: false
    //     });
    //     steps[3] = IBatchRouter.SwapPathStep({
    //         pool: 0x7AB124EC4029316c2A42F713828ddf2a192B36db,
    //         tokenOut: IERC20(0x88b1Cd4b430D95b406E382C3cDBaE54697a0286E),
    //         isBuffer: false
    //     });
    //     steps[4] = IBatchRouter.SwapPathStep({
    //         pool: 0x88b1Cd4b430D95b406E382C3cDBaE54697a0286E,
    //         tokenOut: IERC20(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee),
    //         isBuffer: true
    //     });
    //     IBatchRouter.SwapPathExactAmountIn[] memory swapPaths = new IBatchRouter.SwapPathExactAmountIn[](1);
    //     swapPaths[0] = IBatchRouter.SwapPathExactAmountIn({
    //         tokenIn: IERC20(USDC),
    //         steps: steps,
    //         exactAmountIn: 1e6,
    //         minAmountOut: 1e9
    //     });
    //     uint256 swapDeadline = block.timestamp;

    //     // Initial user balances before withdrawAndSwap
    //     uint256 ghoBeforeWithdraw = IERC20(GHO).balanceOf(user);
    //     uint256 usdcBeforeWithdraw = IERC20(USDC).balanceOf(user);

    //     vault.withdrawAndSwap(shares, minAmountsOut, unwrapUnderlying, false, userData, swapPaths, swapDeadline);

    //     // Assert user received tokens
    //     assertGt(IERC20(GHO).balanceOf(user) - ghoBeforeWithdraw, 0, "User should receive GHO");
    //     assertGt(IERC20(USDC).balanceOf(user) - usdcBeforeWithdraw, 0, "User should receive USDC");
    //     // Assert vault does not hold underlying tokens
    //     assertEq(IERC20(GHO).balanceOf(address(vault)), 0, "Vault should not hold GHO after withdrawAndSwap");
    //     assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "Vault should not hold USDC after withdrawAndSwap");
    //     // Assert vault does not hold pool or gauge tokens
    //     assertEq(IERC20(POOL).balanceOf(address(vault)), 0, "Vault should have no pool tokens after withdrawAndSwap");
    //     assertEq(IERC20(GAUGE).balanceOf(address(vault)), 0, "Vault should not hold gauge tokens after withdrawAndSwap");
    //     // Assert user does not hold pool or gauge tokens
    //     assertEq(IERC20(POOL).balanceOf(user), 0, "User should not hold pool tokens after withdrawAndSwap");
    //     assertEq(IERC20(GAUGE).balanceOf(user), 0, "User should not hold gauge tokens after withdrawAndSwap");
    //     // Assert shares burned
    //     assertEq(vault.balanceOf(user), 0, "User's shares should be burned after withdrawAndSwap");
    //     // Assert vault is empty
    //     assertEq(vault.totalSupply(), 0, "Vault should have no shares after full withdrawAndSwap");
    //     vm.stopPrank();
    // }

    function testMulticall_ClaimRewards() public {
        // Setup: deposit to vault
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        address BAL = 0x4158734D47Fc9692176B5085E0F52ee0Da5d47F1;
        // Transfer tokens to user
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user, 2000e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user, 4000e18);
        vm.stopPrank();
        // User approves vault
        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 2000e6);
        IERC20(GHO).approve(address(vault), 4000e18);
        // Deposit to vault
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 4000e18;
        maxInputAmounts[1] = 2000e6;
        uint256 exactBptAmountOut = 1000e18;
        bytes memory userData = "";
        vault.depositProportional(user, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        IERC20(USDC).transfer(address(vault), 100e6);
        vm.stopPrank();
        // Advance time to simulate reward accumulation
        vm.warp(block.timestamp + 8 days);

        assertEq(IERC20(bal).balanceOf(address(vault)), 0);
        assertEq(IERC20(axlop).balanceOf(address(vault)), 0);
        vault.claimRewards();
        assertGt(IERC20(bal).balanceOf(address(vault)), 0);
        assertGt(IERC20(axlop).balanceOf(address(vault)), 0);
        address balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        vm.startPrank(owner);
        vault.approve(bal, balancerVault, type(uint256).max);
        vault.approve(axlop, equalizerRouter, type(uint256).max);
        vault.setMulticallWhitelist(balancerVault, true);
        vault.setMulticallWhitelist(equalizerRouter, true);
        vault.setMulticallWhitelist(batchRouter, true);
        vault.setMulticallWhitelist(address(vault), true);
        vault.setMulticallWhitelist(owner, true);
        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);
        bytes32 poolId = 0xb328b50f1f7d97ee8ea391ab5096dd7657555f49000100000000000000000048;

        uint256 balBalance = IERC20(BAL).balanceOf(address(vault));
        // Build SingleSwap struct for Balancer V2
        IBalancerV2Swap.SingleSwap memory singleSwap = IBalancerV2Swap.SingleSwap({
            poolId: poolId,
            kind: IBalancerV2Swap.SwapKind.GIVEN_IN,
            assetIn: address(BAL),
            assetOut: address(USDC),
            amount: balBalance,
            userData: ""
        });
        IBalancerV2Swap.FundManagement memory funds = IBalancerV2Swap.FundManagement({
            sender: address(vault),
            fromInternalBalance: false,
            recipient: payable(address(vault)),
            toInternalBalance: false
        });
        uint256 limit = 1; // Accept any amount out for test
        uint256 deadline = block.timestamp + 1 hours;
        // Encode call to Balancer Vault swap
        bytes memory swapCalldata =
            abi.encodeWithSelector(IBalancerV2Swap.swap.selector, singleSwap, funds, limit, deadline);
        targets[0] = balancerVault;
        data[0] = swapCalldata;
        uint256 axlopBalance = IERC20(axlop).balanceOf(address(vault));

        uint256 amountOutMin = 1; // Accept any amount for test
        bool stable = false; // Set to true if axlop/USDC is a stable pool
        bytes memory eqSwapCalldata = abi.encodeWithSelector(
            IEqualizerRouter.swapExactTokensForTokensSimple.selector,
            axlopBalance,
            amountOutMin,
            axlop,
            USDC,
            stable,
            address(vault),
            deadline
        );
        targets[1] = equalizerRouter;
        data[1] = eqSwapCalldata;
        // 1. Approve batchRouter to spend USDC
        uint256 totalUsdc = IERC20(USDC).balanceOf(address(vault)); // 1304 USDC (6 decimals)
        uint256 usdcToSwap = (totalUsdc * 67) / 100; // 67% of USDC = 873.68e6
        targets[2] = address(vault);
        data[2] = abi.encodeWithSelector(vault.deductFees.selector, USDC);
        // 2. Prepare swap path for USDC->GHO (using user-provided path)
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](3);
        steps[0] = IBatchRouter.SwapPathStep({
            pool: 0xC768c589647798a6EE01A91FdE98EF2ed046DBD6,
            tokenOut: IERC20(0xC768c589647798a6EE01A91FdE98EF2ed046DBD6),
            isBuffer: true
        });
        steps[1] = IBatchRouter.SwapPathStep({
            pool: 0x7AB124EC4029316c2A42F713828ddf2a192B36db,
            tokenOut: IERC20(0x88b1Cd4b430D95b406E382C3cDBaE54697a0286E),
            isBuffer: false
        });
        steps[2] = IBatchRouter.SwapPathStep({
            pool: 0x88b1Cd4b430D95b406E382C3cDBaE54697a0286E,
            tokenOut: IERC20(0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee), // GHO
            isBuffer: true
        });
        IBatchRouter.SwapPathExactAmountIn[] memory swapPaths = new IBatchRouter.SwapPathExactAmountIn[](1);
        swapPaths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: IERC20(USDC),
            steps: steps,
            exactAmountIn: usdcToSwap,
            minAmountOut: 1 // Accept any amount for test
        });
        uint256 swapDeadline = block.timestamp + 1 hours;
        bytes memory batchRouterCalldata = abi.encodeWithSelector(
            IBatchRouter.swapExactIn.selector,
            swapPaths,
            swapDeadline,
            false, // WETH is not ETH
            ""
        );
        //targets[3] = batchRouter;
        //data[3] = batchRouterCalldata;
        vault.multicall(targets, data);
        // Assert vault does not hold excess USDC or GHO (should only hold what is needed for next addLiquidity)
        assertLe(IERC20(USDC).balanceOf(address(vault)), 200e6, "Vault should not hold excess USDC after multicall");
        assertLe(IERC20(GHO).balanceOf(address(vault)), 200e18, "Vault should not hold excess GHO after multicall");
        // Assert vault does not hold pool tokens
        assertEq(IERC20(POOL).balanceOf(address(vault)), 0, "Vault should not hold pool tokens after multicall");
        // Assert gauge tokens are unchanged (no deposit yet)
        // Add liquidity and check invariants
        maxInputAmounts[0] = IERC20(GHO).balanceOf(address(vault));
        maxInputAmounts[1] = IERC20(USDC).balanceOf(address(vault));
        exactBptAmountOut = 70e18;
        //vault.addLiquidityProportional(wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData,0);
        // After addLiquidity, vault should not hold underlying or pool tokens
        // assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "Vault should not hold USDC after addLiquidity");
        // assertEq(IERC20(GHO).balanceOf(address(vault)), 0, "Vault should not hold GHO after addLiquidity");
        //assertEq(IERC20(POOL).balanceOf(address(vault)), 0, "Vault should not hold pool tokens after addLiquidity");
        // Gauge should hold pool tokens
        //assertGt(IERC20(POOL).balanceOf(address(GAUGE)), 0, "Gauge should hold pool tokens after addLiquidity");
        // Vault should hold gauge tokens
        //assertGt(IERC20(GAUGE).balanceOf(address(vault)), 0, "Vault should hold gauge tokens after addLiquidity");
        // Vault should not hold reward tokens (should have swapped out)
        //assertEq(IERC20(bal).balanceOf(address(vault)), 0, "Vault should not hold BAL after swaps");
        //assertEq(IERC20(axlop).balanceOf(address(vault)), 0, "Vault should not hold axlop after swaps");
    }

    function testMultipleUsersPartialAndFullWithdraw() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        address user1 = address(0xA1);
        address user2 = address(0xA2);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Fund users with tokens
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user1, 100e6);
        IERC20(USDC).transfer(user2, 100e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user1, 200e18);
        IERC20(GHO).transfer(user2, 200e18);
        vm.stopPrank();

        // Both users approve vault
        vm.startPrank(user1);
        IERC20(USDC).approve(address(vault), 100e6);
        IERC20(GHO).approve(address(vault), 200e18);
        vm.stopPrank();
        vm.startPrank(user2);
        IERC20(USDC).approve(address(vault), 100e6);
        IERC20(GHO).approve(address(vault), 200e18);
        vm.stopPrank();

        // Both users deposit proportionally
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 2e18;
        maxInputAmounts[1] = 1e6;
        uint256 exactBptAmountOut = 5e17;
        bytes memory userData = "";
        vm.startPrank(user1);
        uint256 shares1 =
            vault.depositProportional(user1, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        vm.stopPrank();
        vm.startPrank(user2);
        uint256 shares2 =
            vault.depositProportional(user2, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        vm.stopPrank();

        // Both users withdraw half their shares
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapUnderlying = new bool[](2);
        unwrapUnderlying[0] = true;
        unwrapUnderlying[1] = true;

        // User1 partial withdraw
        vm.startPrank(user1);
        uint256 ghoBefore1 = IERC20(GHO).balanceOf(user1);
        uint256 usdcBefore1 = IERC20(USDC).balanceOf(user1);
        vault.approve(address(vault), shares1 / 2);
        vault.withdraw(shares1 / 2, minAmountsOut, unwrapUnderlying, false, userData);
        assertGt(IERC20(GHO).balanceOf(user1) - ghoBefore1, 0, "User1 should receive GHO on partial withdraw");
        assertGt(IERC20(USDC).balanceOf(user1) - usdcBefore1, 0, "User1 should receive USDC on partial withdraw");
        assertEq(vault.balanceOf(user1), shares1 - shares1 / 2, "User1 should have half shares left");
        vm.stopPrank();

        // User2 partial withdraw
        vm.startPrank(user2);
        uint256 ghoBefore2 = IERC20(GHO).balanceOf(user2);
        uint256 usdcBefore2 = IERC20(USDC).balanceOf(user2);
        vault.approve(address(vault), shares2 / 2);
        vault.withdraw(shares2 / 2, minAmountsOut, unwrapUnderlying, false, userData);
        assertGt(IERC20(GHO).balanceOf(user2) - ghoBefore2, 0, "User2 should receive GHO on partial withdraw");
        assertGt(IERC20(USDC).balanceOf(user2) - usdcBefore2, 0, "User2 should receive USDC on partial withdraw");
        assertEq(vault.balanceOf(user2), shares2 - shares2 / 2, "User2 should have half shares left");
        vm.stopPrank();

        // Advance time
        vm.warp(block.timestamp + 3 days);

        // Both users withdraw remaining shares
        vm.startPrank(user1);
        uint256 ghoBefore1Full = IERC20(GHO).balanceOf(user1);
        uint256 usdcBefore1Full = IERC20(USDC).balanceOf(user1);
        vault.approve(address(vault), vault.balanceOf(user1));
        vault.withdraw(vault.balanceOf(user1), minAmountsOut, unwrapUnderlying, false, userData);
        assertGt(IERC20(GHO).balanceOf(user1) - ghoBefore1Full, 0, "User1 should receive GHO on final withdraw");
        assertGt(IERC20(USDC).balanceOf(user1) - usdcBefore1Full, 0, "User1 should receive USDC on final withdraw");
        assertEq(vault.balanceOf(user1), 0, "User1 should have no shares left");
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 ghoBefore2Full = IERC20(GHO).balanceOf(user2);
        uint256 usdcBefore2Full = IERC20(USDC).balanceOf(user2);
        vault.approve(address(vault), vault.balanceOf(user2));
        vault.withdraw(vault.balanceOf(user2), minAmountsOut, unwrapUnderlying, false, userData);
        assertGt(IERC20(GHO).balanceOf(user2) - ghoBefore2Full, 0, "User2 should receive GHO on final withdraw");
        assertGt(IERC20(USDC).balanceOf(user2) - usdcBefore2Full, 0, "User2 should receive USDC on final withdraw");
        assertEq(vault.balanceOf(user2), 0, "User2 should have no shares left");
        vm.stopPrank();
        // Assert vault is empty
        assertEq(IERC20(GHO).balanceOf(address(vault)), 0, "Vault should not hold GHO after all withdraws");
        assertEq(IERC20(USDC).balanceOf(address(vault)), 0, "Vault should not hold USDC after all withdraws");
        assertEq(IERC20(POOL).balanceOf(address(vault)), 0, "Vault should not hold pool tokens after all withdraws");
        assertEq(IERC20(GAUGE).balanceOf(address(vault)), 0, "Vault should not hold gauge tokens after all withdraws");
        assertEq(vault.totalSupply(), 0, "Vault should have no shares after all withdraws");
    }

    function testWithdrawMoreThanBalanceReverts() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        // Fund user
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user, 2e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user, 4e18);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 2e6);
        IERC20(GHO).approve(address(vault), 4e18);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 4e18;
        maxInputAmounts[1] = 2e6;
        uint256 exactBptAmountOut = 1e18;
        bytes memory userData = "";
        vault.depositProportional(user, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        uint256 shares = vault.balanceOf(user);
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapUnderlying = new bool[](2);
        unwrapUnderlying[0] = true;
        unwrapUnderlying[1] = true;
        // Try to withdraw more than balance
        vault.approve(address(vault), shares + 1);
        vm.expectRevert();
        vault.withdraw(shares + 1, minAmountsOut, unwrapUnderlying, false, userData);
        vm.stopPrank();
    }

    function testDepositWithZeroAmountsReverts() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user, 2e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user, 4e18);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 2e6);
        IERC20(GHO).approve(address(vault), 4e18);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 0;
        maxInputAmounts[1] = 0;
        uint256 exactBptAmountOut = 1e18;
        bytes memory userData = "";
        vm.expectRevert();
        vault.depositProportional(user, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        vm.stopPrank();
    }

    function testWithdrawWithZeroSharesReverts() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user, 2e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user, 4e18);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 2e6);
        IERC20(GHO).approve(address(vault), 4e18);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 4e18;
        maxInputAmounts[1] = 2e6;
        uint256 exactBptAmountOut = 1e18;
        bytes memory userData = "";
        vault.depositProportional(user, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapUnderlying = new bool[](2);
        unwrapUnderlying[0] = true;
        unwrapUnderlying[1] = true;
        vault.approve(address(vault), 0);
        vm.expectRevert();
        vault.withdraw(0, minAmountsOut, unwrapUnderlying, false, userData);
        vm.stopPrank();
    }

    function testMultipleUsersSimultaneousDepositWithdraw() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        address user1 = address(0xB1);
        address user2 = address(0xB2);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user1, 2e6);
        IERC20(USDC).transfer(user2, 2e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user1, 4e18);
        IERC20(GHO).transfer(user2, 4e18);
        vm.stopPrank();
        vm.startPrank(user1);
        IERC20(USDC).approve(address(vault), 2e6);
        IERC20(GHO).approve(address(vault), 4e18);
        vm.stopPrank();
        vm.startPrank(user2);
        IERC20(USDC).approve(address(vault), 2e6);
        IERC20(GHO).approve(address(vault), 4e18);
        vm.stopPrank();
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 4e18;
        maxInputAmounts[1] = 2e6;
        uint256 exactBptAmountOut = 1e18;
        bytes memory userData = "";
        vm.startPrank(user1);
        uint256 shares1 =
            vault.depositProportional(user1, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        vm.stopPrank();
        vm.startPrank(user2);
        uint256 shares2 =
            vault.depositProportional(user2, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        vm.stopPrank();
        // Both users withdraw at the same block
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapUnderlying = new bool[](2);
        unwrapUnderlying[0] = true;
        unwrapUnderlying[1] = true;
        vm.startPrank(user1);
        vault.approve(address(vault), shares1);
        vault.withdraw(shares1, minAmountsOut, unwrapUnderlying, false, userData);
        assertEq(vault.balanceOf(user1), 0, "User1 should have no shares after withdraw");
        vm.stopPrank();
        vm.startPrank(user2);
        vault.approve(address(vault), shares2);
        vault.withdraw(shares2, minAmountsOut, unwrapUnderlying, false, userData);
        assertEq(vault.balanceOf(user2), 0, "User2 should have no shares after withdraw");
        vm.stopPrank();
        // Vault should be empty
        assertEq(vault.totalSupply(), 0, "Vault should have no shares after all withdraws");
    }

    function testRewardsAccrualAndClaim() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        address BAL = 0x4158734D47Fc9692176B5085E0F52ee0Da5d47F1;
        address AXL = 0x994ac01750047B9d35431a7Ae4Ed312ee955E030;
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user, 2e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user, 4e18);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 2e6);
        IERC20(GHO).approve(address(vault), 4e18);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 4e18;
        maxInputAmounts[1] = 2e6;
        uint256 exactBptAmountOut = 1e18;
        bytes memory userData = "";
        vault.depositProportional(user, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        vm.stopPrank();
        // Simulate time passing for rewards
        vm.warp(block.timestamp + 10 days);
        // Claim rewards
        uint256 balBefore = IERC20(BAL).balanceOf(address(vault));
        uint256 axlBefore = IERC20(AXL).balanceOf(address(vault));
        vault.claimRewards();
        uint256 balAfter = IERC20(BAL).balanceOf(address(vault));
        uint256 axlAfter = IERC20(AXL).balanceOf(address(vault));
        assertGt(balAfter, balBefore, "Vault should accrue BAL rewards");
        assertGt(axlAfter, axlBefore, "Vault should accrue AXL rewards");
    }

    function testPartialWithdrawals() public {
        address usdcWhale = 0x0B0A5886664376F59C351ba3f598C8A8B4D0A6f3;
        address ghoWhale = 0x12Da7E0c469CEeC4EFADa2F5E8CAedCD3F3E6748;
        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address GHO = 0x6Bb7a212910682DCFdbd5BCBb3e28FB4E8da10Ee;
        vm.startPrank(usdcWhale);
        IERC20(USDC).transfer(user, 2e6);
        vm.stopPrank();
        vm.startPrank(ghoWhale);
        IERC20(GHO).transfer(user, 4e18);
        vm.stopPrank();
        vm.startPrank(user);
        IERC20(USDC).approve(address(vault), 2e6);
        IERC20(GHO).approve(address(vault), 4e18);
        bool[] memory wrapUnderlying = new bool[](2);
        wrapUnderlying[0] = true;
        wrapUnderlying[1] = true;
        uint256[] memory maxInputAmounts = new uint256[](2);
        maxInputAmounts[0] = 4e18;
        maxInputAmounts[1] = 2e6;
        uint256 exactBptAmountOut = 1e18;
        bytes memory userData = "";
        vault.depositProportional(user, wrapUnderlying, maxInputAmounts, exactBptAmountOut, false, userData);
        uint256 shares = vault.balanceOf(user);
        uint256[] memory minAmountsOut = new uint256[](2);
        minAmountsOut[0] = 1;
        minAmountsOut[1] = 1;
        bool[] memory unwrapUnderlying = new bool[](2);
        unwrapUnderlying[0] = true;
        unwrapUnderlying[1] = true;
        // First partial withdraw
        vault.approve(address(vault), shares / 2);
        vault.withdraw(shares / 2, minAmountsOut, unwrapUnderlying, false, userData);
        assertEq(
            vault.balanceOf(user), shares - shares / 2, "User should have half shares left after first partial withdraw"
        );
        // Second partial withdraw
        vault.approve(address(vault), shares - shares / 2);
        vault.withdraw(shares - shares / 2, minAmountsOut, unwrapUnderlying, false, userData);
        assertEq(vault.balanceOf(user), 0, "User should have no shares left after second partial withdraw");
        vm.stopPrank();
    }
}
