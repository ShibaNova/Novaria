// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./libs/Editor.sol";
import "./libs/ShibaBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./interfaces/ITreasury.sol";

/*
TO-DO:
- set functions to edit personal max fighters/miners 
- add experience attribute
- add 10 new ship placeholders
- restructure the ships, remove from capital, make own struct
- add attributes for each ship type
*/

contract Fleet is Editor {
    using SafeBEP20 for ShibaBEP20;

    event NewCapitalShip(uint shipID, string name);
    event NewTreasury(address newAddress);
    event NewNovaAddress(address newNova);

    ShibaBEP20 public Nova;
    address public Treasury;
    // Be sure to set this contract as a editor after deployment
    constructor(
        ShibaBEP20 _Nova,
        address _Treasury
        
    ) {
        Nova = _Nova;
        Treasury = _Treasury;
    }

    // Info of the player's capital ship
    struct CapitalShip {
        string name;
        uint power;
        uint8 powerMod;
        uint256 carryCapacity;
        uint experience;
        uint16 wins;
        uint16 losses;
    }

    CapitalShip[] public capitalShips;

    
    mapping (uint => address) public capitalShipOwner;
    mapping (address => uint) public ownerShipId;
    mapping (address => uint) ownerCapitalShipCount;
    mapping (address => bool) public editor;
    mapping (address => bool) isLaunched; // flag to check if a player has already prepared/launched their fleet

    // set treasury address
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "FLEET: Cannot set treasury to 0 address");
        Treasury = _treasury;
        emit NewTreasury(_treasury);
    }

    //update the nova token address
    function setNovaAddress(address _newAddress) external onlyOwner {
        Nova = ShibaBEP20(_newAddress);
        emit NewNovaAddress(_newAddress);
    }


    function setLaunched(address _player, bool _status) external {
        require(isLaunched[_player] != _status, "FLEET: Player already in this state");
        isLaunched[_player] = _status;
    }

    function getLaunchStatus(address _player) public view returns(bool) {
        return isLaunched[_player];
    }

    function isContract(address _address) internal view returns (bool){
    uint32 size;
    assembly {
        size := extcodesize(_address)
    }
    return (size > 0);
    }

    // capital ship info helpers
    function getOwnerCapitalShipCount(address _owner) external view returns(uint) {
        return ownerCapitalShipCount[_owner];
    }

    function getCapShipOwner(uint _id) external view returns (address) {
        return capitalShipOwner[_id];
    }

    function getOwnerShipId(address _owner) external view returns (uint) {
        return ownerShipId[_owner];
    }

    function capShipLength() public view returns (uint256) {
        return capitalShips.length;
    }

    // get capital ship personal record
    function getCapitalShipRecord(uint256 _id) external view returns(
            string memory name,
            uint16 wins,
            uint16 losses,
            uint experience
            ) {
            return (
                capitalShips[_id].name,
                capitalShips[_id].wins,
                capitalShips[_id].losses,
                capitalShips[_id].experience
            );
    }

    // get capital ship combat stats and mining power
    function getCapitalShip(uint256 _id) external view returns(
            uint power,
            uint8 powerMod,
            uint256 carryCapacity
        ) {
            return (
                capitalShips[_id].power,
                capitalShips[_id].powerMod,
                capitalShips[_id].carryCapacity
            );
        }
    
    // external function to build capital ship, _sender should be the address of the player, not the contracts interacting with this
    function buildCapShip (
        address _sender,
        string memory _name 
        ) external onlyEditor {
            require(ownerCapitalShipCount[_sender] == 0, "FLEET: Each player can only have one Capital Ship");
            ownerCapitalShipCount[msg.sender]++;
            Nova.transferFrom(_sender, Treasury, baseCapCost);
            ITreasury(Treasury).sendFee();
            uint id = capShipLength();
            capitalShips.push(CapitalShip({
                name: _name, 
                power: 0,
                powerMod: 0, 
                carryCapacity: 0, 
                wins: 0, 
                losses: 0,
                experience: 0
                }));

        capitalShipOwner[id] = _sender;
        ownerShipId[_sender] = id;
        emit NewCapitalShip(id, _name);
    }

    //Extneral function to set the total power
    function setPower(uint _id, uint _amount) external onlyEditor {
        capitalShips[_id].power = _amount;
    }  
    //External function to set the carry capacity
    function setCarryCapacity(uint _id, uint _amount) external onlyEditor {
        capitalShips[_id].carryCapacity = _amount;
    }

    
    // set the capital ship's powerMod
    function addPowerMod(uint8 _value, address _sender) external onlyEditor {
        uint _id = ownerShipId[_sender];
        require(capitalShips[_id].powerMod + _value <= 255, "FLEET: player's powerMod is capped");
        capitalShips[_id].powerMod = capitalShips[_id].powerMod + _value;
    }

    function subPowerMod(uint8 _value, address _sender) external onlyEditor {
        uint _id = ownerShipId[_sender];
        if (capitalShips[_id].powerMod - _value <= 0) {
            capitalShips[_id].powerMod = 0;
        } else {
        capitalShips[_id].powerMod = capitalShips[_id].powerMod + _value;
        }
    }

    

}