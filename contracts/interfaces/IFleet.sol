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
        string memory _name
        ) external; // onlyPurchaser
    function addPowerMod(uint8 _value, address _sender) external; // onlyPurchaser
    function subPowerMod(uint8 _value, address _sender) external; // onlyPurchaser
    function setLaunched(address _player, bool _status) external;
    function getLaunchStatus(address _player) external view returns(bool);
    function setPower(uint _id, uint _amount) external;
    function setCarryCapacity(uint _id, uint _amount) external;
    
}