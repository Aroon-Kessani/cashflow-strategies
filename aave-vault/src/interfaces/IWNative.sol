pragma solidity ^0.8.19;

interface IWNative {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
