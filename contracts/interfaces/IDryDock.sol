// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// Interface for external contracts to interact with the DryDock

interface IDryDock {
    function capShipLength() external view returns (uint256);
    function getCapShpiOwner(uint _id) external view returns (address);
    function getOwnerShipId(address _owner) external view returns (uint);
    function getOwnerCapitalShipCount(address _owner) external view returns(uint);
    function getCapitalShipRecord (uint256 _id) external view returns(
            string memory name,
            uint16 wins,
            uint16 losses
            );
    function getCapitalShip(uint256 _id) external view returns(
            uint16 fighters,
            uint16 maxFighters,
            uint8 powerMod,
            uint16 miners,
            uint16 maxMiners,
            uint256 carryCapacity
        );
    function buildCapShip (
        address _sender,
        string memory _name, 
        uint _amount, 
        uint16 _startFighters, 
        uint16 _currentMaxFighters, 
        uint16 _startMiners, 
        uint16 _currentMaxMiners
        ) external; // onlyPurchaser
    function addFighter (address _sender, uint16 _value) external; // onlyPurchaser
    function subFighter (address _sender, uint16 _value) external; // onlyPurchaser
    function buyFighters (uint16 _value) external;
    function addMiner(address _sender, uint16 _value) external; // onlyPurchaser
    function subMiner (address _sender, uint16 _value) external; // onlyPurchaser
    function buyMiners (uint16 _value) external;
    function addPowerMod(uint8 _value, address _sender) external; // onlyPurchaser
    function subPowerMod(uint8 _value, address _sender) external; // onlyPurchaser

}