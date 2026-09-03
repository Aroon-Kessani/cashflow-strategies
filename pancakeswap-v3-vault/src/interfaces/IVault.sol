// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

interface IVault {
    function initializeVault(
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min,
        int24 _tickLower,
        int24 _tickUpper
    ) external payable;
    function zapInSingle(
        address recipient,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable returns (uint256 shareAmount);

    function zapInDual(address recipient, uint256 amount0, uint256 amount1, uint256 amount0Min, uint256 amount1Min)
        external
        payable
        returns (uint256 shareAmount);

    function zapOut(uint128 amount, uint256 amount0Min, uint256 amount1Min)
        external
        returns (uint256 amount0, uint256 amount1);

    function zapOutAndSwap(
        uint128 amount,
        uint256 amount0Min,
        uint256 amount1Min,
        address desiredToken,
        uint256 amountOutMin
    ) external;

    function setMulticallWhitelist(address target, bool allowed) external;

    function updateFeePercentage(uint256 _platformFeeBps) external;

    function updateFeeReceiverAddress(address _feeReceiver) external;

    function approve(address token, address spender, uint256 amount) external;

    function multicall(address[] calldata targets, bytes[] calldata data) external returns (bytes[] memory results);
    function deductFees(address token) external;
    function collectFees() external;
    function harvestReward() external;
}
