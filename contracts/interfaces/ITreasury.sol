// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface ITreasury {

    function deposit(address _from, uint _amount) external;
    function withdraw (address _recipient, uint _amount) external; // onlyDistributor

}