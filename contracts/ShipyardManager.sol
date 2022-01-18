// SPDX-License-Identifier: MIT
 
pragma solidity 0.8.7;

import "./ShipEngineering.sol";
import "./interfaces/IMap.sol";
import "./libs/ShibaBEP20.sol";
import "./libs/SafeBEP20.sol";
 
abstract contract ShipyardManager is ShipEngineering {
 
    using SafeBEP20 for ShibaBEP20;
    IMap public Map;

    constructor (IMap _map, ITreasury _treasury, ShibaBEP20 _Nova) {
        Map = _map;
        Treasury = _treasury;
        Nova = _Nova;
        maxFleetSize = 1000;
    }
    
    ShibaBEP20 public Nova; // nova token address
    uint maxFleetSize;

    function setTreasury (address _treasury) external onlyOwner {
        Map = IMap(_treasury);
    }

    struct Shipyard {
        uint id;
        address owner;
        uint coordX;
        uint coordY;
        uint feePercent; 
        bool exists;
    }
    Shipyard[] public shipyards; //list of shipyards
    mapping (uint => mapping (uint => Shipyard)) coordinateShipyards; //index to quickly track where shipyards are

    struct DryDock {
        ShipClass shipClass;
        uint amount; 
        uint completionTime;
    }

    // player address -> shipyard ID -> Drydock
    mapping (address => mapping (uint => DryDock)) playerDryDocks; //each player can have only 1 drydock at each location

    // player address -> ship class -> number of ships
    mapping (address => mapping(string => uint)) fleets; //player fleet composition
 
    function addShipyard(address _owner, uint _x, uint _y, uint _feePercent)  public onlyOwner {
        require(coordinateShipyards[_x][_y].exists, 'Shipyard: shipyard already exists at location');
        require(Map.isShipyardLocation(_x, _y) == true, 'Shipyard: shipyard not possible at this location');

        uint shipyardId = shipyards.length;
        shipyards.push(Shipyard(shipyardId, _owner, _x, _y, _feePercent, true));
        coordinateShipyards[_x][_y] = shipyards[shipyardId];
    }

    function getShipyards() external view returns(Shipyard[] memory) {
        return shipyards;
    }

    function getDockCost(string memory _shipClass, uint _amount) public view returns(uint) {
        return _amount * shipClasses[_shipClass].cost * Treasury.getCostMod();
    }

    function getBuildTime(string memory _shipClass, uint _amount) public view returns(uint) {
        return _amount * shipClasses[_shipClass].buildTime;
    }
    
    // Ship building Function
    function buildShips(uint _x, uint _y, string memory _shipClass, uint _amount) external {
        Shipyard memory shipyard = coordinateShipyards[_x][_y];
        require(shipyard.exists, 'Shipyard: no shipyard at this location');
        require(playerDryDocks[msg.sender][shipyard.id].amount > 0, 'DryDock: already in progress or ships waiting to be claimed');
        require((shipClasses[_shipClass].size * _amount) < maxFleetSize, 'DryDock: order is too large');

        //total build cost
        uint totalCost = getDockCost(_shipClass, _amount);

        //send fee to shipyard owner
        uint ownerFee = (totalCost * shipyard.feePercent) / 100;
        Nova.safeTransferFrom(shipyard.owner, msg.sender, ownerFee);

        Treasury.deposit(msg.sender, totalCost - ownerFee);

        uint completionTime = block.timestamp + (getBuildTime(_shipClass, _amount) * 60);
        playerDryDocks[msg.sender][shipyard.id] = DryDock(shipClasses[_shipClass], _amount, completionTime);
    }

    function getDryDock(uint _x, uint _y, address _player) view external returns(DryDock memory){
        return playerDryDocks[_player][coordinateShipyards[_x][_y].id];
    }

    function getFleetSize() public view returns(uint) {
        address player = msg.sender;
        uint fleetSize = 0;
        for(uint i=0; i<shipClassesList.length; i++) {
            fleetSize += fleets[player][shipClassesList[i]];
        }
        return fleetSize;
    }

    function destroyShips(string memory _shipClass, uint _amount) external {
        fleets[msg.sender][_shipClass] -= (Helper.getMax(_amount, fleets[msg.sender][_shipClass]));
    }

    /* move ships to fleet, call must fit the following criteria:
        1) fleet must be at same location as shipyard being requested
        2) amount requested must be less than or equal to amount in dry dock
        3) dry dock build must be completed (completion time must be past block timestamp)
        4) claim size must not put fleet over max fleet size */
    function claimShips(uint _x, uint _y, uint _amount) external {
        Shipyard memory shipyard = coordinateShipyards[_x][_y];
        require(shipyard.exists, 'Shipyard: no shipyard at this location');

        DryDock storage dryDock = playerDryDocks[msg.sender][shipyard.id];
        require(_amount <= dryDock.amount, 'Dry Dock: ship amount requested not available in dry dock');
        require(block.timestamp > dryDock.completionTime, 'Dry Dock: ships not built, yet');

        ShipClass memory dryDockClass = dryDock.shipClass;

        uint claimSize = _amount * dryDockClass.size;
        uint fleetSize = getFleetSize(); //player's current fleet size

        require(fleetSize + claimSize < maxFleetSize, 'Claim size requested cannot be larger than max fleet size');

        fleets[msg.sender][dryDockClass.name] += _amount; //add ships to fleet
        dryDock.amount -= _amount; //remove ships from drydock
    }
}