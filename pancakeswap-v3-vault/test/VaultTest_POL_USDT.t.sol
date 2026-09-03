// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

//import "./helpers/VaultTestBase.sol";
import "./helpers/SwapHelper.sol";
//import "./core/VaultTest.sol";
import "../src/Vault.sol";
import "forge-std/Test.sol";

contract VaultTest_POL_USDT is Test {
    address internal constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address internal constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address internal constant ROUTER = 0x13f4EA83D0bd40E75C8222255bc855a974568Dd4;
    address internal constant POOL = 0xf2688Fb5B81049DFB7703aDa5e770543770612C4;
    address internal constant REWARD_TOKEN = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    Vault public vault;
    address public owner = address(0xA11CE);
    address public user1 = address(0xBEEF);
    address public user2 = address(0xCAFE);
    address public user3 = address(0xDEAD);
    address internal constant _POOL = 0xf2688Fb5B81049DFB7703aDa5e770543770612C4;
    address internal constant _MASTER_CHEF_V3 = 0x556B9306565093C855AEA9AE92A594704c2Cd59e;
    address internal constant NonfungiblePositionManager = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
    int24 tickUpper = 887220;
    int24 tickLower = -887220;

    function setUp() public virtual {
        vault = new Vault(
            "TestVault",
            "TVLT",
            _POOL,
            _MASTER_CHEF_V3,
            NonfungiblePositionManager,
            REWARD_TOKEN,
            WBNB,
            ROUTER,
            owner,
            owner
        );
    }

    function testVaultLifecycle_POL_USDT() public {
        vm.startPrank(owner);
        vm.deal(owner, 10000 ether);

        // Step 1: Initialize Vault
        uint256 amountToSwap = 1 ether;
        uint256 amountOutMinimum = 1;
        SwapHelper.singleSwap(WBNB, USDC, amountToSwap, amountOutMinimum, 100, ROUTER, owner);
        IERC20(USDC).approve(address(vault), type(uint256).max);

        uint256 vaultNativeBalBefore = address(vault).balance;
        // uint256 vaultToken0BalBefore = IERC20(address(vault.token0())).balanceOf(address(vault));
        // uint256 vaultToken1BalBefore = IERC20(address(vault.token1())).balanceOf(address(vault));
        vm.startPrank(owner);
        vault.initializeVault{value: 0.1 ether}(100e6, 0.1 ether, 1, 1, tickLower, tickUpper);
        // Assertions
        assertEq(vault.pool(), _POOL, "POOL address should match");
        assertEq(vault.tickLower(), tickLower, "tickLower should match");
        assertEq(vault.tickUpper(), tickUpper, "tickUpper should match");
        assertGt(vault.tokenId(), 0, "tokenId should be set");
        assertEq(address(vault).balance, vaultNativeBalBefore);
        assertEq(IERC20(address(vault.token0())).balanceOf(address(vault)), 0);
        assertEq(IERC20(address(vault.token1())).balanceOf(address(vault)), 0);
        //vault.initializeVault(amount0, amount1, amount0Min, amount1Min, _tickLower, _tickUpper);
        // InitializeVault(0.1 ether,100e6,0.1 ether, 1, 1, -887220, 887220, vault);
        // // vm.stopPrank();

        // // // Step 2: Test ZapInSingle with POL
        vm.startPrank(user1);
        amountToSwap = 10 ether;
        amountOutMinimum = 1;
        vm.deal(user1, 10000 ether);
        // // --- Zap in with POL (MATIC) ---
        // ZapInSingleTest(WBNB, 10 ether, 10 ether, 1, 1, 1, user1, vault);
        uint256 userShareBefore = vault.balanceOf(user1);
        vault.zapInSingle{value: 10 ether}(user1, WBNB, 10 ether, 1, 1, 1);
        assertEq(IERC20(address(vault.token0())).balanceOf(address(vault)), 0);
        assertEq(IERC20(address(vault.token1())).balanceOf(address(vault)), 0);
        assertGt(vault.balanceOf(user1), userShareBefore);
        // // --- Zap in with USDT ---
        SwapHelper.singleSwap(WBNB, USDC, amountToSwap, amountOutMinimum, 100, ROUTER, user1);
        IERC20(USDC).approve(address(vault), type(uint256).max);
        uint256 amountInUSDC = IERC20(USDC).balanceOf(user1);
        // console.log(amountInUSDC);
        userShareBefore = vault.balanceOf(user1);
        //ZapInSingleTest(USDC, 0, amountInUSDC, 1, 1, 1, user1);
        vault.zapInSingle{value: 0}(user1, USDC, amountInUSDC, 1, 1, 1);
        assertEq(IERC20(address(vault.token0())).balanceOf(address(vault)), 0);
        assertEq(IERC20(address(vault.token1())).balanceOf(address(vault)), 0);
        assertGt(vault.balanceOf(user1), userShareBefore);
        // // // // // Step 4: Test ZapInDual
        vm.deal(user1, 10000 ether); // Replenish ETH
        SwapHelper.singleSwap(WBNB, USDC, amountToSwap, amountOutMinimum, 100, ROUTER, user1);
        IERC20(WBNB).approve(address(vault), type(uint256).max);
        IERC20(USDC).approve(address(vault), type(uint256).max);
        userShareBefore = vault.balanceOf(user1);
        vault.zapInDual{value: 1 ether}(user1, 500e6, 1 ether, 1, 1);
        assertEq(IERC20(address(vault.token0())).balanceOf(address(vault)), 0);
        assertEq(IERC20(address(vault.token1())).balanceOf(address(vault)), 0);
        assertGt(vault.balanceOf(user1), userShareBefore);
        // ZapInDualTest(1 ether, 500e6, 1 ether, 1, 1, user1, vault);
        vm.warp(block.timestamp + 5 days);
        // vault.harvest();
        // vm.stopPrank();

        // SwapHelper.swapNativeToToken(POL, USDT, 50000 ether, amountOutMinimum, ROUTER, owner);
        // SwapHelper.swapNativeToToken(POL, Quick_Token, 50000 ether, amountOutMinimum, ROUTER, owner);
        vm.startPrank(owner);
        // IERC20(Quick_Token).transfer(address(vault), 200 ether);
        //vault.setFarmingRewardClaimer(0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae, owner);
        vault.setMulticallWhitelist(ROUTER, true);
        vault.setMulticallWhitelist(owner, true);
        vault.setMulticallWhitelist(address(vault), true);
        //vault.approve(REWARD_TOKEN, ROUTER, type(uint256).max);
        vault.collectFees();
        vault.harvestReward();
        address[] memory targets;
        bytes[] memory data;
        // (targets, data) = prepareMulticall(
        //     IERC20(REWARD_TOKEN).balanceOf(address(vault)),
        //     IERC20(USDC).balanceOf(address(vault)),
        //     address(vault)
        // );
        // vault.multicall(targets, data);
        // (targets, data) = prepareMulticallForSwapOptimalSwap();
        // vault.multicall(targets, data);
        vm.startPrank(user1);
        uint256 user1token0Bal = IERC20(WBNB).balanceOf(user1);
        uint256 user1token1Bal = IERC20(USDC).balanceOf(user1);
        vault.zapOut(uint128(vault.balanceOf(user1) / 2), 1, 1);
        assertGt(IERC20(WBNB).balanceOf(user1), user1token0Bal);
        assertGt(IERC20(USDC).balanceOf(user1), user1token1Bal);
        user1token0Bal = IERC20(WBNB).balanceOf(user1);
        vault.zapOutAndSwap(uint128(vault.balanceOf(user1) / 2), 1, 1, WBNB, 1);
        assertGt(IERC20(WBNB).balanceOf(user1), user1token0Bal);
        user1token1Bal = IERC20(USDC).balanceOf(user1);
        vault.zapOutAndSwap(uint128(vault.balanceOf(user1)), 1, 1, USDC, 1);
        assertGt(IERC20(USDC).balanceOf(user1), user1token1Bal);
        // vault.addLiquidity(
        //     IERC20(vault.token0()).balanceOf(address(vault)), IERC20(vault.token1()).balanceOf(address(vault)), 1, 1
        // );
        // vm.startPrank(user1);
        // uint128 shares = uint128(vault.balanceOf(user1) / 2);
        // ZapOutTest(shares, 1, 1, user1);
        // shares = uint128(vault.balanceOf(user1));
        // //ZapOutAndSwapTest(shares, WBNB, 1, 1, 1, user1);
        // vm.stopPrank();
    }

    function prepareMulticallForSwapOptimalSwap() public view returns (address[] memory targets, bytes[] memory data) {
        targets = new address[](1);
        data = new bytes[](1);
        address router = ROUTER;
        uint256 remainingWBNB = IERC20(WBNB).balanceOf(address(vault));
        uint256 halfWBNB = remainingWBNB / 2;
        targets[0] = router;
        data[0] = abi.encodeWithSelector(
            IV3SwapRouter.exactInputSingle.selector,
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: WBNB,
                tokenOut: USDC,
                recipient: address(vault),
                fee: IPancakeV3Pool(_POOL).fee(),
                amountIn: halfWBNB,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
        );
    }

    function prepareMulticall(uint256 rewardAmount, uint256 usdcAmount, address recipient)
        public
        view
        returns (address[] memory targets, bytes[] memory data)
    {
        targets = new address[](2);
        data = new bytes[](2);
        address router = ROUTER;
        // 1. Approve QUICK to router
        // targets[0] = quick;
        // data[0] = abi.encodeWithSelector(
        //     IERC20.approve.selector,
        //     router,
        //     quickAmount
        // );

        // 2. Swap QUICK -> POL
        // targets[0] = router;
        // data[0] = abi.encodeWithSelector(
        //     IV3SwapRouter.exactInputSingle.selector,
        //     IV3SwapRouter.ExactInputSingleParams({
        //         tokenIn: REWARD_TOKEN,
        //         tokenOut: WBNB,
        //         fee: 2500,
        //         recipient: recipient,
        //         amountIn: 18078618901912734,
        //         amountOutMinimum: 0,
        //         sqrtPriceLimitX96: 0
        //     })
        // );

        // 3. Swap USDT -> POL
        targets[0] = router;
        data[0] = abi.encodeWithSelector(
            IV3SwapRouter.exactInputSingle.selector,
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: USDC,
                tokenOut: WBNB,
                recipient: recipient,
                fee: IPancakeV3Pool(_POOL).fee(),
                amountIn: usdcAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // 4. Transfer 5% POL to recipient
        // uint256 polBalance = IERC20(pol).balanceOf(address(this));
        // uint256 fivePercent = (polBalance * 5) / 100;
        targets[1] = address(vault);
        data[1] = abi.encodeWithSelector(vault.deductFees.selector, WBNB);

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
