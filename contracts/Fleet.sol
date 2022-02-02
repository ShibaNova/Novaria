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
    //battleWindow - 30 min.
    //building ships

contract Fleet is Ownable {
    using SafeBEP20 for ShibaBEP20;

    constructor (
       // IMap _map, 
       // ITreasury _treasury, 
       // ShibaBEP20 _Token
        ) {
        Token = ShibaBEP20(0x9249DAcc91cddB8C67E9a89e02E071085dE613cE);
        Treasury = ITreasury(0x42bCB57E0617728A7E4e13D8cD6458879cd576D1);
        Map = IMap(0x59d65CDcd319315471Dd24a0398cbc539c0E1b25);
        _baseMaxFleetSize = 1000;
        _baseFleetSize = 100;
        _timeModifier = 50;
        _battleWindow = 3600; //60 minutes
        _battleSizeRestriction = 4;
        _startFee = 10**18;

        //load start data
        createShipClass("Viper", 1, 1, 5, 0, 0, 0, 60, 10**18);
        createShipClass("Mole", 2, 0, 10, 5 * 10**17, 10**17, 0, 30, 2 * 10**18);
        addShipyard(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,0,0,7);
        addShipyard(0x729F3cA74A55F2aB7B584340DDefC29813fb21dF,5,5,5);

        //DELETE BEFORE LAUNCH
        // _createPlayer('_Koray', 0x078BB52f3FD53Cde7Ab15FE831Da9B55E3c702Fa);
        // _players[0].ships[0] = 100;
        // _players[0].ships[1] = 19;

        // _createPlayer('_Nate', 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
        // _players[1].ships[0] = 33;

        //enterBattle(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4, BattleStatus.ATTACK);
//        goBattle(0);
    }

    enum BattleStatus{ PEACE, ATTACK, DEFEND }
    //complete mapping of all names to avoid duplicates
    mapping (string => address) _names;

    struct Player {
        string name;
        uint experience;
        uint16[16] ships;
        SpaceDock[] spaceDocks;
        BattleStatus battleStatus;
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
        string name;
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
        uint battleDeadline;
        Team attackTeam;
        Team defendTeam;
    }
    Battle[] _battles;

    struct Team {
        address[] members;
        uint attackPower;
        uint fleetSize;
        uint mineral;
    }

    IMap public Map;
    ITreasury public Treasury;
    ShibaBEP20 public Token; // nova token address
    uint _baseMaxFleetSize;
    uint _baseFleetSize; //size of capital ship
    uint _timeModifier;
    uint _battleWindow;
    uint _battleSizeRestriction;
    uint _startFee;

    event NewShipyard(uint _x, uint _y);

    function _createPlayer(string memory _name, address _player) internal {
        _players.push();
        _players[_players.length-1].name = _name;
        _names[_name] = _player; //add to name map
        addressToPlayer[_player] = _players.length-1;
        playerExists[_player] = true;
    }

    function insertCoinHere(string memory _name) external {
        require(bytes(_name).length < 16, 'FLEET: name too long');
        require(_names[_name] == address(0), 'FLEET: duplicate name');
        require(playerExists[msg.sender] == false, 'FLEET: player exists');
        Treasury.pay(msg.sender, _startFee / Treasury.getCostMod());
        _createPlayer(_name, msg.sender);
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

        string memory name = Map.getPlaceName(_x, _y);

        _shipyards.push(Shipyard(name, _owner, _x, _y, _feePercent));
        _shipyardExists[_x][_y] = true;
        _coordinatesToShipyard[_x][_y] = _shipyards.length-1;
        emit NewShipyard(_x, _y);
    }

    // Ship building Function
    function buildShips(uint _x, uint _y, uint _shipClassId, uint _amount) external {
        address sender = msg.sender;
        Shipyard memory shipyard = _shipyards[_coordinatesToShipyard[_x][_y]];

        require(getSpaceDocks(sender, _x, _y).length == 0, 'FLEET: no dock available');

        require((_shipClasses[_shipClassId].size * _amount) < _getMaxFleetSize(sender), 'FLEET: order too large');

        //total build cost
        uint totalCost = getDockCost(_shipClassId, _amount);

        //send fee to shipyard owner
        uint ownerFee = (totalCost * shipyard.feePercent) / 100;
        Token.safeTransferFrom(sender, shipyard.owner, ownerFee);

        uint scrapFee = 25;
        Treasury.pay(sender, (totalCost * (100-scrapFee)) / 100);
        Token.safeTransferFrom(sender, address(Map), (totalCost * scrapFee) / 100); //send scrap to Map contract

        uint completionTime = block.timestamp + getBuildTime(_shipClassId, _amount);
        Player storage player = _players[addressToPlayer[sender]];
        player.spaceDocks.push(SpaceDock(_shipClassId, _amount, completionTime, _x, _y));
    }

    /* move ships to fleet, call must fit the following criteria:
        1) fleet must be at same location as shipyard being requested
        2) amount requested must be less than or equal to amount in dry dock
        3) dry dock build must be completed (completion time must be past block timestamp)
        4) claim size must not put fleet over max fleet size */
    function claimShips(uint spaceDockId, uint16 _amount) external {
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

        dock = player.spaceDocks[player.spaceDocks.length-1];
        player.spaceDocks.pop();
    }

    //destroy ships
    function _destroyShips(address _player, uint16 _shipClassId, uint16 _amount) internal {
        _players[addressToPlayer[_player]].ships[_shipClassId] -= uint16(Helper.getMin(_amount, _players[addressToPlayer[_player]].ships[_shipClassId]));
    }

    //can player participate in this battle
    modifier canJoinBattle(address _player, address _target) {
        require(playerExists[_player] == true, 'FLEET: no player');
        require(playerExists[_target] == true, 'FLEET: no target');
        require(_player != _target, 'FLEET: Player/target not same');
        require(_players[addressToPlayer[_player]].battleStatus == BattleStatus.PEACE, 'FLEET: in battle');

        //verify players are at same location
        (uint attackX, uint attackY) = Map.getFleetLocation(_player);
        (uint targetX, uint targetY) = Map.getFleetLocation(_target);
        require(attackX == targetX && attackY == targetY, 'FLEET: dif. location');

        require(getFleetSize(_player) * _battleSizeRestriction >= getFleetSize(_target), 'FLEET: player too small');
        require(getFleetSize(_target) * _battleSizeRestriction >= getFleetSize(_player), 'FLEET: target too small');
        _;
    }

    function _joinTeam(address _hero, uint _battleId, Team storage _team, BattleStatus _mission) internal {
            _players[addressToPlayer[_hero]].battleId = _battleId;
            _players[addressToPlayer[_hero]].battleStatus = _mission;
            _team.members.push(_hero);
            _team.attackPower += getAttackPower(_hero);
            _team.fleetSize += getFleetSize(_hero);
            _team.fleetSize += Map.getFleetMineral(_hero);
    }

    function enterBattle(address _target, BattleStatus mission) public canJoinBattle(msg.sender, _target) {
        Player storage targetPlayer = _players[addressToPlayer[_target]];
        require(mission != BattleStatus.PEACE, 'FLEET: no peace');
        require((mission == BattleStatus.DEFEND? targetPlayer.battleStatus != BattleStatus.PEACE : true), 'FLEET: player not under attack');

        uint targetBattleId = targetPlayer.battleId;
        if(mission == BattleStatus.ATTACK) {
            if(targetPlayer.battleStatus == BattleStatus.PEACE) { //if new battle
                _battles.push(Battle(block.timestamp + _getBattleWindow(), Team(new address[](0), 0, 0, 0), Team(new address[](0), 0, 0, 0)));
                _joinTeam(_target, _battles.length-1, _battles[_battles.length-1].defendTeam, BattleStatus.DEFEND);
            }
            _joinTeam(_target, targetBattleId, _battles[targetBattleId].attackTeam, BattleStatus.ATTACK);
        }
        else if(mission == BattleStatus.DEFEND) {
            _joinTeam(_target, targetBattleId, _battles[targetBattleId].defendTeam, BattleStatus.DEFEND);
        }
    }

    //after battle is complete
    function _endBattle(uint _battleId) internal {
        //put attackers and denders into peace status
        Battle memory battleToEnd = _battles[_battleId];
        for(uint i=0; i<battleToEnd.attackTeam.members.length; i++) {
            _players[addressToPlayer[battleToEnd.attackTeam.members[i]]].battleStatus = BattleStatus.PEACE;
        }
        for(uint i=0; i<battleToEnd.defendTeam.members.length; i++) {
            _players[addressToPlayer[battleToEnd.defendTeam.members[i]]].battleStatus = BattleStatus.PEACE;
        }

        //remove battle from battles list
        _battles[_battleId] = _battles[_battles.length-1];
        _battles.pop();
    }

    function goBattle(uint battleId) public {
        Battle storage battle = _battles[battleId];
        require(block.timestamp > battle.battleDeadline, 'FLEET: battle preppiing');

        (uint attackerTeamMineralLost, uint[] memory attackersMineralLost) = 
            _getMineralLost(battle.attackTeam.members, battle.defendTeam.attackPower, battle.attackTeam.fleetSize);

        (uint defenderTeamMineralLost, uint[] memory defendersMineralLost) = 
            _getMineralLost(battle.defendTeam.members, battle.attackTeam.attackPower, battle.defendTeam.fleetSize);

        _endBattle(battleId);
    }

    function _getMineralLost(address[] memory _team, uint _totalOtherTeamAttack, uint _totalTeamSize) internal returns(uint, uint[] memory) {
        uint totalValueLost = 0;
        uint totalMineralLost = 0;
        uint[] memory memberMineralLost = new uint[](_team.length); //get mineral capacity each player lost
        for(uint i=0; i<_team.length; i++) {
            address member = _team[i];
            uint memberMineralCapacityLost = 0;
            for(uint16 j=0; j<_shipClasses.length; j++) {
                //number of ships that team member has of this class
                uint numClassShips = _players[addressToPlayer[member]].ships[j];

                //size of members ships of this class    
                uint damageTaken = (_totalOtherTeamAttack * (numClassShips * _shipClasses[j].size)) / _totalTeamSize;

                //actual ships lost compares the most ships lost from the damage taken by the other team with most ships that member has, member cannot lose more ships than he has
                uint actualShipsLost = Helper.getMin(numClassShips, damageTaken / _shipClasses[j].shield);

                totalValueLost = actualShipsLost  * _shipClasses[j].cost;

                //calculate mineral capacity lost by this class of member's ships; mineral capacity lost is based off of actual ships that were lost
                memberMineralCapacityLost += (actualShipsLost * _shipClasses[j].mineralCapacity);

                //destroy actual ships lost
                _destroyShips(member, j, uint16(actualShipsLost));
            }
            //member's final lost mineral is the percentage of filled mineral capacity
            memberMineralLost[i] = (memberMineralCapacityLost * Map.getFleetMineral(member)) / getMineralCapacity(member);
            totalMineralLost += memberMineralLost[i];
        }
        return (totalMineralLost, memberMineralLost);
    }

    function recall() external {
        address player = msg.sender;
        require(getFleetSize(player) == _getBaseFleetSize(), "FLEET: fleet cannot have any ships for recall");
        Map.setFleetLocation(player, 0, 0);
    }

    function getFleets(address _player) external view returns (uint16[16] memory) {
        return _players[addressToPlayer[_player]].ships;
    }

    function getBattle(uint battleId) external view returns (Battle memory) {
        return _battles[battleId];
    }
    
    function getBattles() external view returns (Battle[] memory) {
        return _battles;
    }

    function getShipyards() external view returns (Shipyard[] memory) {
        return _shipyards;
    }

    function getShipClasses() external view returns (ShipClass[] memory) {
        return _shipClasses;
    }

    function getDockCost(uint shipClassId, uint _amount) public view returns(uint) {
        return (_amount * _shipClasses[shipClassId].cost) / Treasury.getCostMod();
    }

    function getBuildTime(uint _shipClassId, uint _amount) public view returns(uint) {
        return (_amount * _shipClasses[_shipClassId].buildTime) / _timeModifier;
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
        return _battles[battleId].attackTeam.members;
    }

    function getDefenders(uint battleId) external view returns (address[] memory) {
        return _battles[battleId].defendTeam.members;
    }

    function _getBattleWindow() internal view returns (uint) {
        return _battleWindow / _timeModifier;
    }
    function getAttackPower(address _player) public view returns (uint) {
        uint totalAttack = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            totalAttack += _players[addressToPlayer[_player]].ships[i] * _shipClasses[i].attackPower;
        }
        return totalAttack;
    }

    function getMaxFleetSize(address _player) external view returns (uint) {
        return _getMaxFleetSize(_player);
    }

    function _getMaxFleetSize(address _player) internal view returns (uint) {
        uint maxFleetSize = _baseMaxFleetSize; 
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
        return _baseFleetSize / Treasury.getCostMod();
    }

    //get the max mineral capacity of player's fleet
    function getMaxMineralCapacity(address _player) public view returns (uint){
        uint mineralCapacity = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            mineralCapacity += (_players[addressToPlayer[_player]].ships[i] * _shipClasses[i].mineralCapacity);
        }
        return mineralCapacity / Treasury.getCostMod();
    }

    // how much mineral can a player currently hold
    function getMineralCapacity(address _player) public view returns (uint){
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

    function getPlayerExists(address _player) external view returns (bool) {
        return playerExists[_player];
    }
}