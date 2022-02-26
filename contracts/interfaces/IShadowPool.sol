// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IShadowPool {
    function replenishPlace(address _map, uint _mod) external;
}