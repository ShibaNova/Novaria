// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// Interface for external contracts to interact with the DryDock

interface IFleet {
    function getMaxMineralCapacity(address player) external view returns (uint);
    function getMiningCapacity(address _player) external view returns (uint);
    function getMaxFleetSize(address player) external view returns (uint);
    function getFleetSize(address player) external view returns(uint);
}