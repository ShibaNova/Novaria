// SPDX-License-Identifier: MIT
 
pragma solidity 0.8.7;

import './libs/Editor.sol';
import "./interfaces/ITreasury.sol";
import './libs/Helper.sol';
import "./interfaces/IMap.sol";
import "./libs/ShibaBEP20.sol";
import "./libs/SafeBEP20.sol";
 
//miningCooldown - 30 min.
//jumpDriveCooldown - 30 min + distance
//battleWindow 
//building ships

contract Fleet is Editor {
    using SafeBEP20 for ShibaBEP20;

    constructor (
       // IMap _map, 
       // ITreasury _treasury, 
       // ShibaBEP20 _Token
        ) {
        Token = ShibaBEP20(0x9249DAcc91cddB8C67E9a89e02E071085dE613cE);
        Treasury = ITreasury(0x0c5a18Eb2748946d41f1EBe629fF2ecc378aFE91);
        Map = IMap(0x37a8Df0ddfAEBc79b6B89f5a73944AbF4FaAC050);
        //Token = ShibaBEP20(0xd9145CCE52D386f254917e481eB44e9943F39138);
        //Treasury = ITreasury(0xd8b934580fcE35a11B58C6D73aDeE468a2833fa8);
        //Map = IMap(0xf8e81D47203A594245E36C48e151709F0C19fBe8);
        _baseMaxFleetSize = 5000;
        _battleSizeRestriction = 4;
        _startFee = 10**20;
        _scrapPercentage = 25;
        _battleCounter = 0;
        _maxShipyardFeePercent = 50;

        //load start data
        createShipClass("Viper", 1, 1, 3, 0, 0, 0, 10**18, 0);
        createShipClass("Mole", 2, 0, 5, 10**17, 10**16, 0, 2 * 10**18, 0);
        //addShipyard(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,0,0,7);
        //addShipyard(0x729F3cA74A55F2aB7B584340DDefC29813fb21dF,5,5,5);
       // loadPlayers();
    }

    enum BattleStatus{ PEACE, ATTACK, DEFEND }
    //complete mapping of all names to avoid duplicates
    mapping (string => address) _names;

    struct Player {
        string name;
        uint experience;
        uint[32] ships;
        uint battleId;
        uint mineral;
        BattleStatus battleStatus;
        SpaceDock[] spaceDocks;
    }
    Player[] _players;
    mapping (address => bool) _playerExists;
    mapping (address => uint) _addressToPlayer;

    //ship class data
    struct ShipClass {
        string name;
        uint size;
        uint attackPower;
        uint shield;
        uint mineralCapacity;
        uint miningCapacity;
        uint hangarSize;
        uint cost;
        uint experienceRequired;
    }
    ShipClass[] _shipClasses;

    //shipyard data
    struct Shipyard {
        string name;
        address owner;
        uint coordX;
        uint coordY;
        uint8 feePercent;
        uint lastTakeoverTime;
        uint takeoverDeadline;
        address takeoverAddress;
        BattleStatus status;
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
        uint battleCount;
        uint battleDeadline;
        uint coordX;
        uint coordY;
        Team attackTeam;
        Team defendTeam;
    }
    Battle[] _battles;
    mapping(uint => uint) _battleCountToId;

    struct Team {
        address[] members;
        uint attackPower;
        uint fleetSize;
    }

    IMap public Map;
    ITreasury public Treasury;
    ShibaBEP20 public Token; // nova token address
    uint _baseMaxFleetSize;
    uint _battleSizeRestriction;
    uint _startFee;
    uint _scrapPercentage;
    uint _battleCounter;
    uint _maxShipyardFeePercent;

    event NewShipyard(uint _x, uint _y);
    event NewMap(address _address);

    //BEGIN*****************FUNCTIONS FOR TESTING, CAN BE DELETED LATER
/*    function loadPlayers() public {
        _createPlayer('Nate', 0x729F3cA74A55F2aB7B584340DDefC29813fb21dF);
        _players[0].ships[0] = 100;
        _players[0].ships[1] = 19;

        _createPlayer('Sam', 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
        _players[1].ships[0] = 43;
        _players[1].ships[1] = 4;
    }*/

/*    function battleTest() public {
        enterBattle(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, BattleStatus.ATTACK);
    }*/
    //END*****************FUNCTIONS FOR TESTING, CAN BE DELETED LATER

    function _createPlayer(string memory _name, address _player) internal {
        require(bytes(_name).length < 16, 'FLEET: name too long');
        require(_names[_name] == address(0), 'FLEET: duplicate name');
        require(_playerExists[_player] == false, 'FLEET: player exists');
        _players.push();
        _players[_players.length-1].name = _name;
        _names[_name] = _player; //add to name map
        _addressToPlayer[_player] = _players.length-1;
        _playerExists[_player] = true;
        Map.setFleetLocation(msg.sender, 0, 0, 0, 0);
    }

    function insertCoinHere(string memory _name) external {
        Treasury.pay(msg.sender, _startFee / Treasury.getCostMod());
        _createPlayer(_name, msg.sender);
    }

    function createShipClass(
        string memory _name,
        uint _size,
        uint _attackPower,
        uint _shield,
        uint _mineralCapacity,
        uint _miningCapacity,
        uint _hangarSize,
        uint _cost,
        uint _experienceRequired) public onlyOwner {

        _shipClasses.push(ShipClass(_name, _size, _attackPower, _shield, _mineralCapacity, _miningCapacity,_hangarSize, _cost, _experienceRequired));
    }

    function addShipyard(address _owner, uint _x, uint _y, uint8 _feePercent) public onlyEditor {
        require(Map.isShipyardLocation(_x, _y) == true, 'FLEET: shipyard unavailable');
        require(_shipyardExists[_x][_y] == false, 'FLEET: shipyard exists');

        string memory name = Map.getPlaceName(_x, _y);

        _shipyards.push(Shipyard(name, _owner, _x, _y, _feePercent, block.timestamp, 0, _owner, BattleStatus.PEACE));
        _shipyardExists[_x][_y] = true;
        _coordinatesToShipyard[_x][_y] = _shipyards.length-1;
        emit NewShipyard(_x, _y);
    }

    function initiateShipyardTakeover(uint _x, uint _y) external doesShipyardExist(_x, _y) {
        (uint fleetX, uint fleetY) = Map.getFleetLocation(msg.sender);
        require(fleetX == _x && fleetY == _y, 'FLEET: not at shipyard');

        Shipyard storage shipyard = _shipyards[_coordinatesToShipyard[_x][_y]];
        require(shipyard.lastTakeoverTime < block.timestamp - ((60 * 60 * 24 * 7) / Map.getTimeModifier()), 'FLEET: shipyard protected');

        //takeover begins if either shipyard is at peace or new takeover address has a larger fleet than current takeover address
        uint fleetSize = getFleetSize(msg.sender);
        if(fleetSize >= 1000 && (shipyard.status == BattleStatus.PEACE || fleetSize > getFleetSize(shipyard.takeoverAddress))) {
            shipyard.status = BattleStatus.ATTACK;
            shipyard.takeoverAddress = msg.sender;
            shipyard.takeoverDeadline = block.timestamp + ((60 * 60 * 24) / Map.getTimeModifier());
        }

        uint takeOverFee = 25 / Treasury.getCostMod();
        Treasury.pay(msg.sender, takeOverFee);
        addExperience(msg.sender, takeOverFee);
    }

    //complete shipyard takeover
    function completeShipyardTakeover(uint _x, uint _y) external doesShipyardExist(_x, _y) {
        Shipyard storage shipyard = _shipyards[_coordinatesToShipyard[_x][_y]];
        require(block.timestamp > shipyard.takeoverDeadline, 'FLEET: takeover deadline');

        if(getFleetSize(shipyard.takeoverAddress) >= 200) {
            shipyard.owner = msg.sender;
            shipyard.status = BattleStatus.PEACE;
            shipyard.lastTakeoverTime = block.timestamp;
        }
    }

    function setShipyardName(uint _x, uint _y, string memory _name) external doesShipyardExist(_x, _y) {
        require(bytes(_name).length < 16, 'FLEET: shipyard name too long');
        require(_shipyards[_coordinatesToShipyard[_x][_y]].owner == msg.sender);
        _shipyards[_coordinatesToShipyard[_x][_y]].name = _name;
    }

    function setShipyardFeePercent(uint _x, uint _y, uint8 _feePercent) external doesShipyardExist(_x, _y) {
        require(_feePercent <= _maxShipyardFeePercent, 'FLEET: fee percent too high');
        require(_shipyards[_coordinatesToShipyard[_x][_y]].owner == msg.sender);
        _shipyards[_coordinatesToShipyard[_x][_y]].feePercent = _feePercent;
    }

    // Ship building function
    function buildShips(uint _x, uint _y, uint _shipClassId, uint _amount, uint _cost) external {
        address sender = msg.sender;
        require(_getSpaceDocks(sender, _x, _y).length == 0, 'FLEET: no dock available');
        require((_shipClasses[_shipClassId].size * _amount) < _getMaxFleetSize(sender), 'FLEET: order too large');

        //total build cost
        uint totalCost = getDockCost(_shipClassId, _amount);

        //send fee to shipyard owner
        Shipyard memory shipyard = _shipyards[_coordinatesToShipyard[_x][_y]];
        uint ownerFee = (totalCost * shipyard.feePercent) / 100;

        require(_cost == totalCost + ownerFee, 'FLEET: cost mismatch');
        Token.safeTransferFrom(sender, shipyard.owner, ownerFee);

        Treasury.pay(sender, (totalCost * (100-_scrapPercentage)) / 100);
        uint scrap = (totalCost * _scrapPercentage) / 100;
        Token.safeTransferFrom(sender, address(Map), scrap); //send scrap to Map contract
        Map.increasePreviousBalance(scrap);

        uint completionTime = block.timestamp + getBuildTime(_shipClassId, _amount);
        Player storage player = _players[_addressToPlayer[sender]];
        player.spaceDocks.push(SpaceDock(_shipClassId, _amount, completionTime, _x, _y));
        addExperience(sender, totalCost + ownerFee);
    }

    /* move ships to fleet, call must fit the following criteria:
        1) fleet must be at same location as shipyard being requested
        2) amount requested must be less than or equal to amount in dry dock
        3) dry dock build must be completed (completion time must be past block timestamp)
        4) claim size must not put fleet over max fleet size */
    function claimShips(uint spaceDockId, uint _amount) isPlayer(msg.sender) external {
        address sender = msg.sender;
        Player storage player = _players[_addressToPlayer[sender]];
        SpaceDock storage dock = player.spaceDocks[spaceDockId];
        (uint fleetX, uint fleetY) = Map.getFleetLocation(sender);
        require(fleetX == dock.coordX && fleetY == dock.coordY, 'FLEET: not at shipyard');
        require(isInBattle(sender) == false, "MAPS: in battle or takeover");

        require(_amount <= dock.amount, 'Dry Dock: not that many');
        require(block.timestamp > dock.completionTime, 'Dry Dock: ships not built, yet');

        ShipClass memory dockClass = _shipClasses[dock.shipClassId];

        require(getFleetSize(sender) + (_amount * dockClass.size) < _getMaxFleetSize(sender), 'Claim size too large');

        player.ships[dock.shipClassId] += _amount; //add ships to fleet
        dock.amount -= _amount; //remove ships from drydock

        if(dock.amount <= 0) {
            player.spaceDocks[spaceDockId] = player.spaceDocks[player.spaceDocks.length-1];
            player.spaceDocks.pop();
        }
    }

    //destroy ships
    function _destroyShips(address _player, uint _shipClassId, uint _amount) internal {
        _players[_addressToPlayer[_player]].ships[_shipClassId] -= uint(Helper.getMin(_amount, _players[_addressToPlayer[_player]].ships[_shipClassId]));
    }

    modifier doesShipyardExist(uint _x, uint _y) {
        require(_shipyardExists[_x][_y] == true, 'FLEET: no shipyard');
        _;
    }

    //can player participate in this battle
    modifier canJoinBattle(address _player, address _target) {
        require(_playerExists[_player] == true, 'FLEET: no player');
        require(_playerExists[_target] == true, 'FLEET: no target');
        require(_player != _target, 'FLEET: Player/target not same');

        //verify players are at same location
        (uint attackX, uint attackY) = Map.getFleetLocation(_player);
        (uint targetX, uint targetY) = Map.getFleetLocation(_target);
        require(attackX == targetX && attackY == targetY, 'FLEET: dif. location');
        require(Map.isRefineryLocation(targetX, targetY) != true, 'FLEET: refinery is DMZ');

        require(getFleetSize(_player) * _battleSizeRestriction >= getFleetSize(_target), 'FLEET: player too small');
        require(getFleetSize(_target) * _battleSizeRestriction >= getFleetSize(_player), 'FLEET: target too small');
        require(_players[_addressToPlayer[_player]].battleStatus == BattleStatus.PEACE, 'FLEET: in battle');
        _;
    }

    function _joinTeam(address _hero, uint _battleId, Team storage _team, BattleStatus _mission) internal {
            _players[_addressToPlayer[_hero]].battleId = _battleId;
            _players[_addressToPlayer[_hero]].battleStatus = _mission;
            _team.members.push(_hero);
            _team.attackPower += getAttackPower(_hero);
            _team.fleetSize += getFleetSize(_hero);
    }

    //battleWindow is 1 hour
    function enterBattle(address _target, BattleStatus mission) public canJoinBattle(msg.sender, _target) {
        (uint targetX, uint targetY) = Map.getFleetLocation(_target);
        Player storage targetPlayer = _players[_addressToPlayer[_target]];
        require(mission != BattleStatus.PEACE, 'FLEET: no peace');
        require((mission == BattleStatus.DEFEND? targetPlayer.battleStatus != BattleStatus.PEACE : true), 'FLEET: defend,no attack');

        uint targetBattleId = targetPlayer.battleId;
        if(mission == BattleStatus.ATTACK) {
            if(targetPlayer.battleStatus == BattleStatus.PEACE) { //if new battle
                Team memory attackTeam; Team memory defendTeam;
                _battles.push(Battle(_battleCounter++, block.timestamp + (3600 / Map.getTimeModifier()), targetX, targetY, attackTeam, defendTeam));
                _battleCountToId[_battleCounter] = _battles.length-1;
                _joinTeam(_target, _battles.length-1, _battles[_battles.length-1].defendTeam, BattleStatus.DEFEND);
            }
            _joinTeam(msg.sender, targetBattleId, _battles[targetBattleId].attackTeam, BattleStatus.ATTACK);
        }
        else if(mission == BattleStatus.DEFEND) {
            _joinTeam(_target, targetBattleId, _battles[targetBattleId].defendTeam, BattleStatus.DEFEND);
        }
    }

    //calc battle, only works for two teams
    function goBattle(uint battleId) public {
        Battle memory battle = _battles[battleId];
        require(block.timestamp > battle.battleDeadline, 'FLEET: battle prepping');

        Team[2] memory teams = [battle.attackTeam, battle.defendTeam];
        uint totalMineralLost;
        uint totalScrap;
        for(uint i=0; i<teams.length-1; i++) {
            uint otherTeamAttackPower = (i==0? teams[i+1].attackPower: teams[i].attackPower);//if 1st team, get 2nd team attack power, else get 1st
            for(uint j=0; j<teams[i].members.length; j++) {
                address member = teams[i].members[j];
                uint memberMineralCapacityLost = 0;
                for(uint k=0; k<_shipClasses.length; k++) {
                    uint numClassShips = _players[_addressToPlayer[member]].ships[k]; //number of ships that team member has of this class

                    //calculate opposing team's damage to this member
                    uint damageTaken = (otherTeamAttackPower * numClassShips * _shipClasses[k].size) / teams[i].fleetSize;

                    //actual ships lost compares the most ships lost from the damage taken by the other team with most ships that member has, member cannot lose more ships than he has
                    uint actualShipsLost = Helper.getMin(numClassShips, damageTaken / _shipClasses[k].shield);

                    //token value of ships lost
                    totalScrap += (actualShipsLost  * _shipClasses[k].cost * _scrapPercentage) / 100;

                    //calculate mineral capacity lost by this class of member's ships
                    memberMineralCapacityLost += (actualShipsLost * _shipClasses[k].mineralCapacity);

                    //destroy ships lost
                    _destroyShips(member, k, uint(actualShipsLost));
                }
                //member's final lost mineral is the percentage of filled mineral capacity
                if(memberMineralCapacityLost > 0) {
                    totalMineralLost += (memberMineralCapacityLost * _players[_addressToPlayer[member]].mineral) / getMineralCapacity(member);
                }
            }
        }

        Map.addSalvageToPlace(battle.coordX, battle.coordY, totalMineralLost + totalScrap);

        _endBattle(battleId);
    }

    //after battle is complete
    function _endBattle(uint _battleId) internal {
        //put attackers and denders into peace status
        Battle memory battleToEnd = _battles[_battleId];
        for(uint i=0; i<battleToEnd.attackTeam.members.length; i++) {
            _players[_addressToPlayer[battleToEnd.attackTeam.members[i]]].battleStatus = BattleStatus.PEACE;
        }
        for(uint i=0; i<battleToEnd.defendTeam.members.length; i++) {
            _players[_addressToPlayer[battleToEnd.defendTeam.members[i]]].battleStatus = BattleStatus.PEACE;
        }

        //remove battle from battles list
        _battles[_battleId] = _battles[_battles.length-1];
        _battles.pop();
    }

    //add experience to player based on in game purchases
    function addExperience(address _player, uint _paid) public onlyEditor isPlayer(_player) {
        //each nova paid in game, gets player 1/10 experience point
        _players[_addressToPlayer[_player]].experience += (_paid / 10**19);
    }

    //get players experience
    function getExperience(address _player) external view isPlayer(_player) returns (uint) {
        return _players[_addressToPlayer[_player]].experience;
    }

    modifier isPlayer(address _player) {
        require(_playerExists[_player] == true, 'FLEET: no player');
        _;
    }

    //if player battle status is NOT PEACE or player is taking over shipyard, player is in a battle
    function isInBattle(address _player) public view isPlayer(_player) returns(bool) {
        (uint fleetX, uint fleetY) = Map.getFleetLocation(_player);
        if(_players[_addressToPlayer[_player]].battleStatus != BattleStatus.PEACE || _shipyards[_coordinatesToShipyard[fleetX][fleetY]].takeoverAddress == _player) {
            return true;
        }
        else {
            return false;
        }
    }

    function getShips(address _player) external view isPlayer(_player) returns (uint[32] memory) {
        return _players[_addressToPlayer[_player]].ships;
    }

    function getBattleByCount(uint _battleCount) external view returns (Battle memory) {
        return _battles[_battleCountToId[_battleCount]];
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
        //5 minutes per size
        return (_amount * _shipClasses[_shipClassId].size * 300) / Map.getTimeModifier();
    }
    function _getSpaceDocks(address _player, uint _x, uint _y) internal view isPlayer(_player) returns (SpaceDock[] memory) {
        SpaceDock[] memory foundDocks;
        uint foundDockCount;
        SpaceDock[] memory playerDocks = _players[_addressToPlayer[_player]].spaceDocks;
        for(uint i=0; i<playerDocks.length; i++) {
            if(playerDocks[i].coordX == _x  && playerDocks[i].coordY == _y) {
                foundDocks[foundDockCount++];
            }
        }
        return foundDocks;
    }

    function getPlayerSpaceDocks(address _player) external view isPlayer(_player) returns (SpaceDock[] memory) {
        return _players[_addressToPlayer[_player]].spaceDocks;
    }
 
    function getBattlesAtLocation(uint _x, uint _y) external view returns(Battle[] memory) {
        Battle[] memory foundBattles;
        uint foundBattleCount;
        for(uint i=0; i<_battles.length; i++) {
            if(_battles[i].coordX == _x && _battles[i].coordY == _y) {
                foundBattles[foundBattleCount++] = _battles[i];
            }
        }
        return foundBattles;
    }

    function getAttackers(uint _battleId) external view returns (address[] memory) {
        return _battles[_battleId].attackTeam.members;
    }

    function getDefenders(uint _battleId) external view returns (address[] memory) {
        return _battles[_battleId].defendTeam.members;
    }

    function getAttackPower(address _player) public view isPlayer(_player) returns (uint) {
        uint totalAttack = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            totalAttack += _players[_addressToPlayer[_player]].ships[i] * _shipClasses[i].attackPower;
        }
        return totalAttack;
    }

    function getMaxFleetSize(address _player) external view isPlayer(_player) returns (uint) {
        return _getMaxFleetSize(_player);
    }

    function _getMaxFleetSize(address _player) internal view isPlayer(_player) returns (uint) {
        uint maxFleetSize = _baseMaxFleetSize; 
        for(uint i=0; i<_shipClasses.length; i++) {
            uint shipClassAmount = _players[_addressToPlayer[_player]].ships[i]; //get number of player's ships in this ship class
            maxFleetSize += (shipClassAmount * _shipClasses[i].hangarSize);
        }
        return maxFleetSize;
    }

    function getFleetSize(address _player) public view isPlayer(_player) returns(uint) {
        uint fleetSize = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            uint shipClassAmount = _players[_addressToPlayer[_player]].ships[i]; //get number of player's ships in this ship class
            fleetSize += (shipClassAmount * _shipClasses[i].size);
        }
        return fleetSize;
    }

    function getMineral(address _player) external view isPlayer(_player) returns(uint) {
        return _players[_addressToPlayer[_player]].mineral;
    }

    function setMineral(address _player, uint _amount) external onlyEditor isPlayer(_player) {
        _players[_addressToPlayer[_player]].mineral = _amount;
    }

    // how much mineral can a player currently hold
    function getMineralCapacity(address _player) public view isPlayer(_player) returns (uint){
        uint mineralCapacity = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            mineralCapacity += (_players[_addressToPlayer[_player]].ships[i] * _shipClasses[i].mineralCapacity);
        }
        return mineralCapacity;
    }

    //get the max mining capacity of player's fleet (how much mineral can a player mine each mining attempt)
    function getMiningCapacity(address _player) public view isPlayer(_player) returns (uint){
        uint miningCapacity = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            miningCapacity += (_players[_addressToPlayer[_player]].ships[i] * _shipClasses[i].miningCapacity);
        }
        return miningCapacity;
    }

    function setMap(address _new) external onlyOwner {
        require(address(0) != _new);
        Map = IMap(_new); 
        emit NewMap(_new);
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

    function getNameByAddress(address _address) external view isPlayer(_address) returns (string memory) {
        return _players[_addressToPlayer[_address]].name;
    }

    function getPlayerExists(address _player) external view returns (bool) {
        return _playerExists[_player];
    }

    function getPlayerBattleInfo(address _player) external view isPlayer(_player) returns (BattleStatus, uint) {
        return (_players[_addressToPlayer[_player]].battleStatus, _players[_addressToPlayer[_player]].battleId);
    }
}