// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IBatchRouter.sol";

interface IVault {
    error ZeroAddress();
    error ArrayLengthMismatch();
    error NotWhitelisted(address target);
    error NotEnoughShares();
    error InvalidAmount();
    error ETHRefundFailed();
    error IncorrectETHSent();
    error PoolTokenIsZero();
    error GaugeTargetForbidden();
    error MulticallSubcallFailed(address target, bytes data);

    function depositProportional(
        address recipient,
        bool[] memory wrapUnderlying,
        uint256[] memory maxInputAmounts,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 shareAmount);

    function depositUnbalanced(
        address recipient,
        bool[] memory wrapUnderlying,
        uint256[] memory inputAmounts,
        uint256 minBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable returns (uint256 shareAmount);

    function withdraw(
        uint256 sharesToBurn,
        uint256[] memory minAmountsOut,
        bool[] memory unwrapWrapped,
        bool wethIsEth,
        bytes memory userData
    )
        external
        returns (address[] memory tokensOut, uint256[] memory amountsOut);

    function multicall(
        address[] calldata targets,
        bytes[] calldata data
    ) external returns (bytes[] memory results);
    function approve(address token, address spender, uint256 amount) external;
    function permit2Approve(
        address permit2,
        address token,
        address spender,
        uint160 amount,
        uint48 expiration
    ) external;
    function setMulticallWhitelist(address target, bool allowed) external;
    function updateFeePercentage(uint256 _platformFeePercentage) external;
    function claimRewards() external;
    function deductFees(address token) external;
    function updateFeeReceiverAddress(address _feeReceiver) external;
}
