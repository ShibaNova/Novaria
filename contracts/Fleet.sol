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
        Map = IMap(0xf8e81D47203A594245E36C48e151709F0C19fBe8);
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
        address owner;
        uint coordX;
        uint coordY;
        uint feePercent;
        bool exists;
    }
    mapping (uint => mapping (uint => Shipyard)) coordinateShipyards; //shipyard locations

    struct DryDock {
        ShipClass shipClass;
        uint amount; 
        uint completionTime;
    }
    // player address -> shipyard x coordinate -> shipyard y coordinate -> Drydock
    mapping (address => mapping (uint => mapping (uint => DryDock))) playerDryDocks; //each player can have only 1 drydock at each location
   
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
    }
    Battle[] public battles;

    //mappings to easily access player battles
    //player can be in up to 2 battles, one where player is target and one where player is attacker or defender
    mapping (address => bool) public isPlayerTargetted;
    mapping (address => uint) public targetToBattle;

    mapping (address => bool) public isPlayerAttacking;
    mapping (address => bool) public isPlayerDefending;
    mapping (address => uint) public participantToBattle;

    //can player participate in this battle
    modifier canParticipateInBattle(address _player, address _target) {
        require(_player != _target, 'FLEET: Player/target cannot be the same player (dummy!)');

        //verify players are at same location
        (uint attackX, uint attackY) = Map.getFleetLocation(_player);
        (uint targetX, uint targetY) = Map.getFleetLocation(_target);
        require(attackX == targetX && attackY == targetY, 'FLEET: player and target not at same location');

        require(isPlayerAttacking[_player] == false && isPlayerDefending[_player] == false, 'FLEET: player already in another battle');

        require(_getFleetSize(_target) > _getBaseFleetSize(), 'FLEET: cannot attack a player that has no ships');
        require(_getFleetSize(_player) > _getBaseFleetSize(), 'FLEET: cannot attack/defend without ships');
        _;
    }

    //come to the defense of another player
    function defend(address _player, address _target) external canParticipateInBattle(_player, _target) {
        require(isPlayerTargetted[_target] == true, 'FLEET: cannot defend a player that is not under attack');

        Battle storage foundBattle = battles[targetToBattle[_target]];
        require(block.timestamp < (foundBattle.battleDeadline - _getAttackWindow()), 'FLEET: withdraw window is past');
        participantToBattle[_player] = foundBattle.id;
        isPlayerDefending[_player] = true;
        foundBattle.defenders.push(_player);
    }

    //initiate an attack against another player
    function attack(address _player, address _target) external canParticipateInBattle(_player, _target) {
        if(isPlayerTargetted[_target] == true) {
            Battle storage foundBattle = battles[targetToBattle[_target]];
            require(block.timestamp < (foundBattle.battleDeadline - _getAttackWindow()), 'FLEET: withdraw window is past');
            participantToBattle[_player] = foundBattle.id;
            foundBattle.attackers.push(_player);
        }
        else { //create battle if there is currently no attack against target
            uint battleDeadline = block.timestamp + _getAttackWindow() + _getDefendWindow();
            uint newBattleId = battles.length;
            battles.push(Battle(newBattleId, _target, battleDeadline, new address[](0), new address[](0)));
            Battle storage newBattle = battles[newBattleId];
            newBattle.attackers.push(_player);
            newBattle.defenders.push(_target);

            isPlayerTargetted[_target] = true;
            targetToBattle[_target] = newBattleId;
            participantToBattle[_player] = newBattleId;
        }
        isPlayerAttacking[_player] = true;
    }

    function getAttackers(uint battleId) external view returns (address[] memory) {
        return battles[battleId].attackers;
    }

    function getDefenders(uint battleId) external view returns (address[] memory) {
        return battles[battleId].defenders;
    }

    function leaveBattle(address _player) external {
        require(isPlayerAttacking[_player] == true || isPlayerDefending[_player] == true, 'FLEET: player not a participant in a battle');

        Battle storage playerBattle = battles[participantToBattle[_player]];

        if(isPlayerAttacking[_player]) {
            //loop through battle attackers and find/remove player
            for(uint i=0; i<playerBattle.attackers.length; i++) {
                if(playerBattle.attackers[i] == _player) {
                    playerBattle.attackers[i] = playerBattle.attackers[playerBattle.attackers.length-1];
                    playerBattle.attackers.pop();
                }
            }
            isPlayerAttacking[_player] = false;
        }

        if(isPlayerDefending[_player]) {
            //loop through battle defenders and find/remove player
            for(uint i=0; i<playerBattle.defenders.length; i++) {
                if(playerBattle.defenders[i] == _player) {
                    playerBattle.defenders[i] = playerBattle.defenders[playerBattle.defenders.length-1];
                    playerBattle.defenders.pop();
                }
            }
            isPlayerDefending[_player] = false;
        }

        //if player is only attacker in battle
        if(playerBattle.attackers.length == 0) {
            _endBattle(playerBattle);
        }

    }

    //need to add modifier restricting to Map contract
    function endBattle(address _player) external {
        if(isPlayerTargetted[_player]) {
            _endBattle(battles[targetToBattle[_player]]);
        }
    }

    //after 1) all attackers leave battle or 2) battle is completed or 3) battle target jumps away
    function _endBattle(Battle storage battleToEnd) internal {
        //remove all attacker references
        uint numAttackers = battleToEnd.attackers.length;
        for(uint i=0; i<numAttackers; i++) {
            delete isPlayerAttacking[battleToEnd.attackers[i]];
            delete participantToBattle[battleToEnd.attackers[i]];
        }

        //remove all defender references
        uint numDefenders = battleToEnd.defenders.length;
        for(uint i=0; i<numDefenders; i++) {
            delete isPlayerDefending[battleToEnd.defenders[i]];
            delete participantToBattle[battleToEnd.defenders[i]];
        }

        //remove player targetted references
        delete isPlayerTargetted[battleToEnd.attackTarget];
        delete targetToBattle[battleToEnd.attackTarget];

        //remove battle from battles list
        battles[battleToEnd.id] = battles[battles.length-1];
        battles.pop();
    }

    function _getAttackWindow() internal view returns (uint) {
        return attackWindow / timeModifier;
    }

    function _getDefendWindow() internal view returns (uint) {
        return defendWindow / timeModifier;
    }

    function goBattle(address _target) external {
        require(isPlayerTargetted[_target] == true, 'FLEET: no battle for target');
        Battle memory battle = battles[targetToBattle[_target]];

        (uint totalAttackersAttack, uint totalAttackerFleetSize) = _getTeamInfo(battle.attackers);
        (uint totalDefendersAttack, uint totalDefenderFleetSize) = _getTeamInfo(battle.defenders);

        uint attackerMineralCapacityLost = _getMineralLost(battle.attackers, totalDefendersAttack, totalAttackerFleetSize);
        uint defenderMineralCapacityLost = _getMineralLost(battle.defenders, totalAttackersAttack, totalDefenderFleetSize);

        int netAttackerTaken = int(attackerMineralCapacityLost - defenderMineralCapacityLost);
        if(netAttackerTaken != 0) {
            _settleMineral(battle.attackers, totalAttackerFleetSize, netAttackerTaken);
        }
    }

    function _settleMineral(address[] memory _team, uint _totalTeamFleetSize, int _teamMineralGained) internal {
        for(uint i=0; i<_team.length; i++) {
            Map.mineralGained(_team[i], (_teamMineralGained * int(_getFleetSize(_team[i]))) / int(_totalTeamFleetSize));
        }
    }

    function _getMineralLost(address[] memory _team, uint _totalOtherTeamAttack, uint _totalTeamSize) internal returns(uint) {
        uint numMembers = _team.length;
        uint totalMineralCapacityLost = 0;
        for(uint i=0; i<numMembers; i++) {
            for(uint j=0; j<shipClassesList.length; j++) {
                address member = _team[i];
                ShipClass memory shipClass = shipClasses[shipClassesList[j]];

                uint shipClassFleetSize = fleets[member][shipClassesList[j]] * shipClass.size;
                uint damageTaken = (_totalOtherTeamAttack * shipClassFleetSize) / _totalTeamSize;
                uint shipsLost = damageTaken / shipClass.shield;
                totalMineralCapacityLost += shipsLost * shipClass.mineralCapacity;
                _destroyShips(member, shipClass.handle, shipsLost);
            }
        }
        return totalMineralCapacityLost;
    }

    //get team info for battle
    function _getTeamInfo(address[] memory _team) internal view returns(uint, uint) {
        uint numMembers = _team.length;
        uint totalAttack = 0;
        uint totalFleetSize = 0;
        for(uint i=0; i<numMembers; i++) {
            for(uint j=0; j<shipClassesList.length; j++) {
                totalAttack += fleets[_team[i]][shipClassesList[j]];
                totalFleetSize += _getFleetSize(_team[i]);
            }
        }
        return (totalAttack, totalFleetSize);
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
        address player = msg.sender;
        require(bytes(addressToName[player]).length == 0, 'FLEET: player already has name');
        Treasury.pay(player, startFee / Treasury.getCostMod());
        names[_name] = player;
        addressToName[player] = _name;
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

        coordinateShipyards[_x][_y] = Shipyard(_owner, _x, _y, _feePercent, true);
        emit NewShipyard(_x, _y);
    }

    function getShipyards() external view returns(Shipyard[] memory) {
        uint shipyardCount = 0;
        Shipyard[] memory shipyards;
        uint[] memory planetIds = Map.getPlanetIds();
        for(uint i=0; i<planetIds.length; i++) {
            (uint x, uint y) = Map.getPlanetCoordinates(planetIds[i]);
            if(coordinateShipyards[x][y].exists) {
                shipyards[shipyardCount++] = coordinateShipyards[x][y];
            }
        }
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
        require(playerDryDocks[player][shipyard.coordX][shipyard.coordY].amount == 0, 'FLEET: already in progress or ships waiting to be claimed');
        require((shipClasses[_shipClass].size * _amount) < _getMaxFleetSize(player), 'FLEET: order is too large');

        //total build cost
        uint totalCost = getDockCost(_shipClass, _amount);

        //send fee to shipyard owner
        uint ownerFee = (totalCost * shipyard.feePercent) / 100;
        Token.safeTransferFrom(player, shipyard.owner, ownerFee);

        Treasury.pay(player, totalCost);

        uint completionTime = block.timestamp + getBuildTime(_shipClass, _amount);
        playerDryDocks[player][shipyard.coordX][shipyard.coordY] = DryDock(shipClasses[_shipClass], _amount, completionTime);
    }

    function getDryDock(uint _x, uint _y, address _player) view external returns(DryDock memory){
        return playerDryDocks[_player][_x][_y];
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
        uint fleetSize = 0;
        if(bytes(addressToName[_player]).length > 0) {
            fleetSize += _getBaseFleetSize();
        }
        for(uint i=0; i<shipClassesList.length; i++) {
            uint shipClassAmount = fleets[_player][shipClassesList[i]]; //get number of player's ships in this ship class
            fleetSize += (shipClassAmount * shipClasses[shipClassesList[i]].size);
        }
        return fleetSize;
    }

    function _getBaseFleetSize() internal view returns (uint) {
        return baseFleetSize / Treasury.getCostMod();
    }


    function recall() external {
        address player = msg.sender;
        require(_getFleetSize(player) == _getBaseFleetSize(), "FLEET: fleet cannot have any ships for recall");
        Map.setFleetLocation(player, 0, 0);
    }

    //destroy ships
    function _destroyShips(address _player, string memory _shipClass, uint _amount) internal {
        fleets[_player][_shipClass] -= (Helper.getMin(_amount, fleets[msg.sender][_shipClass]));
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
        require(coordinateShipyards[_x][_y].exists == true, 'Shipyard: no shipyard at this location');

        DryDock storage dryDock = playerDryDocks[msg.sender][_x][_y];
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