// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IShadowPool {
    function replenish(address _jackpot, uint _value) external returns(uint);
}