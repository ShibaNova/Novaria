// SPDX-License-Identifier: MIT
 
pragma solidity 0.8.7;

import "./ShipEngineering.sol";
import "./interfaces/IMap.sol";
 
contract ShipyardManager is ShipEngineering {
 
    IMap public Map;
    ITreasury public Treasury;

    constructor (IMap _map, ITreasury _treasury) {
        Map = _map;
        Treasury = _treasury;
    }
    
    function setTreasury (address _treasury) external onlyOwner {
        Map = IMap(_treasury);
    }

    struct Shipyard {
        address owner;
        uint coordX;
        uint coordY;
        uint feePercent; 
    }
    Shipyard [] public shipyards;

    struct DryDock {
        ShipClass shipClass;
        uint amount;
        uint buildTime;
    }
    mapping (address => mapping (uint => mapping (uint => DryDock))) playerDocks;
 
    function addShipyard (address _owner, uint _x, uint _y, uint _feePercent)  public onlyOwner {
        require(isShipyardLocation(_x, _y) != true, 'Shipyard: shipyard already exists at location');
        shipyards[] = ShipYard(_owner, _x, _y, _feePercent);
    }

    function isShipyardLocation(uint _x, uint _y) public {
        for(i=0;i<shipyards.length;i++) {
            if(shipyards[i].coordX == _x && shipyards[i].coordY == _y) {
                return true;
            }
        }
        return false;
    }

    function getDockCost(strint memory _shipClass, uint _amount) public returns(uint) {
        return _amount * shipClasses[_shipClass].cost * Treasury.getCostMod();
    }
    
    // Ship building Function
    function buildShips(uint _x, uint _y, string memory _shipClass, uint _amount, uint _buildTime) external {
        ShipClass shipClass = shipClasses[_shipClass];
        
        uint totalCost = _amount * shipClass.cost;
        Treasury.deposit(msg.sender, totalCost);
 
        playerDocks[msg.sender][_x][_y] = DryDock(shipClasses[_shipClass], _amount, _buildTime);
 
        //TODO: need to add build time feature
        //TODO: need to add max restriction
    }

    function getDryDock(uint _x, uint _y, address _player) view external {
        return playerDocks[_player][_x][_y];
    }
}