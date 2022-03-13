// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface ITreasury {

    function pay(address _from, uint _amount) external;
    function deposit(address _from, uint _amount) external;
    function withdraw (address _recipient, uint _amount) external; // onlyDistributor
    function getCostMod() external view returns(uint);
    function getAvailableAmount() external view returns(uint);
}