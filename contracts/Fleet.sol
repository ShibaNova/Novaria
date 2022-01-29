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

        //load start data
        createShipClass("Viper", 1, 1, 5, 0, 0, 0, 60, 10**18);
        createShipClass("Mole", 2, 0, 10, 10**17, 5 * 10**16, 0, 30, 2 * 10**18);
        addShipyard(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,0,0,7);
        //DELETE BEFORE LAUNCH
/*        _names['Koray'] = 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4;
        _addressToName[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4] = 'Koray';

        _addressToName[0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2] = 'Nate';
        _names['Nate'] = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;

        fleets[0x5B38Da6a701c568545dCfcB03FcB875f56beddC4]['viper'] = 100;
        fleets[0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2]['mole'] = 100;

        _attackFleet(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4, 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
        goBattle(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);*/
    }

    //complete mapping of all names to avoid duplicates
    mapping (string => address) _names;

    struct Player {
        string name;
        uint experience;
        uint[] ships;
        SpaceDock[] spaceDocks;
        bool isInBattle;
        uint battleId;
    }
    Player[] _players;
    mapping (address => bool) playerExists;
    mapping (address => uint) addressToPlayer;

    //ship class data
    struct ShipClass {
        string name;
        uint size;
        uint attackPower;
        uint shield;
        uint mineralCapacity;
        uint miningCapacity;
        uint hangarSize;
        uint buildTime;
        uint cost;
    }
    ShipClass[] _shipClasses;

    //shipyard data
    struct Shipyard {
        address owner;
        uint coordX;
        uint coordY;
        uint feePercent;
    }

    Shipyard[] _shipyards;
    mapping (uint => mapping(uint => bool)) _shipyardExists;
    mapping (uint => mapping(uint => uint)) _coordinatesToShipyard; //shipyard locations

    struct SpaceDock {
        uint shipClassId;
        uint amount; 
        uint completionTime;
        uint coordX;
        uint coordY;
    }

    //battle data
    struct Battle {
        uint id;
        address attackTarget;
        uint battleDeadline;
        address[] attackers;
        uint attackersAttackPower;
        uint attackersFleetSize;
        address[] defenders;
        uint defendersAttackPower;
        uint defendersFleetSize;
    }
    Battle[] _battles;

    //mappings to easily access player battles
    //player can be in up to 2 battles, one where player is target and one where player is attacker or defender
    mapping (address => bool) public isPlayerTargetted;
    mapping (address => uint) public targetToBattle;

    mapping (address => bool) public isPlayerAttacking;
    mapping (address => bool) public isPlayerDefending;
    mapping (address => uint) public participantToBattle;

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
        require(bytes(_name).length < 16, 'FLEET: name too long');
        require(_names[_name] == address(0), 'FLEET: duplicate name');
        address player = msg.sender;
        require(playerExists[player] == false, 'FLEET: player exists');
        Treasury.pay(player, startFee / Treasury.getCostMod());

        _players.push();
        _players[_players.length-1].name = _name;
        _names[_name] = player; //add to name map
        addressToPlayer[player] = _players.length-1;
        playerExists[player] == true;
    }

    function getPlayers() external view returns (Player[] memory) {
        return _players;
    }

    function createShipClass(
        string memory _name,
        uint _size,
        uint _attackPower,
        uint _shield,
        uint _mineralCapacity,
        uint _miningCapacity,
        uint _hangarSize,
        uint _buildTime,
        uint _cost) public onlyOwner {

        _shipClasses.push(ShipClass(_name, _size, _attackPower, _shield, _mineralCapacity, _miningCapacity,_hangarSize, _buildTime, _cost));
    }

    function addShipyard(address _owner, uint _x, uint _y, uint _feePercent)  public onlyOwner {
        require(_shipyardExists[_x][_y] == false, 'FLEET: shipyard exists');
        require(Map.isShipyardLocation(_x, _y) == true, 'FLEET: shipyard unavailable');

        _shipyards.push(Shipyard(_owner, _x, _y, _feePercent));
        _shipyardExists[_x][_y] = true;
        _coordinatesToShipyard[_x][_y] = _shipyards.length-1;
        emit NewShipyard(_x, _y);
    }

    function getShipyards() external view returns (Shipyard[] memory) {
        return _shipyards;
    }

    // Ship building Function
    function buildShips(uint _x, uint _y, uint _shipClassId, uint _amount) external {
        address sender = msg.sender;
        (uint fleetX, uint fleetY) = Map.getFleetLocation(sender);
        require(fleetX == _x && fleetY == _y, 'FLEET: not at shipyard');
        require(_shipyardExists[_x][_y] == true, 'FLEET: no shipyard');
        Shipyard memory shipyard = _shipyards[_coordinatesToShipyard[_x][_y]];

        require((_shipClasses[_shipClassId].size * _amount) < _getMaxFleetSize(sender), 'FLEET: order is too large');

        //total build cost
        uint totalCost = getDockCost(_shipClassId, _amount);

        //send fee to shipyard owner
        uint ownerFee = (totalCost * shipyard.feePercent) / 100;
        Token.safeTransferFrom(sender, shipyard.owner, ownerFee);

        Treasury.pay(sender, totalCost);

        uint completionTime = block.timestamp + getBuildTime(_shipClassId, _amount);
        Player storage player = _players[addressToPlayer[sender]];
        player.spaceDocks.push(SpaceDock(_shipClassId, _amount, completionTime, _x, _y));
    }

    /* move ships to fleet, call must fit the following criteria:
        1) fleet must be at same location as shipyard being requested
        2) amount requested must be less than or equal to amount in dry dock
        3) dry dock build must be completed (completion time must be past block timestamp)
        4) claim size must not put fleet over max fleet size */
    function claimShips(uint spaceDockId, uint _amount) external {
        address sender = msg.sender;
        Player storage player = _players[addressToPlayer[sender]];
        SpaceDock storage dock = player.spaceDocks[spaceDockId];
        (uint fleetX, uint fleetY) = Map.getFleetLocation(sender);
        require(fleetX == dock.coordX && fleetY == dock.coordY, 'FLEET: not at shipyard');

        require(_amount <= dock.amount, 'Dry Dock: not that many');
        require(block.timestamp > dock.completionTime, 'Dry Dock: ships not built, yet');

        ShipClass memory dockClass = _shipClasses[dock.shipClassId];

        require(getFleetSize(sender) + (_amount * dockClass.size) < _getMaxFleetSize(sender), 'Claim size too large');

        player.ships[dock.shipClassId] += _amount; //add ships to fleet
        dock.amount -= _amount; //remove ships from drydock
    }

    //destroy ships
    function _destroyShips(address _player, uint _shipClassId, uint _amount) internal {
        _players[addressToPlayer[_player]].ships[_shipClassId] -= (Helper.getMin(_amount, _players[addressToPlayer[_player]].ships[_shipClassId]));
    }

    //initiate an attack against another player
    function attackFleet(address _player, address _target) external {
        _attackFleet(_player, _target);
    }
    function _attackFleet(address _player, address _target) internal canParticipateInBattle(_player, _target) {
        if(isPlayerTargetted[_target] == true) {
            Battle storage foundBattle = _battles[targetToBattle[_target]];
            require(block.timestamp < (foundBattle.battleDeadline - _getAttackWindow()), 'FLEET: withdraw window is past');
            _addBattleAttacker(foundBattle, _player);
        }
        else { //create battle if there is currently no attack against target
            uint battleDeadline = block.timestamp + _getAttackWindow() + _getDefendWindow();
            uint newBattleId = _battles.length;
            _battles.push(Battle(newBattleId, _target, battleDeadline, new address[](0), 0, 0, new address[](0), 0, 0));
            isPlayerTargetted[_target] = true;
            targetToBattle[_target] = newBattleId;

            _addBattleDefender(_battles[newBattleId], _target);
            _addBattleAttacker(_battles[newBattleId], _player);
        }
    }

    function _addBattleAttacker(Battle storage _battle, address _player) internal {
            _battle.attackers.push(_player);
            isPlayerAttacking[_player] = true;
            participantToBattle[_player] = _battle.id;

            _battle.attackersAttackPower += getAttackPower(_player);
            _battle.attackersFleetSize += getFleetSize(_player);
    }

    function _addBattleDefender(Battle storage _battle, address _player) internal {
            _battle.defenders.push(_player);
            isPlayerDefending[_player] = true;
            participantToBattle[_player] = _battle.id;

            _battle.defendersAttackPower += getAttackPower(_player);
            _battle.defendersFleetSize += getFleetSize(_player);
    }

    function getAttackPower(address _player) public view returns (uint) {
        uint totalAttack = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            totalAttack += _players[addressToPlayer[_player]].ships[i] * _shipClasses[i].attackPower;
        }
        return totalAttack;
    }

    //come to the defense of another player
    function defendFleet(address _player, address _target) external canParticipateInBattle(_player, _target) {
        require(isPlayerTargetted[_target] == true, 'FLEET: cannot defend a player that is not under attack');

        Battle storage foundBattle = _battles[targetToBattle[_target]];
        require(block.timestamp < (foundBattle.battleDeadline - _getAttackWindow()), 'FLEET: withdraw window is past');
        _addBattleDefender(foundBattle, _target);
    }

    //need to add modifier restricting to Map contract
    function endBattle(address _player) external {
        if(isPlayerTargetted[_player]) {
            _endBattle(_battles[targetToBattle[_player]]);
        }
    }

    //after 1) all attackers leave battle or 2) battle is completed or 3) battle target jumps away
    function _endBattle(Battle storage battleToEnd) internal {
        //remove all attacker references
        for(uint i=0; i<battleToEnd.attackers.length; i++) {
            delete participantToBattle[battleToEnd.attackers[i]];
            delete isPlayerAttacking[battleToEnd.attackers[i]];
        }

        //remove all defender references
        for(uint i=0; i<battleToEnd.defenders.length; i++) {
            delete participantToBattle[battleToEnd.defenders[i]];
            delete isPlayerDefending[battleToEnd.defenders[i]];
        }

        //remove player targetted references
        delete isPlayerTargetted[battleToEnd.attackTarget];
        delete targetToBattle[battleToEnd.attackTarget];

        //remove battle from battles list
        _battles[battleToEnd.id] = _battles[_battles.length-1];
        _battles.pop();
    }

    function goBattle(address _target) public {
        require(isPlayerTargetted[_target] == true, 'FLEET: no battle for target');
        Battle storage battle = _battles[targetToBattle[_target]];

        (uint attackerTeamMineralLost, uint[] memory attackersMineralLost) = 
            _getMineralLost(battle.attackers, battle.defendersAttackPower, battle.attackersFleetSize);

        (uint defenderTeamMineralLost, uint[] memory defendersMineralLost) = 
            _getMineralLost(battle.defenders, battle.attackersAttackPower, battle.defendersFleetSize);

        _settleMineral(battle.attackers, battle.attackersAttackPower, defenderTeamMineralLost, attackersMineralLost);
        _settleMineral(battle.defenders, battle.defendersAttackPower, attackerTeamMineralLost, defendersMineralLost);
        _endBattle(battle);
    }

    function _getMineralLost(address[] memory _team, uint _totalOtherTeamAttack, uint _totalTeamSize) internal returns(uint, uint[] memory) {
        uint totalMineralLost = 0;
        uint[] memory memberMineralLost = new uint[](_team.length); //get mineral capacity each player lost
        for(uint i=0; i<_team.length; i++) {
            address member = _team[i];
            uint memberMineralCapacityLost = 0;
            for(uint j=0; j<_shipClasses.length; j++) {
                //number of ships that team member has of this class
                uint numClassShips = _players[addressToPlayer[member]].ships[j];

                //size of members ships of this class    
                uint damageTaken = (_totalOtherTeamAttack * (numClassShips * _shipClasses[j].size)) / _totalTeamSize;

                //actual ships lost compares the most ships lost from the damage taken by the other team with most ships that member has, member cannot lose more ships than he has
                uint actualShipsLost = Helper.getMin(numClassShips, damageTaken / _shipClasses[j].shield);

                //destroy actual ships lost
                _destroyShips(member, j, actualShipsLost);

                //calculate mineral capacity lost by this class of member's ships; mineral capacity lost is based off of actual ships that were lost
                memberMineralCapacityLost += (actualShipsLost * _shipClasses[j].mineralCapacity);
            }
            //member's final lost mineral is the minimum of how much member currently has in fleet and how much mineral capacity was just lost
            memberMineralLost[i] += (Helper.getMin(Map.getFleetMineral(member), memberMineralCapacityLost));
            totalMineralLost += memberMineralLost[i];
        }
        return (totalMineralLost, memberMineralLost);
    }

    function _settleMineral(address[] memory _team, uint _teamAttackPower, uint _totalTeamMineralGained, uint[] memory _teamMineralLost) internal {
        for(uint i=0; i<_team.length; i++) {

            //get player's attack contribution
            uint playerAttack = 0;
            for(uint j=0; j<_shipClasses.length; j++) {
                playerAttack += _players[addressToPlayer[_team[i]]].ships[i] * _shipClasses[i].attackPower;
            }

            //player receives mineral based on attack contribution and how much total was taken
            uint playerMineralGained = 0;
            if(_teamAttackPower > 0) {
                playerMineralGained = (_totalTeamMineralGained * playerAttack) / _teamAttackPower;
            }

            //player mineral gained subtracts how much player lost from how much player gained (can be negative)
            Map.mineralGained(_team[i], int(playerMineralGained - _teamMineralLost[i]));
        }
    }

    function recall() external {
        address player = msg.sender;
        require(getFleetSize(player) == _getBaseFleetSize(), "FLEET: fleet cannot have any ships for recall");
        Map.setFleetLocation(player, 0, 0);
    }

    //can player participate in this battle
    modifier canParticipateInBattle(address _player, address _target) {
        require(_player != _target, 'FLEET: Player/target cannot be the same player (dummy!)');

        //verify players are at same location
        (uint attackX, uint attackY) = Map.getFleetLocation(_player);
        (uint targetX, uint targetY) = Map.getFleetLocation(_target);
        require(attackX == targetX && attackY == targetY, 'FLEET: player and target not at same location');

        require(isPlayerAttacking[_player] == false && isPlayerDefending[_player] == false, 'FLEET: player already in another battle');

        require(getFleetSize(_target) > _getBaseFleetSize(), 'FLEET: cannot attack a player that has no ships');
        require(getFleetSize(_player) > _getBaseFleetSize(), 'FLEET: cannot attack/defend without ships');
        _;
    }

    function getFleets(address _player) external view returns (uint[] memory) {
        return _players[addressToPlayer[_player]].ships;
    }

    function getDockCost(uint shipClassId, uint _amount) public view returns(uint) {
        return (_amount * _shipClasses[shipClassId].cost) / Treasury.getCostMod();
    }

    function getBuildTime(uint _shipClassId, uint _amount) public view returns(uint) {
        return (_amount * _shipClasses[_shipClassId].buildTime) / timeModifier;
    }

    function getSpaceDocks(address _player, uint _x, uint _y) public view returns (SpaceDock[] memory) {
        SpaceDock[] memory foundDocks;
        uint foundDockCount;
        SpaceDock[] memory playerDocks = _players[addressToPlayer[_player]].spaceDocks;
        for(uint i=0; i<playerDocks.length; i++) {
            if(playerDocks[i].coordX == _x  && playerDocks[i].coordY == _y) {
                foundDocks[foundDockCount++];
            }
        }
        return foundDocks;
    }

    function getPlayerSpaceDocks(address _player) external view returns (SpaceDock[] memory) {
        return _players[addressToPlayer[_player]].spaceDocks;
    }
 
    function getAttackers(uint battleId) external view returns (address[] memory) {
        return _battles[battleId].attackers;
    }

    function getDefenders(uint battleId) external view returns (address[] memory) {
        return _battles[battleId].defenders;
    }

    function _getAttackWindow() internal view returns (uint) {
        return attackWindow / timeModifier;
    }

    function _getDefendWindow() internal view returns (uint) {
        return defendWindow / timeModifier;
    }

    function getMaxFleetSize(address _player) external view returns (uint) {
        return _getMaxFleetSize(_player);
    }

    function _getMaxFleetSize(address _player) internal view returns (uint) {
        uint maxFleetSize = baseMaxFleetSize; 
        for(uint i=0; i<_shipClasses.length; i++) {
            uint shipClassAmount = _players[addressToPlayer[_player]].ships[i]; //get number of player's ships in this ship class
            maxFleetSize += (shipClassAmount * _shipClasses[i].hangarSize);
        }
        return maxFleetSize / Treasury.getCostMod();
    }

    function getFleetSize(address _player) public view returns(uint) {
        uint fleetSize = 0;
        if(playerExists[_player]) {
            fleetSize += _getBaseFleetSize();
        }
        for(uint i=0; i<_shipClasses.length; i++) {
            uint shipClassAmount = _players[addressToPlayer[_player]].ships[i]; //get number of player's ships in this ship class
            fleetSize += (shipClassAmount * _shipClasses[i].size);
        }
        return fleetSize;
    }

    function _getBaseFleetSize() internal view returns (uint) {
        return baseFleetSize / Treasury.getCostMod();
    }

    //get the max mineral capacity of player's fleet
    function getMaxMineralCapacity(address _player) public view returns (uint){
        uint mineralCapacity = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            mineralCapacity += (_players[addressToPlayer[_player]].ships[i] * _shipClasses[i].mineralCapacity);
        }
        return mineralCapacity / Treasury.getCostMod();
    }

    //get the max mining capacity of player's fleet (how much mineral can a player mine each mining attempt)
    function getMiningCapacity(address _player) public view returns (uint){
        uint miningCapacity = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            miningCapacity += (_players[addressToPlayer[_player]].ships[i] * _shipClasses[i].miningCapacity);
        }
        return miningCapacity / Treasury.getCostMod();
    }

    function setTimeModifier(uint _timeModifier) external onlyOwner{
        timeModifier = _timeModifier;
    }

    function setTreasury (address _treasury) external onlyOwner {
        Map = IMap(_treasury);
    }

    function editCost(uint shipClassId, uint _newCost) public onlyOwner {
        _shipClasses[shipClassId].cost = _newCost;
    }

    function getAddressByName(string memory _name) external view returns (address) {
        return _names[_name];
    }

    function getNameByAddress(address _address) external view returns (string memory) {
        return _players[addressToPlayer[_address]].name;
    }
}