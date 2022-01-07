// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IMap {
        function getPlace(uint _x, uint _y) external view returns(
        string memory name,
        string memory placeType,
        bool isDmz,
        bool isRefinery,
        bool isActive
    );
    function isRefinery(uint _x, uint _y) external view returns(bool);
    function getPlayerLocation (address _player) external view returns(uint x, uint y);
}