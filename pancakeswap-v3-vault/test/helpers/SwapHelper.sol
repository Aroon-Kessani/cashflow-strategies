// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "@pancakeswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

library SwapHelper {
    function singleSwap(
        address tokenIn,
        address tokenOut,
        uint256 amountToSwap,
        uint256 amountOutMinimum,
        uint24 fee,
        address router,
        address to
    ) internal returns (uint256) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: to,
            deadline: block.timestamp + 300, // 5 minutes from now
            amountIn: amountToSwap,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0 // No price limit
        });
        return ISwapRouter(router).exactInputSingle{value: amountToSwap}(params);
    }
}
