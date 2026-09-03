// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.24;

// import "forge-std/Test.sol";

// interface IBatchRouter {
//     struct SwapPathStep {
//         address pool;
//         address tokenIn;
//         address tokenOut;
//         bool isBuffer;
//     }
//     struct SwapPathExactAmountOut {
//         address tokenIn;
//         SwapPathStep[] steps;
//         uint256 maxAmountIn;
//         uint256 exactAmountOut;
//     }
//     function swapExactOut(
//         SwapPathExactAmountOut[] memory paths,
//         uint256 deadline,
//         bool wethIsEth,
//         bytes calldata userData
//     ) external payable returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn);
// }

// interface IWETH {
//     function deposit() external payable;
//     function withdraw(uint256) external;
//     function balanceOf(address) external view returns (uint256);
//     function approve(address spender, uint256 amount) external returns (bool);
// }

// contract BatchRouterSwapTest is Test {
//     address constant BATCH_ROUTER = 0x85a80afee867aDf27B50BdB7b76DA70f1E853062;
//     address constant WETH = 0x4200000000000000000000000000000000000006;
//     address constant GHO = 0xC768c589647798a6EE01A91FdE98EF2ed046DBD6;
//     address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
//     address constant USER = address(0xABCD);

//     function setUp() public {
//         //vm.createSelectFork("mainnet");
//         vm.deal(USER, 10 ether);
//     }

//     // function testSwapETHForGHOAndUSDC() public {
//     //     vm.startPrank(USER);
//     //     // --- ETH -> GHO path (fill with real pools/steps for mainnet) ---
//     //     IBatchRouter.SwapPathStep[] memory ghoSteps = new IBatchRouter.SwapPathStep[](1);
//     //     ghoSteps[0] = IBatchRouter.SwapPathStep({
//     //         pool: 0xe298b938631f750DD409fB18227C4a23dCdaab9b, // Example pool
//     //         tokenIn: WETH,
//     //         tokenOut: GHO,
//     //         isBuffer: true
//     //     });
//     //     IBatchRouter.SwapPathExactAmountOut memory ghoPath = IBatchRouter.SwapPathExactAmountOut({
//     //         tokenIn: WETH,
//     //         steps: ghoSteps,
//     //         maxAmountIn: 2 ether,
//     //         exactAmountOut: 5e18 // 5 GHO
//     //     });
//     //     // --- ETH -> USDC path (fill with real pools/steps for mainnet) ---
//     //     IBatchRouter.SwapPathStep[] memory usdcSteps = new IBatchRouter.SwapPathStep[](1);
//     //     usdcSteps[0] = IBatchRouter.SwapPathStep({
//     //         pool: 0xe298b938631f750DD409fB18227C4a23dCdaab9b, // Example pool
//     //         tokenIn: WETH,
//     //         tokenOut: USDC,
//     //         isBuffer: true
//     //     });
//     //     IBatchRouter.SwapPathExactAmountOut memory usdcPath = IBatchRouter.SwapPathExactAmountOut({
//     //         tokenIn: WETH,
//     //         steps: usdcSteps,
//     //         maxAmountIn: 2 ether,
//     //         exactAmountOut: 1000e6 // 1000 USDC (6 decimals)
//     //     });
//     //     IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](2);
//     //     paths[0] = ghoPath;
//     //     paths[1] = usdcPath;
//     //     uint256 deadline = block.timestamp + 1 hours;
//     //     bool wethIsEth = true;
//     //     bytes memory userData = "";
//     //     // Call swapExactOut on BatchRouter
//     //     (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) =
//     //         IBatchRouter(BATCH_ROUTER).swapExactOut{value: 4 ether}(
//     //             paths,
//     //             deadline,
//     //             wethIsEth,
//     //             userData
//     //         );
//     //     emit log_named_array("ETH spent for each path", pathAmountsIn);
//     //     emit log_named_array("Tokens received", tokensIn);
//     //     emit log_named_array("Amounts received", amountsIn);
//     //     vm.stopPrank();
//     // }

//     function testSwapETHForGHO() public {
//         //vm.createSelectFork("https://base-mainnet.g.alchemy.com/v2/jlxrE4wpG-lcjCGyyPKa9rfVFgsbDor_", 30767665);
//         // vm.deal(USER, 10 ether);
//         // vm.startPrank(USER);
//         // --- ETH -> GHO path ---

//         IBatchRouter.SwapPathStep[] memory ghoSteps = new IBatchRouter.SwapPathStep[](1);
//         ghoSteps[0] = IBatchRouter.SwapPathStep({
//             pool: 0x4Fbb7870DBE7A7Ef4866A33c0eED73D395730dc0, // Example pool, update for best route
//             tokenIn: WETH,
//             tokenOut: USDC,
//             isBuffer: true
//         });
//         IBatchRouter.SwapPathExactAmountOut[] memory paths = new IBatchRouter.SwapPathExactAmountOut[](1);
//         paths[0] = IBatchRouter.SwapPathExactAmountOut({
//             tokenIn: WETH,
//             steps: ghoSteps,
//             maxAmountIn: 1 ether,
//             exactAmountOut: 5e18 // 5 GHO
//         });
//         uint256 deadline = block.timestamp + 1 hours;
//         bool wethIsEth = true;
//         bytes memory userData = "";
//         (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn) =
//             IBatchRouter(BATCH_ROUTER).swapExactOut{value: 0 ether}(
//                 paths,
//                 deadline,
//                 wethIsEth,
//                 userData
//             );
//         emit log_named_array("ETH spent for GHO path", pathAmountsIn);
//         emit log_named_array("Tokens received", tokensIn);
//         emit log_named_array("Amounts received", amountsIn);
//         //vm.stopPrank();
//     }

//     function testDepositNativeETHAndGetWETH() public {
//         //vm.createSelectFork("https://base-mainnet.g.alchemy.com/v2/jlxrE4wpG-lcjCGyyPKa9rfVFgsbDor_", 30767665);
//         vm.deal(USER, 2 ether);
//         vm.startPrank(USER);
//         address WETH = 0x4200000000000000000000000000000000000006;
//         IWETH weth = IWETH(WETH);
//         uint256 wethBalanceBefore = weth.balanceOf(USER);
//         // Deposit native ETH to WETH contract
//         weth.deposit{value: 1 ether}();
//         uint256 wethBalanceAfter = weth.balanceOf(USER);
//         emit log_named_uint("WETH balance before", wethBalanceBefore);
//         emit log_named_uint("WETH balance after", wethBalanceAfter);
//         assertEq(wethBalanceAfter, wethBalanceBefore + 1 ether, "WETH mint failed");
//         IWETH(WETH).approve(BATCH_ROUTER, type(uint256).max);
//         testSwapETHForGHO();
//         vm.stopPrank();
//     }
// }
