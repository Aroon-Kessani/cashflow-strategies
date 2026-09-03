// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@pancakeswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@pancakeswap/v3-core/contracts/interfaces/IPancakeV3Pool.sol";
import "@pancakeswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@pancakeswap/v3-core/contracts/libraries/TickMath.sol";

library Liquidity {
    function getAmountsForLiquidity(
        address pool,
        address positionManager,
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256, uint256) {
        (uint160 sqrtPriceX96,,,,,,) = IPancakeV3Pool(pool).slot0();
        (,,,,,,, uint128 liquidity,,,,) = INonfungiblePositionManager(positionManager).positions(tokenId);
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
    }
}
