// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";

library Swap {
    using SafeMath for uint256;

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x.add(1)).div(2);
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x.div(z).add(z)).div(2);
        }
        return y;
    }

    function calculateSwapInAmount(uint256 reserveIn, uint256 userIn, uint256 fee) internal pure returns (uint256) {
        (uint256 result0, uint256 result1) = getConstant(fee);
        return (sqrt(reserveIn * ((userIn * result1 * 4000) + (reserveIn * result0 * result0))) - (reserveIn * result0))
            / (2 * result1);
    }

    function getConstant(uint256 fee) internal pure returns (uint256 result0, uint256 result1) {
        require(fee < 1000000);
        result0 = (2000000 - fee).div(1000);
        result1 = (1000000 - fee).div(1000);
    }
}
