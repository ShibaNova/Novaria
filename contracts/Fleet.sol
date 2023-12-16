// SPDX-License-Identifier: MIT
 
pragma solidity 0.8.7;

import './libs/Editor.sol';
import "./interfaces/ITreasury.sol";
import './libs/Helper.sol';
import "./interfaces/IMap.sol";
import "./libs/ShibaBEP20.sol";
import "./libs/SafeBEP20.sol";
 
contract Fleet is Editor {
    using SafeBEP20 for ShibaBEP20;

    constructor (
        IMap _map, 
        ITreasury _treasury, 
        ShibaBEP20 _token
        ) {
       // Token = ShibaBEP20(0x9249DAcc91cddB8C67E9a89e02E071085dE613cE);
       // BoostToken = ShibaBEP20(0x0F925153230C836761F294eA0d81Cef58E271Fb7);
        // Treasury = ITreasury(0x0c5a18Eb2748946d41f1EBe629fF2ecc378aFE91);
       //  Map = IMap(0xf8e81D47203A594245E36C48e151709F0C19fBe8);
        Token = _token;
        Treasury = _treasury;
        Map = _map;
        _baseMaxFleetSize = 5000;
        _battleSizeRestriction = 4;
        _startFee = 490 * 10**18;
        _scrapPercentage = 80;
        _timeModifier = 1;

        //load start data
        createShipClass('Viper', 1, 1, 3, 0, 0, 0, 10**18, 0);
        createShipClass('P. U. P.', 2, 0, 5, 5 * 10**17, 5 * 10**17, 0, 2 * 10**18, 0);
        createShipClass('Firefly', 5, 4, 18, 10**18, 0, 0, 9 * 10**18, 100);
        createShipClass('Gorian', 20, 2, 40, 0, 0, 200, 50 * 10**18, 1200);
        createShipClass('Viper Swarm', 1, 5, 15, 0, 0, 0, 15 * 10**18, 200);
        createShipClass('Lancer', 8, 20, 7, 0, 0, 0, 5 * 10**18, 500);

        _addShipyard('Haven', tx.origin, 0, 0, 5);
        _addShipyard('BestValueShips', tx.origin, 5, 4, 10);

        //add dummy battle
        battles.push();
        battles[battles.length-1].resolvedTime = 1; 
    }

    enum BattleStatus{ PEACE, ATTACK, DEFEND }
    //complete mapping of all names to avoid duplicates
    mapping (string => address) public names;

    struct Player {
        string name;
        address playerAddress;
        uint experience;
        uint[32] ships;
        uint battleId;
        uint mineral;
        BattleStatus battleStatus;
        SpaceDock[] spaceDocks;
    }
    Player[] public players;
    mapping (address => bool) public playerExists;
    mapping (address => uint) public addressToPlayer;

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
        uint resolvedTime;
        uint battleDeadline;
        uint coordX;
        uint coordY;
        Team attackTeam;
        Team defendTeam;
    }
    Battle[] public battles;

    struct Team {
        address[] members;
        uint attackPower;
        uint fleetSize;
    }

    IMap public Map;
    ITreasury public Treasury;
    ShibaBEP20 public Token; // nova token address
    address internal _boostDestWallet;
    uint internal boostTokenPerSize = 1 * 10**17;
    uint _baseMaxFleetSize;
    uint _battleSizeRestriction;
    uint _startFee;
    uint _scrapPercentage;
    uint _timeModifier; //allow all times to be changed

    event NewShipyard(uint _x, uint _y);

    function _createPlayer(string memory _name, address _player) internal {
        require(bytes(_name).length <= 12, 'FL:long');
        require(names[_name] == address(0), 'FL:dup name');
        require(playerExists[_player] == false, 'FL:play exists');
        players.push();
        players[players.length-1].name = _name;
        players[players.length-1].playerAddress = _player;
        names[_name] = _player; //add to name map
        addressToPlayer[_player] = players.length-1;
        playerExists[_player] = true;
        Map.setFleetLocation(msg.sender, 0, 0, 0, 0);
    }

    function insertCoinHere(string memory _name) external {
        //add starting fleet
        uint viperStart = 30;
        uint pupStart = 20;

        uint scrap = _addScrap(((_shipClasses[0].cost * viperStart) + (_shipClasses[1].cost * pupStart)) / Treasury.getCostMod());

        Treasury.pay(msg.sender, ((_startFee / Treasury.getCostMod()) - scrap));
        _createPlayer(_name, msg.sender);

        players[players.length-1].ships[0] = viperStart; //vipers
        players[players.length-1].ships[1] = pupStart; //pups
    }

    function _addScrap(uint _shipCost) internal returns(uint) {
        uint scrap = (_shipCost * _scrapPercentage) / 100;
        Token.safeTransferFrom(msg.sender, address(Map), scrap); //send scrap to Map contract
        Map.increasePreviousBalance(scrap);
        return scrap;
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

    function addShipyard(string memory _name, address _owner, uint _x, uint _y, uint8 _feePercent) external onlyEditor {
        _addShipyard(_name, _owner, _x, _y, _feePercent);
    }

    function _addShipyard(string memory _name, address _owner, uint _x, uint _y, uint8 _feePercent) internal {
        require(_shipyardExists[_x][_y] == false, 'FL:ship exists');

        _shipyards.push(Shipyard(_name, _owner, _x, _y, _feePercent, block.timestamp, 0, address(0), BattleStatus.PEACE));
        _shipyardExists[_x][_y] = true;
        _coordinatesToShipyard[_x][_y] = _shipyards.length-1;
        emit NewShipyard(_x, _y);
    }

    function initiateShipyardTakeover(uint _x, uint _y) external doesShipyardExist(_x, _y) {
        (uint fleetX, uint fleetY) = Map.getFleetLocation(msg.sender);
        require(fleetX == _x && fleetY == _y, 'FL:not ship');
        require(Map.isRefineryLocation(_x, _y) != true, 'FL:DMZ');

        Shipyard storage shipyard = _shipyards[_coordinatesToShipyard[_x][_y]];
        require(msg.sender != shipyard.takeoverAddress, 'FL:in takover');
        require(msg.sender != shipyard.owner, 'FL:own ship');
        require(shipyard.lastTakeoverTime < block.timestamp - ((60 * 60 * 24 * 14) / _timeModifier), 'FL:ship protect');

        uint fleetSize = getFleetSize(msg.sender);
        require(fleetSize >= 1000, 'FL:small');

        //takeover is possible if either shipyard is at peace or new takeover address has a larger fleet than current takeover address
        require(shipyard.status == BattleStatus.PEACE || fleetSize > getFleetSize(shipyard.takeoverAddress), 'FL:peace/small');
        shipyard.status = BattleStatus.ATTACK;
        shipyard.takeoverAddress = msg.sender;
        shipyard.takeoverDeadline = block.timestamp + ((60 * 60 * 24) / _timeModifier);

        uint takeoverFee = 25*10**18 / Treasury.getCostMod();
        Treasury.pay(msg.sender, takeoverFee);
        _addExperience(msg.sender, takeoverFee);
    }

    //complete shipyard takeover
    function completeShipyardTakeover(uint _x, uint _y) external doesShipyardExist(_x, _y) {
        Shipyard storage shipyard = _shipyards[_coordinatesToShipyard[_x][_y]];
        require(block.timestamp > shipyard.takeoverDeadline, 'FL:take deadline');

        if(getFleetSize(shipyard.takeoverAddress) >= 200) {
            shipyard.owner = shipyard.takeoverAddress;
            shipyard.lastTakeoverTime = block.timestamp;
        }
        shipyard.takeoverAddress = address(0);
        shipyard.status = BattleStatus.PEACE;
    }

    function setShipyardName(uint _x, uint _y, string memory _name) external doesShipyardExist(_x, _y) {
        require(bytes(_name).length <= 14, 'FL:name long');
        require(_shipyards[_coordinatesToShipyard[_x][_y]].owner == msg.sender);
        _shipyards[_coordinatesToShipyard[_x][_y]].name = _name;
    }

    function setShipyardFeePercent(uint _x, uint _y, uint8 _feePercent) external doesShipyardExist(_x, _y) {
        require(_feePercent < 100, 'FL:fee high');
        require(_shipyards[_coordinatesToShipyard[_x][_y]].owner == msg.sender);
        _shipyards[_coordinatesToShipyard[_x][_y]].feePercent = _feePercent;
    }

    // Ship building function
    function buildShips(uint _x, uint _y, uint _shipClassId, uint _amount, uint _cost) external {
        address sender = msg.sender;
        require(_hasSpaceDock(sender, _x, _y) == false, 'FL:no dock');
        require((_shipClasses[_shipClassId].size * _amount) <= getMaxFleetSize(sender), 'FL:large');

        Player storage player = players[addressToPlayer[sender]];
        require(player.experience >= _shipClasses[_shipClassId].experienceRequired, 'FL:exp');

        //total build cost
        uint totalCost = getDockCost(_shipClassId, _amount);

        //send fee to shipyard owner
        Shipyard memory shipyard = _shipyards[_coordinatesToShipyard[_x][_y]];
        uint ownerFee = (totalCost * shipyard.feePercent) / 100;
        require(_cost == totalCost + ownerFee, 'FL:cost mismatch');

        if(ownerFee > 0) {
            Token.safeTransferFrom(sender, shipyard.owner, ownerFee);
        }

        Treasury.pay(sender, totalCost - _addScrap(totalCost));

        player.spaceDocks.push(SpaceDock(_shipClassId, _amount, block.timestamp + getBuildTime(_shipClassId, _amount), _x, _y));
        _addExperience(sender, totalCost + ownerFee);
    }

    /* move ships to fleet, call must fit the following criteria:
        1) fleet must be at same location as shipyard being requested
        2) amount requested must be less than or equal to amount in dry dock
        3) dry dock build must be completed (completion time must be past block timestamp)
        4) claim size must not put fleet over max fleet size */
    function claimShips(uint spaceDockId, uint _amount) external {
        address sender = msg.sender;
        Player storage player = players[addressToPlayer[sender]];
        SpaceDock storage dock = player.spaceDocks[spaceDockId];
        (uint fleetX, uint fleetY) = Map.getFleetLocation(sender);
        require(fleetX == dock.coordX && fleetY == dock.coordY, 'FL:not ship');
        require(isInBattle(sender) == false, "FL:battle/takeover");

        require(_amount <= dock.amount, 'FL:many');
        require(block.timestamp > dock.completionTime, 'FL:not built');

        require(getFleetSize(sender) + (_amount * _shipClasses[dock.shipClassId].size) <= getMaxFleetSize(sender), 'FL:claim large');

        player.ships[dock.shipClassId] += _amount; //add ships to fleet
        dock.amount -= _amount; //remove ships from drydock

        if(dock.amount <= 0) {
            player.spaceDocks[spaceDockId] = player.spaceDocks[player.spaceDocks.length-1];
            player.spaceDocks.pop();
        }
    }

    function boostBuildTime(uint _spaceDockId) external {
        address sender = msg.sender;
        Player storage player = players[addressToPlayer[sender]];
        SpaceDock storage dock = player.spaceDocks[_spaceDockId];
        require(dock.completionTime > block.timestamp, 'FL:already built');
        uint boostCost = dock.amount * _shipClasses[dock.shipClassId].size * (boostTokenPerSize / Treasury.getCostMod());
        ShibaBEP20 BoostToken = ShibaBEP20(0x0F925153230C836761F294eA0d81Cef58E271Fb7);
        BoostToken.safeTransferFrom(sender, address(_boostDestWallet), boostCost);

        dock.completionTime -= ((dock.completionTime - block.timestamp) / 2); //reduce completion time by 50%
    }

    function setBoostDestWallet(address _new) external onlyEditor {
        _boostDestWallet = _new;
    }

    modifier doesShipyardExist(uint _x, uint _y) {
        require(_shipyardExists[_x][_y] == true, 'FL:no ship');
        _;
    }

    //can player participate in this battle
    modifier canJoinBattle(address _player, address _target) {
        require(playerExists[_player] == true, 'FL:no player');
        require(playerExists[_target] == true, 'FL:no target');
        require(_player != _target, 'FL:player/target same');

        //verify players are at same location
        (uint attackX, uint attackY) = Map.getFleetLocation(_player);
        (uint targetX, uint targetY) = Map.getFleetLocation(_target);
        require(attackX == targetX && attackY == targetY, 'FL:dif location');

        //cannot attack in DMZ which is a shipyard/refinery location
        require((Map.isRefineryLocation(targetX, targetY) && _shipyardExists[targetX][targetY]) != true, 'FL:DMZ');

        require(players[addressToPlayer[_player]].battleStatus == BattleStatus.PEACE, 'FL:in battle');
        require((battles[players[addressToPlayer[_player]].battleId].resolvedTime + ((60 * 60 * 48) / _timeModifier)) < block.timestamp, 'FL:battle soon');
        _;
    }

    function _joinTeam(address _hero, uint _battleId, Team storage _team, BattleStatus _mission) internal {
            players[addressToPlayer[_hero]].battleId = _battleId;
            players[addressToPlayer[_hero]].battleStatus = _mission;
            _team.members.push(_hero);
            _team.attackPower += getAttackPower(_hero);
            _team.fleetSize += getFleetSize(_hero);
    }

    //battleWindow is 18 hours
    function enterBattle(address _target, BattleStatus mission) external canJoinBattle(msg.sender, _target) {
        (uint targetX, uint targetY) = Map.getFleetLocation(_target);
        Player storage targetPlayer = players[addressToPlayer[_target]];
        require(mission != BattleStatus.PEACE, 'FL:no peace');
        require((mission == BattleStatus.DEFEND? targetPlayer.battleStatus != BattleStatus.PEACE : true), 'FL:peace');

        uint targetBattleId = targetPlayer.battleId;
        if(mission == BattleStatus.ATTACK) {

            //create new battle, but new battle cannot be initated by a fleet to large or too small
            if(targetPlayer.battleStatus == BattleStatus.PEACE) {
                require(getFleetSize(msg.sender) * _battleSizeRestriction >= getFleetSize(_target), 'FL:player small');
                require(getFleetSize(_target) * _battleSizeRestriction >= getFleetSize(msg.sender), 'FL:target small');
                Team memory attackTeam; Team memory defendTeam;
                battles.push(Battle(0, block.timestamp + (60 * 60 * 18 / _timeModifier), targetX, targetY, attackTeam, defendTeam));
                Map.adjustActiveBattleCount(targetX, targetY, 1);
                _joinTeam(_target, battles.length-1, battles[battles.length-1].defendTeam, BattleStatus.DEFEND);
                targetBattleId = battles.length-1;
            }
            _joinTeam(msg.sender, targetBattleId, battles[targetBattleId].attackTeam, BattleStatus.ATTACK);
        }
        else if(mission == BattleStatus.DEFEND) {
            _joinTeam(msg.sender, targetBattleId, battles[targetBattleId].defendTeam, BattleStatus.DEFEND);
        }
    }

    //calc battle, only works for two teams
    function goBattle(uint battleId) external {
        Battle memory battle = battles[battleId];
        require(block.timestamp > battle.battleDeadline, 'FL:battle prep');
        require(battle.resolvedTime == 0, 'FL:battle over');

        Team[2] memory teams = [battle.attackTeam, battle.defendTeam];
        uint totalMineralLost;
        uint totalScrap;
        for(uint i=0; i<teams.length; i++) {
            //if 1st team, get 2nd team attack power, else get 1st, increase attack power for attacking team by 20%
            uint otherTeamAttackPower = (i==0 ? teams[1].attackPower : teams[0].attackPower += ((teams[0].attackPower * 20) / 100));
            for(uint j=0; j<teams[i].members.length; j++) {
                address memberAddress = teams[i].members[j];
                Player storage player = players[addressToPlayer[memberAddress]];
                uint memberMineralCapacityLost = 0;
                uint memberMineralCapacity = getMineralCapacity(memberAddress);
                for(uint k=0; k<_shipClasses.length; k++) {
                    uint numClassShips = player.ships[k]; //number of ships that team member has of this class
                    if(numClassShips > 0) {

                        //calculate opposing team's damage to this member
                        uint damageTaken = (otherTeamAttackPower * numClassShips * _shipClasses[k].size) / teams[i].fleetSize;

                        //actual ships lost compares the most ships lost from the damage taken by the other team with most ships that member has, member cannot lose more ships than he has
                        //modified equation to limit ship loss to no more than 25% and never more than 3 ships
                        uint maxShipsDestroyed = damageTaken / _shipClasses[k].shield;
                        uint actualShipsLost = Helper.getMin(numClassShips / 4, maxShipsDestroyed);

                        //if less than 4 ships, but high damage, destroy at least 1 ship
                        if(maxShipsDestroyed > 0 && actualShipsLost == 0) {
                            actualShipsLost = 1;
                        }

                        //token value of ships lost
                        totalScrap += (actualShipsLost * _shipClasses[k].cost / Treasury.getCostMod() * _scrapPercentage) / 100;

                        //calculate mineral capacity lost by this class of member's ships
                        memberMineralCapacityLost += (actualShipsLost * _shipClasses[k].mineralCapacity);

                        //destroy ships lost
                        player.ships[k] -= Helper.getMin(actualShipsLost, player.ships[k]);
                    }
                }
                //member's final lost mineral is the percentage of filled mineral capacity
                if(memberMineralCapacityLost > 0) {
                    totalMineralLost += (memberMineralCapacityLost * player.mineral) / memberMineralCapacity;
                    player.mineral -= (memberMineralCapacityLost * player.mineral) / memberMineralCapacity;
                }
            }
        }

        Map.addSalvageToPlace(battle.coordX, battle.coordY, totalMineralLost + totalScrap);
        _endBattle(battleId);
    }

    //after battle is complete
    function _endBattle(uint _battleId) internal {
        //put attackers and denders into peace status
        Battle memory battleToEnd = battles[_battleId];
        for(uint i=0; i<battleToEnd.attackTeam.members.length; i++) {
            players[addressToPlayer[battleToEnd.attackTeam.members[i]]].battleStatus = BattleStatus.PEACE;
        }
        for(uint i=0; i<battleToEnd.defendTeam.members.length; i++) {
            players[addressToPlayer[battleToEnd.defendTeam.members[i]]].battleStatus = BattleStatus.PEACE;
        }

        battles[_battleId].resolvedTime = block.timestamp;
        Map.adjustActiveBattleCount(battleToEnd.coordX, battleToEnd.coordY, -1);
    }

    //add experience to player based on in game purchases
    function addExperience(address _player, uint _paid) external onlyEditor {
        //each nova paid in game, gets player 1/10 experience point
        _addExperience(_player, _paid);
    }
     function _addExperience(address _player, uint _paid) internal isPlayer(_player) {
        //each nova paid in game, gets player 1/10 experience point
        players[addressToPlayer[_player]].experience += ((_paid * Treasury.getCostMod()) / 10**19);
    }

    //get players experience
    function getExperience(address _player) external view isPlayer(_player) returns (uint) {
        return players[addressToPlayer[_player]].experience;
    }

    modifier isPlayer(address _player) {
        require(playerExists[_player] == true, 'FL:no player');
        _;
    }

    //if player battle status is NOT PEACE or player is taking over shipyard, player is in a battle
    function isInBattle(address _player) public view isPlayer(_player) returns(bool) {
        (uint fleetX, uint fleetY) = Map.getFleetLocation(_player);
        return
        (players[addressToPlayer[_player]].battleStatus != BattleStatus.PEACE
            || _shipyards[_coordinatesToShipyard[fleetX][fleetY]].takeoverAddress == _player);
    }

    function getPlayerCount() external view returns(uint) {
        return players.length;
    }

    function getShips(address _player) external view isPlayer(_player) returns (uint[32] memory) {
        return players[addressToPlayer[_player]].ships;
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

    //15 minutes per size
    function getBuildTime(uint _shipClassId, uint _amount) public view returns(uint) {
        return (_amount * _shipClasses[_shipClassId].size * 900) / _timeModifier;
    }

    function _hasSpaceDock(address _player, uint _x, uint _y) public view isPlayer(_player) returns(bool) {
        SpaceDock[] memory playerDocks = players[addressToPlayer[_player]].spaceDocks;
        for(uint i=0; i<playerDocks.length; i++) {
            if(playerDocks[i].coordX == _x  && playerDocks[i].coordY == _y) {
                return true;
            }
        }
        return false;
    }

    function getPlayerSpaceDocks(address _player) external view isPlayer(_player) returns (SpaceDock[] memory) {
        return players[addressToPlayer[_player]].spaceDocks;
    }
 
    function getBattlesAtLocation(uint _x, uint _y, uint _startTime, uint _endTime) external view returns(uint[] memory) {
        uint totalFoundBattles;
        for(uint i=0; i<battles.length; i++) {
            if(battles[i].coordX == _x && battles[i].coordY == _y
                && battles[i].resolvedTime >= _startTime && battles[i].resolvedTime <= _endTime
            ) {
                totalFoundBattles++;
            }
        }

        uint[] memory foundBattles = new uint[](totalFoundBattles);
        uint foundBattlesCount;
        for(uint i=0; i<battles.length; i++) {
            if(battles[i].coordX == _x && battles[i].coordY == _y
                && battles[i].resolvedTime >= _startTime && battles[i].resolvedTime <= _endTime
            ) {
                foundBattles[foundBattlesCount] = i;
                foundBattlesCount++;
            }
        }
        return foundBattles;
    }

    function getAttackPower(address _player) public view isPlayer(_player) returns (uint) {
        uint totalAttack = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            totalAttack += players[addressToPlayer[_player]].ships[i] * _shipClasses[i].attackPower;
        }
        return totalAttack;
    }

    function getMaxFleetSize(address _player) public view isPlayer(_player) returns (uint) {
        uint maxFleetSize = _baseMaxFleetSize; 
        for(uint i=0; i<_shipClasses.length; i++) {
            maxFleetSize += (players[addressToPlayer[_player]].ships[i] * _shipClasses[i].hangarSize);
        }
        return maxFleetSize;
    }

    function getFleetSize(address _player) public view isPlayer(_player) returns(uint) {
        uint fleetSize = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            fleetSize += (players[addressToPlayer[_player]].ships[i] * _shipClasses[i].size);
        }
        return fleetSize;
    }

    function getMineral(address _player) external view isPlayer(_player) returns(uint) {
        return players[addressToPlayer[_player]].mineral;
    }

    function setMineral(address _player, uint _amount) external onlyEditor isPlayer(_player) {
        players[addressToPlayer[_player]].mineral = _amount;
    }

    // how much mineral can a player currently hold
    function getMineralCapacity(address _player) public view isPlayer(_player) returns (uint){
        uint mineralCapacity = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            mineralCapacity += (players[addressToPlayer[_player]].ships[i] * _shipClasses[i].mineralCapacity);
        }
        return mineralCapacity;
    }

    //get the max mining capacity of player's fleet (how much mineral can a player mine each mining attempt)
    function getMiningCapacity(address _player) public view isPlayer(_player) returns (uint){
        uint miningCapacity = 0;
        for(uint i=0; i<_shipClasses.length; i++) {
            miningCapacity += (players[addressToPlayer[_player]].ships[i] * _shipClasses[i].miningCapacity);
        }
        return miningCapacity;
    }

    function setMap(address _new) external onlyOwner {
        Map = IMap(_new); 
    }

    function setTreasury(address _new) external onlyOwner{
        Treasury = ITreasury(_new);
    }

    function getPlayerBattleInfo(address _player) external view isPlayer(_player) returns (BattleStatus, uint) {
        return (players[addressToPlayer[_player]].battleStatus, players[addressToPlayer[_player]].battleId);
    }

    function setTimeModifier(uint _new) external onlyOwner {
        _timeModifier = _new;
    }
}