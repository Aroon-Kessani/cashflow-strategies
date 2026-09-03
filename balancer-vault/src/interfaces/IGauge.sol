// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IGauge {
    function balanceOf(address account) external view returns (uint256);
    function claimable_reward(address _addr, address _token) external view returns (uint256);
    function claimable_tokens(address _addr) external view returns (uint256);
    function claim_rewards() external;
    function claim_rewards(address _addr, address _receiver, uint256[] memory _reward_indexes) external;
    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external;
    function reward_contract() external view returns (address);
}
