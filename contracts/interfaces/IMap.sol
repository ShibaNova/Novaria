// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IMap {
    function isRefineryLocation(uint _x, uint _y) external view returns(bool);
    function getFleetLocation (address _player) external view returns(uint x, uint y);
    function isShipyardLocation(uint _x, uint _y) external view returns (bool);
    function setFleetLocation(address _player, uint _xTo, uint _yTo, uint _xFrom, uint _yFrom) external;
    function getPlaceName(uint _x, uint _y) external view returns(string memory);
    function increasePreviousBalance(uint _amount) external;
    function addSalvageToPlace(uint _x, uint _y, uint _amount) external;
}