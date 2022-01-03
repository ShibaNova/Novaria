// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface Map {
    function getPlace(uint _x, uint _y) external view returns (Place memory);
}