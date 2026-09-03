// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "@cryptoalgebra/periphery/contracts/interfaces/ISwapRouter.sol";

library SwapHelper {
    function swapNativeToToken(
        address tokenIn,
        address tokenOut,
        uint256 amountToSwap,
        uint256 amountOutMinimum,
        address router,
        address recipient
    ) internal {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            recipient: recipient,
            deadline: block.timestamp,
            amountIn: amountToSwap,
            amountOutMinimum: amountOutMinimum,
            limitSqrtPrice: 0
        });
        ISwapRouter(router).exactInputSingle{value: amountToSwap}(params);
    }
}
