// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import './libs/Editor.sol';
import './libs/Helper.sol';
import './libs/ShibaBEP20.sol';
import './libs/SafeBEP20.sol';
import "./interfaces/ITreasury.sol";
import "./interfaces/IShadowPool.sol";
import "./interfaces/IFleet.sol";

contract Map is Editor {
    using SafeBEP20 for ShibaBEP20;

    constructor (
        // ShibaBEP20 _token,
        // ITreasury _treasury
        //IShadowPool _shadowPool,
        //IFleet _fleet
    ) {
        Token = ShibaBEP20(0xd9145CCE52D386f254917e481eB44e9943F39138);
        Treasury = ITreasury(0xd8b934580fcE35a11B58C6D73aDeE468a2833fa8);
        Fleet = IFleet(0xD7ACd2a9FD159E69Bb102A1ca21C9a3e3A5F771B);
       // ShadowPool = _shadowPool;

        previousBalance = 0;
        _baseTravelCost = 10**15;
        _baseTravelCooldown = 2700; //45 minutes
        _travelCooldownPerDistance = 900; //15 minutes
        _maxTravel = 10; //AU
        _rewardsTimer = 0;
        _timeModifier = 100;
        _miningCooldown = 1800; //30 minutes
        _minTravelSize = 25;

        _placeTypes.push('star');
        _placeTypes.push('planet');
        _placeTypes.push('jumpgate');

        _addStar(2, 2, 'Solar', 9); // first star
        _addPlanet(0, 0, 0, 'Haven', false, true, true); //Haven
        _addPlanet(0, 3, 4, 'Cetrus 22A', true, false, false); //unrefined planet
        _addPlanet(0, 1, 6, 'Cetrus 22B', true, false, false); //unrefined planet
        _addPlanet(0, 5, 5, 'BestValueShips', false, true, true); // BestValueShips
    }

    ShibaBEP20 public Token; // TOKEN Token
    ITreasury public Treasury; //Contract that collects all Token payments
    IShadowPool public ShadowPool; //Contract that collects Token emissions
    IFleet public Fleet; // Fleet Contract

    uint public previousBalance; // helper for allocating Token
    uint _rewardsMod; // = x/100, the higher the number the more rewards sent to this contract
    uint _rewardsTimer; // Rewards can only be pulled from shadow pool every 4 hours?
    uint rewardsDelay;
    mapping (uint => bool) isPaused; // can pause token mining for mining planets
    uint _timeModifier; //allow all times to be changed
    uint _miningCooldown; // how long before 
    uint _minTravelSize; //min. fleet size required to travel

    // Fleet Info and helpers
    mapping (address => uint[2]) fleetLocation; //address to [x,y] array
    mapping(uint => mapping (uint => address[])) fleetsAtLocation; //reverse index to see what fleets are at what location

    mapping(address => uint) _fleetMineral; //amount of mineral a fleet is carrying
    mapping (address => uint) _travelCooldown; // limits how often fleets can travel
    mapping (address => uint) _fleetMiningCooldown; // limits how often a fleet can mine mineral
    mapping (address => uint) _fleetLastShipyardPlace; // last shipyard place that fleet visited
    
    uint _baseTravelCooldown; 
    uint _travelCooldownPerDistance; 
    uint _baseTravelCost; // Token cost to travel 1 AU
    uint _maxTravel; // max distance a fleet can travel in 1 jump

    string[] _placeTypes; // list of placeTypes

    struct Place {
        uint id; //native key 
        string placeType;
        uint childId;
        uint coordX;
        uint coordY;
        string name;
        uint salvage;
    }
    Place[] _places;
    mapping (uint => mapping(uint => bool)) _placeExists;
    mapping (uint => mapping(uint => uint)) _coordinatePlaces;

    struct Planet {
        uint id; //native key
        uint placeId; //foreign key to places
        uint starId; //foreign key to stars
        uint starDistance;
        bool isMiningPlanet;
        uint availableMineral;
        bool hasRefinery;
        bool hasShipyard;
    }
    Planet[] _planets;

    struct Star {
        uint id; //native key
        uint placeId; //foreign key to places
        uint luminosity;
        uint totalMiningPlanets;
        uint totalMiningPlanetDistance;
    }
    Star[] _stars;

    event NewShadowPool(address _new);
    event NewFleet(address _new);
    event NewToken(address _new);
    event NewTreasury(address _new);
    event NewRewardsMod(uint _new);
    event MineralGained(address _player, int _amountGained, uint _amountBurned);
    event MineralTransferred(address _from, address _to, uint _amountSent, uint _amountReceived, uint _amountBurned);
    event MineralRefined(address _fleet, uint _amount);
    event MineralMined(address _fleet, uint _amount);
    event NewPlanet(uint _star, uint _x, uint _y);
    event NewStar(uint _x, uint _y);

    function _addPlace(string memory _placeType, uint _childId, uint _x, uint _y, string memory _name) internal {
        require(_placeExists[_x][_y] == false, 'Place already exists in these coordinates');
        uint placeId = _places.length;
        _places.push(Place(placeId, _placeType, _childId, _x, _y, _name, 0));

        //set place in coordinate mapping
        _placeExists[_x][_y] = true;
        _coordinatePlaces[_x][_y] = placeId;
    }

    function _addStar(uint _x, uint _y, string memory _name, uint _luminosity) internal {
        //add star to stars list
        uint starId = _stars.length;
        _stars.push(Star(starId, _places.length, _luminosity, 0, 0));

        _addPlace('star', starId, _x, _y, _name);
        emit NewStar(_x, _y);
    }

    function addStar(uint _x, uint _y, string memory _name, uint _luminosity) external onlyOwner {
        _addStar(_x, _y, _name, _luminosity);
    }

    function _addPlanet(uint _starId, uint _x, uint _y, string memory _name, bool _isMiningPlanet, bool _hasRefinery, bool _hasShipyard) internal {
        uint starX = _places[_stars[_starId].placeId].coordX;
        uint starY = _places[_stars[_starId].placeId].coordY;
        uint starDistance = Helper.getDistance(starX, starY, _x, _y);

        //add planet info to star
        if(_isMiningPlanet) {
            _stars[_starId].totalMiningPlanetDistance += starDistance;
            _stars[_starId].totalMiningPlanets += 1;
        }

        uint planetId = _planets.length;
        _planets.push(Planet(planetId, _places.length, _starId, starDistance, _isMiningPlanet, 0, _hasRefinery, _hasShipyard));

        _addPlace('planet', planetId, _x, _y, _name);
        emit NewPlanet(_starId, _x, _y);
    }

    function addPlanet(uint _starId, uint _x, uint _y, string memory _name, bool _isMiningPlanet, bool _hasRefinery, bool _hasShipyard) external onlyOwner{
        _addPlanet(_starId, _x, _y, _name, _isMiningPlanet, _hasRefinery, _hasShipyard);
    }

    /* get coordinatePlaces cannot handle a map box larger than 255 */
    function getCoordinatePlaces(uint _lx, uint _ly, uint _rx, uint _ry) external view returns(Place[] memory) {
        uint xDistance = (_rx - _lx) + 1;
        uint yDistance = (_ry - _ly) + 1;
        uint numCoordinates = xDistance * yDistance;
        require(xDistance * yDistance < 256, 'MAP: Too much data in loop');

        Place[] memory foundCoordinatePlaces = new Place[]((numCoordinates));

        uint counter = 0;
        for(uint i=_lx; i<=_rx;i++) {
            for(uint j=_ly; j<=_ry;j++) {
                foundCoordinatePlaces[counter] = _places[_coordinatePlaces[i][j]];
                counter++;
            }
        }
        return foundCoordinatePlaces;
    }

    function _getCoordinatePlace(uint _x, uint _y) internal view returns (Place memory) {
        return _places[_coordinatePlaces[_x][_y]];
    }

    //three different return statements to avoid stack too deep error
    function getCoordinateInfo(uint _x, uint _y) external view returns (string memory, string memory, uint, bool, bool, uint) {
        if(_placeExists[_x][_y] == true) {
            Place memory place  = _places[_coordinatePlaces[_x][_y]];
            if(Helper.isEqual(place.placeType, 'planet')) {
                return(place.name, place.placeType, place.salvage,
                _planets[place.childId].hasShipyard, _planets[place.childId].hasRefinery, _planets[place.childId].availableMineral);
            }
            return(place.name, place.placeType, place.salvage, false, false, 0);
        }
        return ("", "", 0, false, false, 0);
    }

    function getPlaceId(uint _x, uint _y) public view returns (uint) {
        return (_coordinatePlaces[_x][_y]);
    }

    function getPlaceName(uint _x, uint _y) external view returns(string memory) {
        return _places[getPlaceId(_x, _y)].name;
    }

    // currently no check for duplicates
    function addPlaceType(string memory _name) external onlyOwner {
        _placeTypes.push(_name);
    }

    // get total star luminosity
    function getTotalLuminosity() public view returns(uint) {
        uint totalLuminosity = 0;
        for(uint i=0; i<_stars.length; i++) {
            if(_stars[i].totalMiningPlanets > 0) {
                totalLuminosity += _stars[i].luminosity;
            }
        }
        return totalLuminosity;
    }

    // Pulls token from the shadow pool, eventually internal function
    //PROBLEM: does not function - review 
    function requestToken() external onlyOwner{
        if (block.timestamp >= _rewardsTimer) {
            ShadowPool.replenishPlace(address(this), _rewardsMod);
            _rewardsTimer = block.timestamp + rewardsDelay;
            allocateToken();
        }
    }
    
    function addSalvageToPlace(uint _x, uint _y, uint _amount) external onlyEditor {
        //get place and add it to place
        _places[_coordinatePlaces[_x][_y]].salvage += _amount * 98 / 100;
        
    }

    // When Token allocated for salvage gets added to contract, call this function
    function increasePreviousBalance(uint _amount) external onlyEditor {
        previousBalance += _amount * 98 / 100;
    }

    // Function to mine, refine, transfer unrefined Token
    function allocateToken() public {
        uint newAmount = Token.balanceOf(address(this)) - previousBalance;
        if (newAmount > 0) {

            uint totalStarLuminosity = getTotalLuminosity();

            //loop through planets and add new token
            for(uint i=0; i<_planets.length; i++) {
                Planet memory planet = _planets[i];

                if(planet.isMiningPlanet) {
                    Star memory star = _stars[planet.starId];

                    uint newStarSystemToken = newAmount * (star.luminosity / totalStarLuminosity);

                    uint newMineral = newStarSystemToken;
                    //if more than one planet in star system
                    if(star.totalMiningPlanets > 1) {
                        newMineral = newStarSystemToken * (star.totalMiningPlanetDistance - planet.starDistance) /
                            (star.totalMiningPlanetDistance * (star.totalMiningPlanets - 1));
                    }
                    _planets[i].availableMineral += newMineral;
                }
            }
            previousBalance = Token.balanceOf(address(this));
        }
    }

    function getPlanetAtLocation(uint _x, uint _y) internal view returns (Planet memory) {
        Place memory place = _places[_coordinatePlaces[_x][_y]];
        require(Helper.isEqual(place.placeType, 'planet'), 'No planet found at this location.');
        return _planets[place.childId];
    }

    function getPlanetAtFleetLocation(address _sender) internal view returns (Planet memory) {
        (uint fleetX, uint fleetY) =  getFleetLocation(_sender);
        return getPlanetAtLocation(fleetX, fleetY);
    }

    function isRefineryLocation(uint _x, uint _y) external view returns (bool) {
        return getPlanetAtLocation(_x, _y).hasRefinery;
    }

    function isShipyardLocation(uint _x, uint _y) public view returns (bool) {
        return getPlanetAtLocation(_x, _y).hasShipyard;
    }

    //common implementation for any kind of mineral/salvage collection
    function _gather(address _player, uint _locationAmount, uint _coolDown) internal returns(uint) {
        require(_locationAmount > 0, 'MAP: no gather');
        require(_fleetMiningCooldown[_player] <= block.timestamp, 'MAP: gather on cooldown');

        uint availableCapacity = Fleet.getMaxMineralCapacity(_player) - _fleetMineral[_player]; //max amount of mineral fleet can carry minus what fleet already is carrying
        require(availableCapacity > 0, 'MAP: fleet cannot carry any more mineral');
        
        uint maxGather = Helper.getMin(availableCapacity, Fleet.getMiningCapacity(_player));
        uint gatheredAmount = Helper.getMin(_locationAmount, maxGather); //the less of fleet maxGather and how much amount place has

        _mineralGained(_player, int(gatheredAmount));
        _fleetMiningCooldown[_player] = block.timestamp + (_coolDown / _timeModifier);
        return gatheredAmount;
    }

    //collect salvage from a coordinate
    function collect(uint _x, uint _y) external {
        uint collectSpeedMultiplier = 5;
        _places[_coordinatePlaces[_x][_y]].salvage -= (
            _gather(msg.sender, _places[_coordinatePlaces[_x][_y]].salvage, _miningCooldown / collectSpeedMultiplier)
        );
    }
 
    //Fleet can mine mineral depending their fleet's capacity and planet available
    function mine() external {
        address player = msg.sender;
        Planet memory planet = getPlanetAtFleetLocation(player);
        require(isPaused[planet.placeId] != true, "MAP: mineral is paused");
        require(planet.availableMineral > 0, 'MAP: no mineral found');

        require(_fleetMiningCooldown[player] <= block.timestamp, 'MAP: mining on cooldown');

        uint availableCapacity = Fleet.getMaxMineralCapacity(player) - _fleetMineral[player]; //max amount of mineral fleet can carry minus what fleet already is carrying
        require(availableCapacity > 0, 'MAP: fleet cannot carry any more mineral');

        uint maxMine = Helper.getMin(availableCapacity, Fleet.getMiningCapacity(player));
        uint minedAmount = Helper.getMin(planet.availableMineral, maxMine); //the less of fleet maxMine and how much mineral planet has available

        _mineralGained(player, int(minedAmount));
        _fleetMiningCooldown[player] = block.timestamp + (_miningCooldown / _timeModifier);

        //requestToken();
        emit MineralMined(player, minedAmount);

        _planets[planet.id].availableMineral -= minedAmount;
    }
    
    function refine() external {
        address player = msg.sender;
        require(getPlanetAtFleetLocation(player).hasRefinery == true, "MAP: Fleet not at a refinery");

        uint playerMineral = _fleetMineral[player];
        require(playerMineral > 0, "MAP: Player/Fleet has no mineral");
        _fleetMineral[player] = 0;

        Token.safeTransfer(player, playerMineral);
        previousBalance -= playerMineral;
        emit MineralRefined(player, playerMineral);
        //requestToken();
    }

    function getFleetMineral(address _player) external view returns(uint) {
        return _fleetMineral[_player];
    }

    function mineralGained(address _player, int _amount) external {
        _mineralGained(_player, _amount);
    }

    // remember to set to onlyEditor
    // mineral gained can also be negative; used for player attacks and mining
    function _mineralGained(address _player, int _amount) internal {
        uint startAmount = _fleetMineral[_player];
        uint maxMineralCapacity = Fleet.getMaxMineralCapacity(_player);

        //add amount gained to current player amount
        //(this should never be less than 0 because mineral lost calculation should never take more than player has)
        //add check just in case the calc is wrong so final player amount is not negative and avoids overflow issues with uint
        //unless there is an error in previous code that calls this function, maxMineralAmount and newAmount should always be the same
        int maxMineralAmount = int(startAmount) + _amount;
        uint newAmount = 0;
        if(maxMineralAmount > 0) {
            newAmount = uint(maxMineralAmount);
        }

        //check new amount with max capacity, make sure it's not more than max capacity
        uint finalMineralAmount = Helper.getMin(maxMineralCapacity, newAmount);

        //burn whatever cannot fit into fleet mineral capacity
        uint burnedAmount = newAmount - finalMineralAmount;
        if(burnedAmount > 0) {
            Token.transfer(0x000000000000000000000000000000000000dEaD, burnedAmount);
        }

        //gained amount is the final amount - start amount (can be negative)
        int gainedAmount = int(finalMineralAmount) - int(startAmount);

        emit MineralGained(_player, gainedAmount, burnedAmount);
    }

    // Returns both x and y coordinates
    function getFleetLocation (address _fleet) public view returns(uint x, uint y) {
        return (fleetLocation[_fleet][0], fleetLocation[_fleet][1]);
    }

    function getFleetsAtLocation(uint _x, uint _y) external view returns(address[] memory) {
        return fleetsAtLocation[_x][_y];
    }

    function getDistanceFromFleet (address _fleet, uint _x, uint _y) public view returns(uint) {
        uint oldX = fleetLocation[_fleet][0];
        uint oldY = fleetLocation[_fleet][1];
        return Helper.getDistance(oldX, oldY, _x, _y);
    }

    function getFleetTravelCost(address _fleet, uint _x, uint _y) public view returns (uint) {
       uint fleetSize = Fleet.getFleetSize(_fleet);
       uint distance = getDistanceFromFleet(_fleet, _x, _y);
       return (distance**2 * _baseTravelCost * fleetSize) / Treasury.getCostMod();
    }

    function getFleetTravelCooldown(address _fleet, uint _x, uint _y) public view returns (uint) {
       uint distance = getDistanceFromFleet(_fleet, _x, _y);
       return _baseTravelCooldown + (distance*_travelCooldownPerDistance);
    }

    // ship travel to _x and _y
    function travel(uint _x, uint _y) external {
        address sender = msg.sender;
        require(block.timestamp >= _travelCooldown[sender], "MAPS: jump drive recharging");
        require(Fleet.isInBattle(sender) == false, "MAPS: in battle");
        require(Fleet.getFleetSize(sender) >= _minTravelSize, "MAPS: fleet too small for travel");

        uint distance = getDistanceFromFleet(sender, _x, _y);
        require(distance <= _maxTravel, "MAPS: cannot travel that far");

        uint travelCost = getFleetTravelCost(sender, _x, _y);
        Treasury.pay(sender, travelCost);

        _addTravelCooldown(sender, getFleetTravelCooldown(sender, _x, _y));

        (uint fleetX, uint fleetY) =  getFleetLocation(sender);
        address[] memory fleetsAtFromLocation = fleetsAtLocation[fleetX][fleetY]; //list of fleets at from location
        uint numFleetsAtLocation = fleetsAtFromLocation.length; //number of fleets at from location

        // PROBLEM: we need to remove this loop. Is there a reason we're storing fleets at location instead of just creating a function that returns this info?
        /* this loop goes through fleets at the player's "from" location and when it finds the fleet,
            it removes puts the last element in the array in that fleets place and then removes the last element */
        for(uint i=0;i<numFleetsAtLocation;i++) {
            if(fleetsAtFromLocation[i] == sender) {
                fleetsAtLocation[fleetX][fleetY][i] = fleetsAtLocation[fleetX][fleetY][numFleetsAtLocation-1]; //assign last element in array to where fleet was
                fleetsAtLocation[fleetX][fleetY].pop(); //remove last element in array
            }
        }

        //add fleet to new location fleet list
        fleetsAtLocation[_x][_y].push(sender);
        _setFleetLocation(sender, _x, _y);

        //if player travelled to a shipyard planet, set this planet as player's recall spot
        if(isShipyardLocation(_x, _y)) {
            _fleetLastShipyardPlace[sender] = _coordinatePlaces[_x][_y];
        }
    }

    function recall() external {
        require(Fleet.getFleetSize(msg.sender) < _minTravelSize, "FLEET: fleet too large for recall");
        _setFleetLocation(msg.sender, _places[_fleetLastShipyardPlace[msg.sender]].coordX, _places[_fleetLastShipyardPlace[msg.sender]].coordY);
    }

    //set travel cooldown or increase it
    function _addTravelCooldown(address _fleet, uint _seconds) internal {
        uint cooldownTime = _seconds / _timeModifier;
        if(_travelCooldown[_fleet] > block.timestamp) {
            _travelCooldown[_fleet] += cooldownTime;
        }
        else {
            _travelCooldown[_fleet] = block.timestamp + cooldownTime;
        }
    }

    function setFleetLocation(address _player, uint _x, uint _y) external onlyEditor {
        _setFleetLocation(_player, _x, _y);
    }

    function _setFleetLocation(address _player, uint _x, uint _y) internal {
        //change fleet location in fleet mapping
        fleetLocation[_player][0] = _x;
        fleetLocation[_player][1] = _y;
    }

    // Setting to 0 disables travel
    function setMaxTravel(uint _new) external onlyOwner {
        _maxTravel = _new;
    }    

    // Setting to 0 removes the secondary cooldown period
    function setTravelTimePerDistance(uint _new) external onlyOwner {
        _travelCooldownPerDistance = _new;
    }

    // setting to 0 removes base travel cooldown
    function setBaseTravelCooldown(uint _new) external onlyOwner {
        _baseTravelCooldown = _new;
    }

    // Functions to setup contract interfaces
    function setShadowPool(address _new) external onlyOwner {
        require(address(0) != _new);
        ShadowPool = IShadowPool(_new);
        emit NewShadowPool(_new);
    }
    function setFleet(address _new) external onlyOwner {
        require(address(0) != _new);
        Fleet = IFleet(_new); 
        emit NewFleet(_new);
    }
    function setToken(address _new) external onlyOwner {
        require(address(0) != _new);
        Token = ShibaBEP20(_new);
        emit NewToken(_new);
    }
    function setTreasury(address _new) external onlyOwner{
        require(address(0) != _new);
        Treasury = ITreasury(_new);
        emit NewTreasury(_new);
    }
    // Maintenance functions
    function setRewardsMod(uint _new) external onlyOwner {
        require(_new <= 100, "MAP: must be <= 100");
        _rewardsMod = _new; // can set to 0 to turn off Token incoming to contract
        emit NewRewardsMod(_new);
    }
    function setRewardsTimer(uint _new) external onlyOwner {
        _rewardsTimer = _new;
    }
    function setRewardsDelay(uint _new) external onlyOwner {
        rewardsDelay = _new;
    }
    // Pause unrefined token mining at a jackpot planet
    function setPaused(uint _id,bool _isPaused) external onlyOwner{
        isPaused[_id] = _isPaused;
    }
    function setBaseTravelCost(uint _new) external onlyOwner {
        _baseTravelCost = _new;
    }

    // setting to 0 removes base travel cooldown
    function setTimeModifier(uint _new) external onlyOwner {
        _timeModifier = _new;
    }
}

