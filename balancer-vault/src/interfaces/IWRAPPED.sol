// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IWRAPPED {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
}
