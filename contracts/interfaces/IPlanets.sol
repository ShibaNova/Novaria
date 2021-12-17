// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IPlanets {

    function getPlanetInfo (uint _id) external view returns (string memory name, uint distance);
    function planetsLength() external view returns (uint);
}