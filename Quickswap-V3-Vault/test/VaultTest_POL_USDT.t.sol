// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./helpers/VaultTestBase.sol";
import "./helpers/SwapHelper.sol";
import "./core/VaultTest.sol";

contract VaultTest_POL_USDT is VaultTest {
    address internal constant POL = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address internal constant USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address internal constant ROUTER = 0xf5b509bB0909a69B1c207E495f687a596C168E12;
    address internal constant POL_USDT_POOL = 0x5b41EEDCfC8e0AE47493d4945Aa1AE4fe05430ff;
    address internal constant REWARD_TOKEN = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;
    uint256 internal constant START_TIME = 1665192467;
    uint256 internal constant END_TIME = 4104559500;
    address internal constant Quick_Token = 0xB5C064F955D8e7F38fE0460C556a72987494eE17;

    function testVaultLifecycle_POL_USDT() public {
        vm.startPrank(owner);
        vm.deal(owner, 10000 ether);

        // Step 1: Initialize Vault
        uint256 amountToSwap = 1000 ether;
        uint256 amountOutMinimum = 1;
        SwapHelper.swapNativeToToken(POL, USDT, amountToSwap, amountOutMinimum, ROUTER, owner);
        IERC20(USDT).approve(address(vault), type(uint256).max);
        
        InitializeVault(0.5 ether, 0.5 ether, 12000, 1, 1, -887220, 887220, POL_USDT_POOL);
        vm.stopPrank();

        // Step 2: Test ZapInSingle with POL
        vm.startPrank(user1);
        amountToSwap = 1000 ether;
        amountOutMinimum = 1;
        vm.deal(user1, 10000 ether);
        // --- Zap in with POL (MATIC) ---
       ZapInSingleTest(POL, 1 ether, 1 ether, 104611, 481750039490172897, 103600, user1);
        // --- Zap in with USDT ---
        SwapHelper.swapNativeToToken(POL, USDT, amountToSwap, amountOutMinimum, ROUTER, user1);
        IERC20(USDT).approve(address(vault), type(uint256).max);
        uint256 amountInUSDT = 1e6;//IERC20(USDT).balanceOf(user1);
        ZapInSingleTest(USDT, 0, amountInUSDT,2.36 ether, 2.35 ether, 480000, user1);

        // // // // Step 4: Test ZapInDual
        // vm.deal(user1, 10000 ether); // Replenish ETH
        // SwapHelper.swapNativeToToken(POL, USDT, amountToSwap, amountOutMinimum, ROUTER, user1);
        // IERC20(POL).approve(address(vault), type(uint256).max);
        // IERC20(USDT).approve(address(vault), type(uint256).max);
        // ZapInDualTest(1 ether, 1 ether, 12000, 1, 1, user1);
        // vm.stopPrank();

        // SwapHelper.swapNativeToToken(POL, USDT, 50000 ether, amountOutMinimum, ROUTER, owner);
        // SwapHelper.swapNativeToToken(POL, Quick_Token, 50000 ether, amountOutMinimum, ROUTER, owner);
        // vm.startPrank(owner);
        // IERC20(Quick_Token).transfer(address(vault), 200 ether);
        // vault.setFarmingRewardClaimer(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae, owner);
        // vault.setMulticallWhitelist(ROUTER, true);
        // vault.setMulticallWhitelist(owner, true);
        // vault.setMulticallWhitelist(address(vault), true);
        // vault.approve(Quick_Token, ROUTER, type(uint256).max);
        // vault.collectFees();
        // address[] memory targets;
        // bytes[] memory data;
        // (targets, data) = prepareMulticall(
        //     Quick_Token,
        //     POL,
        //     USDT,
        //     IERC20(Quick_Token).balanceOf(address(vault)),
        //     IERC20(USDT).balanceOf(address(vault)),
        //     address(vault)
        // );
        // vault.multicall(targets, data);
        // (targets, data) = prepareMulticallForSwapOptimalSwap();
        // vault.multicall(targets, data);
        // vault.addLiquidity(
        //     IERC20(vault.token0()).balanceOf(address(vault)), IERC20(vault.token1()).balanceOf(address(vault)), 1, 1
        // );
        // vm.startPrank(user1);
        // uint128 shares = uint128(vault.balanceOf(user1) / 2);
        // ZapOutTest(shares, 1, 1, user1);
        // shares = uint128(vault.balanceOf(user1));
        // ZapOutAndSwapTest(shares, POL, 1, 1, 1, user1);
        // vm.stopPrank();
    }

    function prepareMulticallForSwapOptimalSwap() public view returns (address[] memory targets, bytes[] memory data) {
        targets = new address[](1);
        data = new bytes[](1);
        address router = ROUTER;
        uint256 remainingPol = IERC20(POL).balanceOf(address(vault));
        uint256 halfPol = remainingPol / 2;
        targets[0] = router;
        data[0] = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: POL,
                tokenOut: USDT,
                recipient: address(vault),
                deadline: block.timestamp,
                amountIn: halfPol,
                amountOutMinimum: 0,
                limitSqrtPrice: 0
            })
        );
    }

    function prepareMulticall(
        address quick,
        address pol,
        address usdt,
        uint256 quickAmount,
        uint256 usdtAmount,
        address recipient
    ) public view returns (address[] memory targets, bytes[] memory data) {
        targets = new address[](3);
        data = new bytes[](3);
        address router = ROUTER;
        // 1. Approve QUICK to router
        // targets[0] = quick;
        // data[0] = abi.encodeWithSelector(
        //     IERC20.approve.selector,
        //     router,
        //     quickAmount
        // );

        // 2. Swap QUICK -> POL
        targets[0] = router;
        data[0] = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: quick,
                tokenOut: pol,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: quickAmount,
                amountOutMinimum: 0,
                limitSqrtPrice: 0
            })
        );

        // 3. Swap USDT -> POL
        targets[1] = router;
        data[1] = abi.encodeWithSelector(
            ISwapRouter.exactInputSingle.selector,
            ISwapRouter.ExactInputSingleParams({
                tokenIn: usdt,
                tokenOut: pol,
                recipient: recipient,
                deadline: block.timestamp,
                amountIn: usdtAmount,
                amountOutMinimum: 0,
                limitSqrtPrice: 0
            })
        );

        // 4. Transfer 5% POL to recipient
        // uint256 polBalance = IERC20(pol).balanceOf(address(this));
        // uint256 fivePercent = (polBalance * 5) / 100;
        targets[2] = address(vault);
        data[2] = abi.encodeWithSelector(vault.deductFees.selector, POL);

        // 5. Swap half of remaining POL to USDT
        //     uint256 remainingPol = polBalance - fivePercent;
        //     uint256 halfPol = remainingPol / 2;
        //     targets[4] = router;
        //     data[4] = abi.encodeWithSelector(
        //         ISwapRouter.exactInputSingle.selector,
        //         ISwapRouter.ExactInputSingleParams({
        //             tokenIn: pol,
        //             tokenOut: usdt,
        //             recipient: recipient,
        //             deadline: block.timestamp,
        //             amountIn: halfPol,
        //             amountOutMinimum: 0,
        //             limitSqrtPrice: 0
        //         })
        //     );
    }
}
