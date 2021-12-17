// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface ITreasury {

    function sendFee() external; // onlyDistributor
    function withdraw (address _recipient, uint _amount) external; // onlyDistributor

}