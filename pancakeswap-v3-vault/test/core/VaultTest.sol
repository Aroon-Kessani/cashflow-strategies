// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.7.6;
// pragma abicoder v2;

// //import "../helpers/VaultTestBase.sol";
// import "forge-std/Test.sol";
// //import "@cryptoalgebra/tokenomics/contracts/interfaces/IFarmingCenter.sol";
// import "../../src/interfaces/IVault.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract VaultTest is Test {
//     function InitializeVault(
//         uint256 nativeAmount,
//         uint256 amount0,
//         uint256 amount1,
//         uint256 amount0Min,
//         uint256 amount1Min,
//         int24 tickLower,
//         int24 tickUpper,
//         IVault vault
//     ) internal {
//         uint256 vaultNativeBalBefore = address(vault).balance;
//         // uint256 vaultToken0BalBefore = IERC20(address(vault.token0())).balanceOf(address(vault));
//         // uint256 vaultToken1BalBefore = IERC20(address(vault.token1())).balanceOf(address(vault));
//         vault.initializeVault{value: nativeAmount}(amount0, amount1, amount0Min, amount1Min, tickLower, tickUpper);
//         // Assertions
//         // assertEq(vault.pool(), pool, "POOL address should match");
//         // assertEq(vault.token0(), IAlgebraPool(pool).token0(), "TOKEN0 should match pool's token0");
//         // assertEq(vault.token1(), IAlgebraPool(pool).token1(), "TOKEN1 should match pool's token1");
//         // assertEq(vault.tickLower(), tickLower, "tickLower should match");
//         // assertEq(vault.tickUpper(), tickUpper, "tickUpper should match");
//         // assertGt(vault.tokenId(), 0, "tokenId should be set");
//         // assertEq(address(vault).balance, vaultNativeBalBefore);
//         // assertEq(IERC20(address(vault.token0())).balanceOf(address(vault)), 0);
//         // assertEq(IERC20(address(vault.token1())).balanceOf(address(vault)), 0);
//     }

//     function ZapInSingleTest(
//         address tokenIn,
//         uint256 nativeAmount,
//         uint256 amountIn,
//         uint256 amountOutMin,
//         uint256 amount0Min,
//         uint256 amount1Min,
//         address user,
//         Vault vault
//     ) internal {
//         uint256 vaultNativeBalBefore = address(vault).balance;
//         uint256 vaultToken0BalBefore = IERC20(address(vault.token0())).balanceOf(address(vault));
//         uint256 vaultToken1BalBefore = IERC20(address(vault.token1())).balanceOf(address(vault));
//         uint256 supplyBefore = vault.totalSupply();
//         uint256 userSharesBefore = vault.balanceOf(user);
//         vault.zapInSingle{value: nativeAmount}(tokenIn, amountIn, amountOutMin);
//         uint256 supplyAfter = vault.totalSupply();
//         uint256 userSharesAfter = vault.balanceOf(user);
//         assertGt(supplyAfter, supplyBefore, "Shares should be minted on zapInSingle");
//         assertGt(userSharesAfter, userSharesBefore, "User should receive shares on zapInSingle");
//         assertEq(IERC20(address(vault.token0())).balanceOf(address(vault)), vaultToken0BalBefore);
//         assertEq(IERC20(address(vault.token1())).balanceOf(address(vault)), vaultToken1BalBefore);
//         assertEq(address(vault).balance, vaultNativeBalBefore);
//     }

//     function ZapInDualTest(
//         uint256 nativeAmount,
//         uint256 amount0,
//         uint256 amount1,
//         uint256 amount0Min,
//         uint256 amount1Min,
//         address user,
//         IVault vault
//     ) internal {
//         uint256 vaultNativeBalBefore = address(vault).balance;
//         uint256 vaultToken0BalBefore = IERC20(address(vault.token0())).balanceOf(address(vault));
//         uint256 vaultToken1BalBefore = IERC20(address(vault.token1())).balanceOf(address(vault));
//         uint256 supplyBefore = vault.totalSupply();
//         uint256 userSharesBefore = vault.balanceOf(user);

//         vault.zapInDual{value: nativeAmount}(amount0, amount1, amount0Min, amount1Min);

//         uint256 supplyAfter = vault.totalSupply();
//         uint256 userSharesAfter = vault.balanceOf(user);

//         assertGt(supplyAfter, supplyBefore, "Shares should be minted on zapInDual");
//         assertGt(userSharesAfter, userSharesBefore, "User should receive shares on zapInDual");
//         assertEq(IERC20(address(vault.token0())).balanceOf(address(vault)), vaultToken0BalBefore);
//         assertEq(IERC20(address(vault.token1())).balanceOf(address(vault)), vaultToken1BalBefore);
//         assertEq(address(vault).balance, vaultNativeBalBefore);
//     }

