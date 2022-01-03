// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ShipEngineering is Ownable {
    struct ShipClass {
        string name;
        string handle;
        uint size;
        uint attack;
        uint shield;
        uint oreCapacity;
        uint hangarSize;
        uint buildTime;
        uint cost;
    }

    mapping (string => ShipClass) public shipClasses;

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
            ShipClass memory newShipClass = ShipClass(
                _name, _handle, _size, _attack, _shield, _oreCapacity, _hangarSize, _buildTime, _cost);

            shipClasses[_handle] = newShipClass;
        }

    constructor() {
        createShipClass("Viper", "viper", 1, 1, 5, 0, 0, 1, 1);
        createShipClass("Mole", "mole", 2, 0, 10, 1, 0, 1, 3);
        createShipClass("Corvette", "corvette", 5, 4, 2, 35, 5, 3, 10);
    } 
}