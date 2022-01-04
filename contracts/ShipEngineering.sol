// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITreasury.sol";

contract ShipEngineering is Ownable {

    ITreasury public Treasury;

    struct ShipClass {
        string name;
        uint size;
        uint attack;
        uint shield;
        uint oreCapacity;
        uint hangarSize;
        uint buildTime;
        uint cost;
    }

    mapping (string => ShipClass) public shipClasses;

    constructor(
        ITreasury _treasury
    ) {
        Treasury = _treasury;
        createShipClass("Viper", "viper", 1, 1, 5, 0, 0, 1, 1);
        createShipClass("Mole", "mole", 2, 0, 10, 1, 0, 1, 3);
        createShipClass("Corvette", "corvette", 5, 4, 2, 35, 5, 3, 10);
    } 

    function createShipClass(
        string memory _name,
        string memory _handle,
        uint _size,
        uint _attack,
        uint _shield,
        uint _oreCapacity,
        uint _hangarSize,
        uint _buildTime,
        uint _cost) public onlyOwner {

            shipClasses[_handle] = ShipClass(_name, _size, _attack, _shield, _oreCapacity, _hangarSize, _buildTime, _cost);
        }

    function getShipClass(string memory _handle) external view returns(ShipClass memory){
        return shipClasses[_handle];
    }

    function editCost(string memory _handle, uint _newCost) public onlyOwner {
        shipClasses[_handle].cost = _newCost;
    }
}