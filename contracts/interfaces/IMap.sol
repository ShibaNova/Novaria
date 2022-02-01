// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

interface IMap {
    function isRefinery(uint _x, uint _y) external view returns(bool);
    function getFleetLocation (address _player) external view returns(uint x, uint y);
    function isShipyardLocation(uint _x, uint _y) external view returns (bool);
    function setFleetLocation(address _player, uint _x, uint _y) external;
    function transferMineral(address _sender, address _receiver, uint _amount) external;
    function mineralGained(address _player, int _amount) external;
    function getFleetMineral(address _player) external view returns(uint);
    function getPlaceName(uint _x, uint _y) external view returns(string memory);
    function increasePreviousBalance(uint _amount) external;
    function addScrapToPlace(uint _x, uint _y, uint _amount) external;
}