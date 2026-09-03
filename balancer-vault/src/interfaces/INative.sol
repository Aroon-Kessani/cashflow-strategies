// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface INative {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function transferFrom(address src, address dst, uint256 wad) external returns (bool);
}