//     // function ZapOutTest(uint128 shares, uint256 amount0Min, uint256 amount1Min, address user) internal {
//     //     uint256 vaultToken0BalBefore = IERC20(address(vault.token0())).balanceOf(address(vault));
//     //     uint256 vaultToken1BalBefore = IERC20(address(vault.token1())).balanceOf(address(vault));
//     //     uint256 vaultNativeBalBefore = address(vault).balance;
//     //     uint256 supplyBefore = vault.totalSupply();
//     //     uint256 userSharesBefore = vault.balanceOf(user);
//     //     uint256 token0BalanceBefore = IERC20(vault.token0()).balanceOf(user);
//     //     uint256 token1BalanceBefore = IERC20(vault.token1()).balanceOf(user);

//     //     vault.zapOut(shares, amount0Min, amount1Min);

//     //     uint256 supplyAfter = vault.totalSupply();
//     //     uint256 userSharesAfter = vault.balanceOf(user);
//     //     uint256 token0BalanceAfter = IERC20(vault.token0()).balanceOf(user);
//     //     uint256 token1BalanceAfter = IERC20(vault.token1()).balanceOf(user);

//     //     assertLt(supplyAfter, supplyBefore, "Total supply should decrease on zapOut");
//     //     assertLt(userSharesAfter, userSharesBefore, "User shares should decrease on zapOut");
//     //     assertGe(token0BalanceAfter, token0BalanceBefore, "User should receive token0");
//     //     assertGe(token1BalanceAfter, token1BalanceBefore, "User should receive token1");
//     //     assertEq(IERC20(address(vault.token0())).balanceOf(address(vault)), vaultToken0BalBefore);
//     //     assertEq(IERC20(address(vault.token1())).balanceOf(address(vault)), vaultToken1BalBefore);
//     //     assertEq(address(vault).balance, vaultNativeBalBefore);
//     // }

//     // function ZapOutAndSwapTest(
//     //     uint128 shares,
//     //     address desiredToken,
//     //     uint256 amount0Min,
//     //     uint256 amount1Min,
//     //     uint256 amountOutMin,
//     //     address user
//     // ) internal {
//     //     uint256 vaultToken0BalBefore = IERC20(address(vault.token0())).balanceOf(address(vault));
//     //     uint256 vaultToken1BalBefore = IERC20(address(vault.token1())).balanceOf(address(vault));
//     //     uint256 vaultNativeBalBefore = address(vault).balance;
//     //     uint256 supplyBefore = vault.totalSupply();
//     //     uint256 userSharesBefore = vault.balanceOf(user);
//     //     uint256 tokenOutBalanceBefore = IERC20(desiredToken).balanceOf(user);

//     //     vault.zapOutAndSwap(shares, amount0Min, amount1Min, desiredToken, amountOutMin);

//     //     uint256 supplyAfter = vault.totalSupply();
//     //     uint256 userSharesAfter = vault.balanceOf(user);
//     //     uint256 tokenOutBalanceAfter = IERC20(desiredToken).balanceOf(user);

//     //     assertLt(supplyAfter, supplyBefore, "Total supply should decrease on zapOutAndSwap");
//     //     assertLt(userSharesAfter, userSharesBefore, "User shares should decrease on zapOutAndSwap");
//     //     assertGt(tokenOutBalanceAfter, tokenOutBalanceBefore, "User should receive tokenOut");
//     //     assertEq(IERC20(address(vault.token0())).balanceOf(address(vault)), vaultToken0BalBefore);
//     //     assertEq(IERC20(address(vault.token1())).balanceOf(address(vault)), vaultToken1BalBefore);
//     //     assertEq(address(vault).balance, vaultNativeBalBefore);
//     // }

//     // function HarvestTest(
//     //     uint256 amountOutMin0,
//     //     uint256 amountOutMin1,
//     //     uint256 amountOutMin2,
//     //     uint256 amount0Min,
//     //     uint256 amount1Min
//     // ) internal {
//     // uint256 token0BalanceBefore = IERC20(vault.token0()).balanceOf(address(vault));
//     // uint256 token1BalanceBefore = IERC20(vault.token1()).balanceOf(address(vault));

//     // HarvestParams memory params = HarvestParams({
//     //     amountOutMin0: amountOutMin0,
//     //     amountOutMin1: amountOutMin1,
//     //     amountOutMin2: amountOutMin2,
//     //     amount0Min: amount0Min,
//     //     amount1Min: amount1Min,
//     //     keyParams: keyParams
//     // });
//     // IVault.HarvestParams memory ivaultParams = IVault.HarvestParams({
//     //     amountOutMin0: params.amountOutMin0,
//     //     amountOutMin1: params.amountOutMin1,
//     //     amountOutMin2: params.amountOutMin2,
//     //     amount0Min: params.amount0Min,
//     //     amount1Min: params.amount1Min,
//     //     keyParams: params.keyParams
//     // });
//     // vault.harvest(ivaultParams);

//     // uint256 token0BalanceAfter = IERC20(vault.token0()).balanceOf(address(vault));
//     // uint256 token1BalanceAfter = IERC20(vault.token1()).balanceOf(address(vault));

//     // assertTrue(
//     //     token0BalanceAfter > token0BalanceBefore || token1BalanceAfter > token1BalanceBefore,
//     //     "Harvest should increase at least one token balance"
//     // );
//     //}
// }
