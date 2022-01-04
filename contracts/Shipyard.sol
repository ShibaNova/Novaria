// SPDX-License-Identifier: MIT
 
pragma solidity 0.8.7;

import "./ShipEngineering.sol";
import "./interfaces/IMap.sol";
 
contract ShipyardManager is ShipEngineering {
 
    IMap public Map;

    constructor (
        IMap _map
    ) {
        Map = _map;
    }

    struct Shipyard {
        address owner;
        uint coordX;
        uint coordY;
        uint buildCost;
        uint feePercent; 
    }
    Shipyard [] public shipyards;

    struct DryDock {
        ShipClass shipClass;
        uint amount;
        uint buildTime;
    }
    mapping (address => mapping (uint => mapping (uint => DryDock))) playerDocks;
 
    function addShipyard (uint _x, uint _y) public onlyOwner {
        //require(Map.getPlayerLocation(_player) = [x,y]);
        require(isShipyardLocation(_x, _y == true);
        ShipYard
        
    }

    function isShipyardLocation(uint _x, uint _y) {
        for(i=0;i<shipyards.length;i++) {
            if(shipyards[i].coordX == _x && shipyards[i].coordY == _y) {
                return true;
            }
        }
        return false;
    }


    
    // Ship building Function
    function buildShips(uint _x, uint _y, string memory _shipClass, uint _amount, uint _buildTime) external {
        ShipClass shipClass = shipClasses[_shipClass];
        
        uint totalCost = _amount * shipClass.cost;
        Nova.transferFrom(msg.sender, address(Treasury), totalCost);
        Treasury.sendFee();
 
        playerDocks[msg.sender][_x][_y] = DryDock(shipClasses[_shipClass], _amount, _buildTime);
 
        //TODO: need to add build time feature
        //TODO: need to add max restriction
    }

    function getDryDock(uint _x, uint _y, address _player) view external {
        return playerDocks[_player][_x][_y];
    }
}