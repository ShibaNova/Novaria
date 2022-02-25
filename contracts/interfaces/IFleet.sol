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
    function addShipyard(string calldata _name, address _owner, uint _x, uint _y, uint8 _feePercent) external;
    function addExperience(address _player, uint _paid) external;
    function getExperience(address _player) external view returns (uint);
}