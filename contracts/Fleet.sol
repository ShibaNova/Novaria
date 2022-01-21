// SPDX-License-Identifier: MIT
 
pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITreasury.sol";
import './libs/Helper.sol';
import "./interfaces/IMap.sol";
import "./libs/ShibaBEP20.sol";
import "./libs/SafeBEP20.sol";
 
    //miningCooldown - 30 min.
    //jumpDriveCooldown - 30 min + distance
    //attackWindow - 30 min.
    //defendWindow - 30 min.
    //building ships

contract Fleet is Ownable {
    using SafeBEP20 for ShibaBEP20;

    constructor (
       // IMap _map, 
       // ITreasury _treasury, 
       // ShibaBEP20 _Token
        ) {
        Map = IMap(0xE3Ca443c9fd7AF40A2B5a95d43207E763e56005F);
        Treasury = ITreasury(0xd8b934580fcE35a11B58C6D73aDeE468a2833fa8);
        Token = ShibaBEP20(0xd9145CCE52D386f254917e481eB44e9943F39138);
        baseMaxFleetSize = 1000;
        baseFleetSize = 100;
        timeModifier = 5;
        attackWindow = 1800; //30 minutes
        defendWindow = 1800; //30 minutes
        createShipClass("Viper", "viper", 1, 1, 5, 0, 0, 0, 60, 10**18);
        createShipClass("Mole", "mole", 2, 0, 10, 10**17, 5 * 10**16, 0, 30, 2 * 10**18);
        addShipyard(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,0,0,7);
    }

    //ship class data
    struct ShipClass {
        string name;
        string handle;
        uint size;
        uint attack;
        uint shield;
        uint mineralCapacity;
        uint miningCapacity;
        uint hangarSize;
        uint buildTime;
        uint cost;
    }
    mapping (string => ShipClass) public shipClasses;
    string[] public shipClassesList; //iterable list for ship classes, better name?

    //shipyard data
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
   
   // ***Add function to view fleet!!!!
    // player address -> ship class -> number of ships
    mapping (address => mapping(string => uint)) public fleets; //player fleet composition

    //player names
    mapping (string => address) public names;
    mapping (address => string) public addressToName;

    //battle data
    struct Battle {
        uint id;
        address attackTarget;
        uint battleDeadline;
        address[] attackers;
        address[] defenders;
        bool exists;
    }
    Battle[] public battles;

    //mapping to easily player battles
    mapping (address => Battle) public targetToBattle;
    mapping (address => Battle) public playerToBattle;

    //initiate an attack against another player
    function attack(address _player, address _target) external {
        //verify players are at same location
        (uint attackX, uint attackY) = Map.getFleetLocation(_player);
        (uint targetX, uint targetY) = Map.getFleetLocation(_target);
        require(attackX == targetX && attackY == targetY, 'FLEET: attacker and target not at same location');
        require(playerToBattle[_player].exists == false, 'FLEET: attacker already in another battle');

        Battle storage foundBattle = targetToBattle[_target];

        //create battle if there is currently no attack against target
        if(foundBattle.exists == false) {
            uint battleDeadline = block.timestamp + _getAttackWindow() + _getDefendWindow();
            uint newBattleId = battles.length;

            //add new battle
            battles.push(Battle(newBattleId, _target, battleDeadline, new address[](0), new address[](0), true));
            Battle storage newBattle = battles[newBattleId];
            newBattle.attackers.push(_player);
            newBattle.defenders.push(_player);

            //add battle references
            playerToBattle[_player] = newBattle;
            targetToBattle[_target] = newBattle;
        }
        else {
            playerToBattle[_player] = foundBattle;
            foundBattle.attackers.push(_player);
        }
    }

    function leaveBattle(address _player) external {
        Battle storage playerBattle = playerToBattle[_player];
        require(playerBattle.exists == true, 'FLEET: attacker not in a battle');

        uint numAttackers = playerBattle.attackers.length;
        uint numDefenders = playerBattle.defenders.length;

        //if player is only participant in battle, end battle
        if(numAttackers + numDefenders == 1) {
            _endBattle(playerBattle);
        }
        else {
            //loop through battle attackers and find/remove player
            for(uint i=0; i<numAttackers; i++) {
                if(playerBattle.attackers[i] == _player) {
                    delete playerBattle.attackers[i];
                    playerBattle.attackers[i] = playerBattle.attackers[numAttackers-1];
                }
            }

            for(uint i=0; i<numDefenders; i++) {
                if(playerBattle.defenders[i] == _player) {
                    delete playerBattle.defenders[i];
                    playerBattle.defenders[i] = playerBattle.defenders[numDefenders-1];
                }
            }
            delete playerToBattle[_player]; //delete player connection to battle
        }

    }

    //after all attackers leave battle or battle is completed
    //remove targetToBattle reference
    //remove all attackers and defenders from playerToBattle reference
    //delete battle
    function _endBattle(Battle storage battleToEnd) internal {
        delete targetToBattle[battleToEnd.attackTarget];

        //remove all attacker references from playerToBattle
        uint numAttackers = battleToEnd.attackers.length;
        for(uint i=0; i<numAttackers; i++) {
            delete playerToBattle[battleToEnd.attackers[i]];
        }

        //remove all defender references from playerToBattle
        uint numDefenders = battleToEnd.defenders.length;
        for(uint i=0; i<numDefenders; i++) {
            delete playerToBattle[battleToEnd.defenders[i]];
        }

        //remove battle from battles list
        delete battles[battleToEnd.id];
        battles[battleToEnd.id] = battles[battles.length-1];
        battles.pop();
    }

    function _getAttackWindow() internal view returns (uint) {
        return attackWindow / timeModifier;
    }

    function _getDefendWindow() internal view returns (uint) {
        return defendWindow / timeModifier;
    }

    IMap public Map;
    ITreasury public Treasury;
    ShibaBEP20 public Token; // nova token address
    uint baseMaxFleetSize;
    uint baseFleetSize; //size of capital ship
    uint timeModifier;
    uint attackWindow;
    uint defendWindow;
    uint startFee = 10**18;

    event NewShipyard(uint _x, uint _y);

    function insertCoinHere(string memory _name) external {
        require(names[_name] == address(0), 'FLEET: Name already exists');
        require(bytes(addressToName[msg.sender]).length == 0, 'FLEET: player already has name');
        address player = msg.sender;
        Treasury.pay(player, startFee * Treasury.getCostMod());
        names[_name] = msg.sender;
        addressToName[msg.sender] = _name;
    }

    function createShipClass(
        string memory _name,
        string memory _handle,
        uint _size,
        uint _attack,
        uint _shield,
        uint _mineralCapacity,
        uint _miningCapacity,
        uint _hangarSize,
        uint _buildTime,
        uint _cost) public onlyOwner {

            shipClasses[_handle] = ShipClass(_name, _handle, _size, _attack, _shield, _mineralCapacity, _miningCapacity,_hangarSize, _buildTime, _cost);
            shipClassesList.push(_handle);
        }

    function getShipClass(string memory _handle) external view returns(ShipClass memory){
        return shipClasses[_handle];
    }

    function addShipyard(address _owner, uint _x, uint _y, uint _feePercent)  public onlyOwner {
        require(coordinateShipyards[_x][_y].exists == false, 'Shipyard: shipyard already exists at location');
        require(Map.isShipyardLocation(_x, _y) == true, 'Shipyard: shipyard not possible at this location');

        uint shipyardId = shipyards.length;
        shipyards.push(Shipyard(shipyardId, _owner, _x, _y, _feePercent, true));
        coordinateShipyards[_x][_y] = shipyards[shipyardId];
        emit NewShipyard(_x, _y);
    }

    function getShipyards() external view returns(Shipyard[] memory) {
        return shipyards;
    }

    function getDockCost(string memory _shipClass, uint _amount) public view returns(uint) {
        return (_amount * shipClasses[_shipClass].cost) / Treasury.getCostMod();
    }

    function getBuildTime(string memory _shipClass, uint _amount) public view returns(uint) {
        return (_amount * shipClasses[_shipClass].buildTime) / timeModifier;
    }
 
    // Ship building Function
    function buildShips(uint _x, uint _y, string memory _shipClass, uint _amount) external {
        address player = msg.sender;
        (uint fleetX, uint fleetY) = Map.getFleetLocation(player);
        require(fleetX == _x && fleetY == _y, 'FLEET: fleet not at designated shipyard');
        Shipyard memory shipyard = coordinateShipyards[_x][_y];
        require(shipyard.exists == true, 'FLEET: no shipyard at this location');
        require(playerDryDocks[player][shipyard.id].amount == 0, 'FLEET: already in progress or ships waiting to be claimed');
        require((shipClasses[_shipClass].size * _amount) < _getMaxFleetSize(player), 'FLEET: order is too large');

        //total build cost
        uint totalCost = getDockCost(_shipClass, _amount);

        //send fee to shipyard owner
        uint ownerFee = (totalCost * shipyard.feePercent) / 100;
        Token.safeTransferFrom(player, shipyard.owner, ownerFee);

        Treasury.pay(player, totalCost);

        uint completionTime = block.timestamp + getBuildTime(_shipClass, _amount);
        playerDryDocks[player][shipyard.id] = DryDock(shipClasses[_shipClass], _amount, completionTime);
    }

    function getDryDock(uint _x, uint _y, address _player) view external returns(DryDock memory){
        return playerDryDocks[_player][coordinateShipyards[_x][_y].id];
    }

    function getMaxFleetSize(address _player) external view returns (uint) {
        return _getMaxFleetSize(_player);
    }

    function _getMaxFleetSize(address _player) internal view returns (uint) {
        uint maxFleetSize = baseMaxFleetSize; 
        for(uint i=0; i<shipClassesList.length; i++) {
            uint shipClassAmount = fleets[_player][shipClassesList[i]]; //get number of player's ships in this ship class
            maxFleetSize += (shipClassAmount * shipClasses[shipClassesList[i]].hangarSize);
        }
        return maxFleetSize / Treasury.getCostMod();
    }

    function getFleetSize(address _player) external view returns(uint) {
        return _getFleetSize(_player);
    }
    
    function _getFleetSize(address _player) internal view returns(uint) {
        uint fleetSize = baseFleetSize / Treasury.getCostMod();
        for(uint i=0; i<shipClassesList.length; i++) {
            uint shipClassAmount = fleets[_player][shipClassesList[i]]; //get number of player's ships in this ship class
            fleetSize += (shipClassAmount * shipClasses[shipClassesList[i]].size);
        }
        return fleetSize;
    }


    function recall() external {
        address player = msg.sender;
        require(_getFleetSize(player) == baseFleetSize, "FLEET: fleet cannot have any ships for recall");
        Map.setFleetLocation(player, 0, 0);
    }

    //allow player to destroy part of their fleet to add different kinds of ships
    function destroyShips(string memory _shipClass, uint _amount) external {
        fleets[msg.sender][_shipClass] -= (Helper.getMin(_amount, fleets[msg.sender][_shipClass]));
    }

    /* move ships to fleet, call must fit the following criteria:
        1) fleet must be at same location as shipyard being requested
        2) amount requested must be less than or equal to amount in dry dock
        3) dry dock build must be completed (completion time must be past block timestamp)
        4) claim size must not put fleet over max fleet size */
    function claimShips(uint _x, uint _y, uint _amount) external {
        address player = msg.sender;
        (uint fleetX, uint fleetY) = Map.getFleetLocation(player);
        require(fleetX == _x && fleetY == _y, 'FLEET: fleet not at designated shipyard');
        Shipyard memory shipyard = coordinateShipyards[_x][_y];
        require(shipyard.exists == true, 'Shipyard: no shipyard at this location');

        DryDock storage dryDock = playerDryDocks[msg.sender][shipyard.id];
        require(_amount <= dryDock.amount, 'Dry Dock: ship amount requested not available in dry dock');
        require(block.timestamp > dryDock.completionTime, 'Dry Dock: ships not built, yet');

        ShipClass memory dryDockClass = dryDock.shipClass;

        uint claimSize = _amount * dryDockClass.size;
        uint fleetSize = _getFleetSize(player); //player's current fleet size

        require(fleetSize + claimSize < _getMaxFleetSize(player), 'Claim size requested cannot be larger than max fleet size');

        fleets[player][dryDockClass.handle] += _amount; //add ships to fleet
        dryDock.amount -= _amount; //remove ships from drydock
    }

    //get the max mineral capacity of player's fleet
    function getMaxMineralCapacity(address _player) public view returns (uint){
        uint mineralCapacity = 0;
        for(uint i=0; i<shipClassesList.length; i++) {
            string memory curShipClass = shipClassesList[i];
            mineralCapacity += (fleets[_player][curShipClass] * shipClasses[curShipClass].mineralCapacity);
        }
        return mineralCapacity / Treasury.getCostMod();
    }

    //get the max mining capacity of player's fleet (how much mineral can a player mine each mining attempt)
    function getMiningCapacity(address _player) public view returns (uint){
        uint miningCapacity = 0;
        for(uint i=0; i<shipClassesList.length; i++) {
            string memory curShipClass = shipClassesList[i];
            miningCapacity += (fleets[_player][curShipClass] * shipClasses[curShipClass].miningCapacity);
        }
        return miningCapacity / Treasury.getCostMod();
    }

    function setTimeModifier(uint _timeModifier) external onlyOwner{
        timeModifier = _timeModifier;
    }

    function setTreasury (address _treasury) external onlyOwner {
        Map = IMap(_treasury);
    }

    function editCost(string memory _handle, uint _newCost) public onlyOwner {
        shipClasses[_handle].cost = _newCost;
    }
}