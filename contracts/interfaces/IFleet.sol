// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// Interface for external contracts to interact with the DryDock

interface IFleet {
    function getFleetMaxMineralCapacity() external view returns (uint);
    function getFleetMiningCapacity() external view returns (uint);
}