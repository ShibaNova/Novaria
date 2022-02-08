// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// Interface for external contracts to interact with the DryDock

interface IFleet {
    function getMineralCapacity(address player) external view returns (uint);
    function getMiningCapacity(address _player) external view returns (uint);
    function getMaxFleetSize(address player) external view returns (uint);
    function getFleetSize(address player) external view returns(uint);
    function isInBattle(address _player) external view returns(bool);
    function getMineral(address _player) external view returns(uint);
    function setMineral(address _player, uint _amount) external;
}