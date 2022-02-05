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
        Token = ShibaBEP20(0xd9145CCE52D386f254917e481eB44e9943F39138);
        Treasury = ITreasury(0xd8b934580fcE35a11B58C6D73aDeE468a2833fa8);
        Map = IMap(0xf8e81D47203A594245E36C48e151709F0C19fBe8);
        _baseMaxFleetSize = 5000;
        _baseFleetSize = 0;
        _timeModifier = 1000;
        _battleWindow = 3600; //60 minutes
        _battleSizeRestriction = 4;
        _startFee = 10**18;
        _scrapPercentage = 25;
        _battleCounter = 0;

        //load start data
        createShipClass("Viper", 1, 1, 3, 0, 0, 0, 60, 10**18);
        createShipClass("Mole", 2, 0, 5, 10**17, 10**16, 0, 30, 2 * 10**18);
        addShipyard(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2,0,0,7);
        addShipyard(0x729F3cA74A55F2aB7B584340DDefC29813fb21dF,5,5,5);
        loadPlayers();
    }

    enum BattleStatus{ PEACE, ATTACK, DEFEND }
    //complete mapping of all names to avoid duplicates
    mapping (string => address) _names;

    struct Player {
        string name;
        uint experience;
        uint16[16] ships;
        uint battleId;
        uint mineral;
        BattleStatus battleStatus;
        SpaceDock[] spaceDocks;
    }
    Player[] _players;
    mapping (address => bool) playerExists;
    mapping (address => uint) addressToPlayer;

    //ship class data
    struct ShipClass {
        string name;
        uint16 size;
        uint16 attackPower;
        uint16 shield;
        uint mineralCapacity;
        uint miningCapacity;
        uint16 hangarSize;
        uint16 buildTime;
        uint cost;
    }
    ShipClass[] _shipClasses;

    //shipyard data
    struct Shipyard {
        string name;
        address owner;
        uint coordX;
        uint coordY;
        uint8 feePercent;
    }

    Shipyard[] _shipyards;
    mapping (uint => mapping(uint => bool)) _shipyardExists;
    mapping (uint => mapping(uint => uint)) _coordinatesToShipyard; //shipyard locations

    struct SpaceDock {
        uint16 shipClassId;
        uint16 amount; 
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
    uint16 _baseMaxFleetSize;
    uint16 _baseFleetSize; //size of capital ship
    uint16 _timeModifier;
    uint16 _battleWindow;
    uint16 _battleSizeRestriction;
    uint16 _scrapPercentage;
    uint16 _battleCounter;
    uint _startFee;

    event NewShipyard(uint _x, uint _y);

    //BEGIN*****************FUNCTIONS FOR TESTING, CAN BE DELETED LATER
    function loadPlayers() public {
        _createPlayer('Koray', 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);
        _players[0].ships[0] = 100;
        _players[0].ships[1] = 19;

        _createPlayer('Nate', 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
        _players[1].ships[0] = 43;
        _players[1].ships[1] = 4;
    }

    function battleTest() public {
        enterBattle(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2, BattleStatus.ATTACK);
    }
    //END*****************FUNCTIONS FOR TESTING, CAN BE DELETED LATER

    function _createPlayer(string memory _name, address _player) internal {
        require(bytes(_name).length < 16, 'FLEET: name too long');
        require(_names[_name] == address(0), 'FLEET: duplicate name');
        require(playerExists[_player] == false, 'FLEET: player exists');
        _players.push();
        _players[_players.length-1].name = _name;
        _names[_name] = _player; //add to name map
        addressToPlayer[_player] = _players.length-1;
        playerExists[_player] = true;
    }

    function insertCoinHere(string memory _name) external {
        Treasury.pay(msg.sender, _startFee / Treasury.getCostMod());
        _createPlayer(_name, msg.sender);
        Map.setFleetLocation(msg.sender, 0, 0, 0, 0);
    }

    function getPlayers() external view returns (Player[] memory) {
        return _players;
    }

    function createShipClass(
        string memory _name,
        uint16 _size,
        uint16 _attackPower,
        uint16 _shield,
        uint _mineralCapacity,
        uint _miningCapacity,
        uint16 _hangarSize,
        uint16 _buildTime,
        uint _cost) public onlyOwner {

        _shipClasses.push(ShipClass(_name, _size, _attackPower, _shield, _mineralCapacity, _miningCapacity,_hangarSize, _buildTime, _cost));
    }

    function addShipyard(address _owner, uint _x, uint _y, uint8 _feePercent) public onlyOwner {
        require(_shipyardExists[_x][_y] == false, 'FLEET: shipyard exists');
        require(Map.isShipyardLocation(_x, _y) == true, 'FLEET: shipyard unavailable');

        string memory name = Map.getPlaceName(_x, _y);

        _shipyards.push(Shipyard(name, _owner, _x, _y, _feePercent));
        _shipyardExists[_x][_y] = true;
        _coordinatesToShipyard[_x][_y] = _shipyards.length-1;
        emit NewShipyard(_x, _y);
    }

    // Ship building Function
    function buildShips(uint _x, uint _y, uint16 _shipClassId, uint16 _amount) external {
        address sender = msg.sender;
        require(getSpaceDocks(sender, _x, _y).length == 0, 'FLEET: no dock available');
        require((_shipClasses[_shipClassId].size * _amount) < _getMaxFleetSize(sender), 'FLEET: order too large');

        //total build cost
        uint totalCost = getDockCost(_shipClassId, _amount);

        //send fee to shipyard owner
        Shipyard memory shipyard = _shipyards[_coordinatesToShipyard[_x][_y]];
        uint ownerFee = (totalCost * shipyard.feePercent) / 100;
        Token.safeTransferFrom(sender, shipyard.owner, ownerFee);

        Treasury.pay(sender, (totalCost * (100-_scrapPercentage)) / 100);
        uint scrap = (totalCost * _scrapPercentage) / 100;
        Token.safeTransferFrom(sender, address(Map), scrap); //send scrap to Map contract
        Map.increasePreviousBalance(scrap);

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
        require(playerExists[sender] == true, 'FLEET: no player');
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
    }

    function enterBattle(address _target, BattleStatus mission) public canJoinBattle(msg.sender, _target) {
        Player storage targetPlayer = _players[addressToPlayer[_target]];
        require(mission != BattleStatus.PEACE, 'FLEET: no peace');
        require((mission == BattleStatus.DEFEND? targetPlayer.battleStatus != BattleStatus.PEACE : true), 'FLEET: player not under attack');

        uint targetBattleId = targetPlayer.battleId;
        if(mission == BattleStatus.ATTACK) {
            if(targetPlayer.battleStatus == BattleStatus.PEACE) { //if new battle
                Team memory attackTeam; Team memory defendTeam;
                (uint targetX, uint targetY) = Map.getFleetLocation(_target);
                _battles.push(Battle(_battleCounter++, block.timestamp + _getBattleWindow(), targetX, targetY, attackTeam, defendTeam));
                _battleCountToId[_battleCounter] = _battles.length-1;
                _joinTeam(_target, _battles.length-1, _battles[_battles.length-1].defendTeam, BattleStatus.DEFEND);
            }
            _joinTeam(_target, targetBattleId, _battles[targetBattleId].attackTeam, BattleStatus.ATTACK);
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
                for(uint16 k=0; k<_shipClasses.length; k++) {
                    uint numClassShips = _players[addressToPlayer[member]].ships[k]; //number of ships that team member has of this class

                    //calculate opposing team's damage to this member
                    uint damageTaken = (otherTeamAttackPower * numClassShips * _shipClasses[k].size) / teams[i].fleetSize;

                    //actual ships lost compares the most ships lost from the damage taken by the other team with most ships that member has, member cannot lose more ships than he has
                    uint actualShipsLost = Helper.getMin(numClassShips, damageTaken / _shipClasses[k].shield);

                    //token value of ships lost
                    totalScrap += (actualShipsLost  * _shipClasses[k].cost * _scrapPercentage) / 100;

                    //calculate mineral capacity lost by this class of member's ships
                    memberMineralCapacityLost += (actualShipsLost * _shipClasses[k].mineralCapacity);

                    //destroy ships lost
                    _destroyShips(member, k, uint16(actualShipsLost));
                }
                //member's final lost mineral is the percentage of filled mineral capacity
                if(memberMineralCapacityLost > 0) {
                    totalMineralLost += (memberMineralCapacityLost * _players[addressToPlayer[member]].mineral) / getMineralCapacity(member);
                }
            }
        }

   //     Map.addSalvageToPlace(battle.coordX, battle.coordY, totalMineralLost + totalScrap);

        _endBattle(battleId);
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

    //if player battle status is NOT PEACE, player is in a battle
    function isInBattle(address _player) external view returns(bool) {
        require(playerExists[_player] == true, 'FLEET: no player');
        if(_players[addressToPlayer[_player]].battleStatus != BattleStatus.PEACE) {
            return true;
        }
        else {
            return false;
        }
    }

    function getShips(address _player) external view returns (uint16[16] memory) {
        require(playerExists[_player] == true, 'FLEET: no player');
        return _players[addressToPlayer[_player]].ships;
    }

    function getBattleByCount(uint _battleCount) external view returns (Battle memory) {
        return _battles[_battleCountToId[_battleCount]];
    }
    
    function getBattle(uint _battleId) external view returns (Battle memory) {
        return _battles[_battleId];
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
        require(playerExists[_player] == true, 'FLEET: no player');
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
        require(playerExists[_player] == true, 'FLEET: no player');
        return _players[addressToPlayer[_player]].spaceDocks;
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

    function _getBattleWindow() internal view returns (uint) {
        return _battleWindow / _timeModifier;
    }
    function getAttackPower(address _player) public view returns (uint) {
        require(playerExists[_player] == true, 'FLEET: no player');
        uint totalAttack = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            totalAttack += _players[addressToPlayer[_player]].ships[i] * _shipClasses[i].attackPower;
        }
        return totalAttack;
    }

    function getMaxFleetSize(address _player) external view returns (uint) {
        require(playerExists[_player] == true, 'FLEET: no player');
        return _getMaxFleetSize(_player);
    }

    function _getMaxFleetSize(address _player) internal view returns (uint) {
        require(playerExists[_player] == true, 'FLEET: no player');
        uint maxFleetSize = _baseMaxFleetSize; 
        for(uint i=0; i<_shipClasses.length; i++) {
            uint shipClassAmount = _players[addressToPlayer[_player]].ships[i]; //get number of player's ships in this ship class
            maxFleetSize += (shipClassAmount * _shipClasses[i].hangarSize);
        }
        return maxFleetSize / Treasury.getCostMod();
    }

    function getFleetSize(address _player) public view returns(uint) {
        require(playerExists[_player] == true, 'FLEET: no player');
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

    function getMineral(address _player) external view returns(uint) {
        require(playerExists[_player] == true, 'FLEET: no player');
        return _players[addressToPlayer[_player]].mineral;
    }

    //NEEDS TO BE RESTRICTED TO MAP CONTRACT
    function setMineral(address _player, uint _amount) external {
        require(playerExists[_player] == true, 'FLEET: no player');
        _players[addressToPlayer[_player]].mineral = _amount;
    }

    //get the max mineral capacity of player's fleet
    function getMaxMineralCapacity(address _player) public view returns (uint){
        require(playerExists[_player] == true, 'FLEET: no player');
        uint mineralCapacity = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            mineralCapacity += (_players[addressToPlayer[_player]].ships[i] * _shipClasses[i].mineralCapacity);
        }
        return mineralCapacity / Treasury.getCostMod();
    }

    // how much mineral can a player currently hold
    function getMineralCapacity(address _player) public view returns (uint){
        require(playerExists[_player] == true, 'FLEET: no player');
        uint mineralCapacity = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            mineralCapacity += (_players[addressToPlayer[_player]].ships[i] * _shipClasses[i].mineralCapacity);
        }
        return mineralCapacity / Treasury.getCostMod();
    }

    //get the max mining capacity of player's fleet (how much mineral can a player mine each mining attempt)
    function getMiningCapacity(address _player) public view returns (uint){
        require(playerExists[_player] == true, 'FLEET: no player');
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
        require(playerExists[_address] == true, 'FLEET: no player');
        return _players[addressToPlayer[_address]].name;
    }

    function getPlayerExists(address _player) external view returns (bool) {
        return playerExists[_player];
    }
}