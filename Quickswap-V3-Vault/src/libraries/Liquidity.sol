// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6;

import "@cryptoalgebra/periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@cryptoalgebra/core/contracts/interfaces/IAlgebraPool.sol";
import "@cryptoalgebra/periphery/contracts/libraries/LiquidityAmounts.sol";
import "@cryptoalgebra/core/contracts/libraries/TickMath.sol";

library Liquidity {
    function getAmountsForLiquidity(
        address pool,
        address nonfungiblePositionManager,
        uint256 tokenId,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256, uint256) {
        (uint160 sqrtPriceX96,,,,,,) = IAlgebraPool(pool).globalState();
        (,,,,,, uint128 liquidity,,,,) = INonfungiblePositionManager(nonfungiblePositionManager).positions(tokenId);
        return LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
    }
}
