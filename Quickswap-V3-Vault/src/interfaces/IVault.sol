// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;
pragma abicoder v2;

interface IVault {
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

    function multicall(address[] calldata targets, bytes[] calldata data) external returns (bytes[] memory results);

    function deductFees(address token) external;

    function updateFeeReceiverAddress(address _feeReceiver) external;

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs,
        address rewardDistributor
    ) external;

    function setFarmingRewardClaimer(address rewardDistributor, address claimer) external;

    function approve(address token, address spender, uint256 amount) external;

    function updateFeePercentage(uint256 _platformFeePercentage) external;

    function setMulticallWhitelist(address target, bool allowed) external;

    function initializeVault(
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min,
        int24 _tickLower,
        int24 _tickUpper,
        address _pool
    ) external payable;

    function collectFees() external;
}
