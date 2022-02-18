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
       // Token = ShibaBEP20(0x9249DAcc91cddB8C67E9a89e02E071085dE613cE);
       // Treasury = ITreasury(0x0c5a18Eb2748946d41f1EBe629fF2ecc378aFE91);
        Fleet = IFleet(0xD7ACd2a9FD159E69Bb102A1ca21C9a3e3A5F771B);
       // ShadowPool = _shadowPool;

        _previousBalance = 0;
        _baseTravelCost = 10**15;
        _baseTravelCooldown = 2700; //45 minutes
        _travelCooldownPerDistance = 900; //15 minutes
        _maxTravel = 8; //AU
        _rewardsTimer = 0;
        _timeModifier = 25;
        _miningCooldown = 1800; //30 minutes
        _minTravelSize = 25;
        _collectCooldownReduction = 5;
        _asteroidCooldownReduction = 3;

        _addStar(2, 2, 'Alpha Centauri', 9); // first star
        _addPlanet(0, 0, 0, 'Haven', false, true, true); //Haven
        _addPlanet(0, 3, 4, 'Cetrus 22A', true, false, false); //unrefined planet
        _addPlanet(0, 1, 6, 'Cetrus 22B', true, false, false); //unrefined planet
    }

    ShibaBEP20 public Token; // TOKEN Token
    ITreasury public Treasury; //Contract that collects all Token payments
    IShadowPool public ShadowPool; //Contract that collects Token emissions
    IFleet public Fleet; // Fleet Contract

    uint public _previousBalance; // helper for allocating Token
    uint _rewardsMod; // = x/100, the higher the number the more rewards sent to this contract
    uint _rewardsTimer; // Rewards can only be pulled from shadow pool every 4 hours?
    uint rewardsDelay;
    uint  _timeModifier; //allow all times to be changed
    uint _miningCooldown; // how long before 
    uint _minTravelSize; //min. fleet size required to travel
    uint _collectCooldownReduction;
    uint _asteroidCooldownReduction;

    // Fleet Info and helpers
    mapping (address => uint[2]) fleetLocation; //address to [x,y] array
    mapping(uint => mapping (uint => address[])) fleetsAtLocation; //reverse index to see what fleets are at what location

    mapping (address => uint) public travelCooldown; // limits how often fleets can travel
    mapping (address => uint) public fleetMiningCooldown; // limits how often a fleet can mine mineral
    mapping (address => uint) public fleetLastShipyardPlace; // last shipyard place that fleet visited
    
    uint _baseTravelCooldown; 
    uint _travelCooldownPerDistance; 
    uint _baseTravelCost; // Token cost to travel 1 AU
    uint _maxTravel; // max distance a fleet can travel in 1 jump

    enum PlaceType{ EMPTY, HOSTILE, STAR, PLANET, ASTEROID, WORMHOLE }

    struct Place {
        uint id; //native key 
        PlaceType placeType;
        uint childId;
        uint coordX;
        uint coordY;
        string name;
        uint salvage;
        address discoverer;
        bool canTravel;
    }
    Place[] _places;
    mapping (uint => mapping(uint => bool)) _placeExists;
    mapping (uint => mapping(uint => uint)) _coordinatePlaces;

    struct PlaceGetter {
        string name;
        PlaceType placeType;
        uint salvage;
        uint fleetCount;
        bool hasRefinery;
        bool hasShipyard;
        uint availableMineral;
        bool canTravel;
        uint luminosity;
        bool isMiningPlanet;
    }

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

    struct Asteroid {
        uint id;
        uint placeId;
        uint availableMineral;
    }
    Asteroid[] _asteroids;

    event NewShadowPool(address _new);
    event NewFleet(address _new);
    event NewToken(address _new);
    event NewTreasury(address _new);
    event NewRewardsMod(uint _new);
    event MineralGained(address _player, int _amountGained, uint _amountBurned);
    event MineralTransferred(address _from, address _to, uint _amountSent, uint _amountReceived, uint _amountBurned);
    event MineralRefined(address _fleet, uint _amount);
    event MineralGathered(address _fleet, uint _amount);
    event NewPlanet(uint _star, uint _x, uint _y);
    event NewStar(uint _x, uint _y);

    function _addPlace(PlaceType _placeType, uint _childId, uint _x, uint _y, string memory _name, bool _canTravel) internal {
        require(_placeExists[_x][_y] == false, 'Place already exists');
        uint placeId = _places.length;
        _places.push(Place(placeId, _placeType, _childId, _x, _y, _name, 0, 0xd9145CCE52D386f254917e481eB44e9943F39138, _canTravel));

        //set place in coordinate mapping
        _placeExists[_x][_y] = true;
        _coordinatePlaces[_x][_y] = placeId;
    }

    function _addEmpty(uint _x, uint _y) internal {
        _addPlace(PlaceType.EMPTY, 0, _x, _y, '', true);
    }

    function _addHostile(uint _x, uint _y) internal {
        _addPlace(PlaceType.HOSTILE, 0, _x, _y, '', false);
    }

    function _addAsteroid(uint _x, uint _y, uint _amount) internal {
        uint asteroidId = _asteroids.length;
        _asteroids.push(Asteroid(asteroidId, _places.length, _amount));
        _addPlace(PlaceType.ASTEROID, 0, _x, _y, '', true);
    }

    function _addStar(uint _x, uint _y, string memory _name, uint _luminosity) internal {
        //add star to stars list
        uint starId = _stars.length;
        _stars.push(Star(starId, _places.length, _luminosity, 0, 0));

        _addPlace(PlaceType.STAR, starId, _x, _y, _name, false);
        emit NewStar(_x, _y);
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

        _addPlace(PlaceType.PLANET, planetId, _x, _y, _name, true);
        emit NewPlanet(_starId, _x, _y);
    }

    function getExploreCost(uint _x, uint _y) public view returns(uint) {
        return Helper.getDistance(0, 0, _x, _y) * 2 * 10**19 / Treasury.getCostMod();
    }

    //player explore function
    function explore(uint _x, uint _y) external {
        address sender = msg.sender;
        require(getDistanceFromFleet(sender, _x, _y) == 1, "MAPS: explore too far");
        uint exploreCost = getExploreCost(_x, _y);
        Treasury.pay(sender, exploreCost);
        Fleet.addExperience(sender, exploreCost);
        _createRandomPlaceAt(_x, _y, sender);
    }

    //create a random place at given coordinates
    function _createRandomPlaceAt(uint _x, uint _y, address _creator) internal {
        require(_placeExists[_x][_y] == false, 'Place already exists');
        uint rand = Helper.getRandomNumber(100, _x + _y);
        if(rand >= 10 && rand <= 30) {
           _addHostile(_x, _y); 
        }
        else if(rand >= 31 && rand <= 54) {
            uint asteroidPercent = Helper.getRandomNumber(8, _x + _y) + 2;
            uint asteroidAmount = (asteroidPercent * Token.balanceOf(address(Treasury))) / 100;
            _previousBalance += asteroidAmount;
            Token.safeTransferFrom(address(Treasury), address(this), asteroidAmount); //send asteroid NOVA to Map contract
            _addAsteroid(_x, _y, 98 * asteroidAmount / 100);
        }
        else if(rand >= 55 && rand <= 99) {
            uint nearestStar = _getNearestStar(_x, _y);
            uint nearestStarX = _places[_stars[nearestStar].placeId].coordX;
            uint nearestStarY = _places[_stars[nearestStar].placeId].coordY;

            //new planet must be within 3 AU off nearest star
            if(rand >= 55 && rand <= 73 && Helper.getDistance(_x, _y, nearestStarX, nearestStarY) <= 3) {
                bool isMiningPlanet = false;
                bool hasShipyard = false;
                bool hasRefinery = false;
                uint planetAttributeSelector = Helper.getRandomNumber(20, rand);
                if(planetAttributeSelector <= 8) {
                    isMiningPlanet = true;
                }
                else if(planetAttributeSelector >= 9 && planetAttributeSelector <=11) {
                    hasRefinery = true;
                }
                else if(planetAttributeSelector >= 12 && planetAttributeSelector <= 18) {
                    hasShipyard = true;
                }
                else { hasShipyard = true; hasRefinery = true; }
                _addPlanet(nearestStar, _x, _y, '', isMiningPlanet, hasRefinery, hasShipyard);

                //if planet has a shipyard, add shipyard to Fleet contract
                if(hasShipyard == true) {
                    uint8 feePercent;
                    address placeOwner;
                    if(hasRefinery != true) {
                        feePercent = 5;
                        placeOwner = _creator;
                    }
                    Fleet.addShipyard(placeOwner, _x, _y, feePercent);
                }

            }
            //new star must be more than 7 AU away from nearest star
            else if(rand >= 74 && Helper.getDistance(_x, _y, nearestStarX, nearestStarY) > 7) {
                _addStar(_x, _y, '', Helper.getRandomNumber(9, rand) + 1);
            }
            else {
                _addEmpty(_x, _y);
            }
        }
        else {
           _addEmpty(_x, _y);
        }
    }

    function changeName(uint _x, uint _y, string memory _name) external {
        Place storage namePlace = _places[_coordinatePlaces[_x][_y]];
        require(msg.sender == namePlace.discoverer, 'MAP: not discoverer');
        require(Helper.isEqual(namePlace.name, ""), 'MAP: already named');
        namePlace.name = _name;
    }

    function _getNearestStar(uint _x, uint _y) internal view returns(uint) {
        uint nearestStar;
        uint nearestStarDistance;
        for(uint i=0; i<_stars.length; i++) {
            uint starDistance = Helper.getDistance(_x, _y, _places[_stars[i].placeId].coordX, _places[_stars[i].placeId].coordY);
            if(nearestStarDistance == 0 || starDistance < nearestStarDistance) {
                nearestStar = i;
                nearestStarDistance = starDistance;
            }
        }
        return nearestStar;
    }

    function getCoordinatePlaces(uint _lx, uint _ly) external view returns(PlaceGetter[] memory) {
        PlaceGetter[] memory foundCoordinatePlaces = new PlaceGetter[](49);

        uint counter = 0;
        for(uint j=_ly+7; j>=_ly; j--) {
            for(uint i=_lx; i<=_lx+6; i++) {
                PlaceGetter memory placeGetter;

                if(_placeExists[i][j] == true) {
                    Place memory place = _places[_coordinatePlaces[i][j]];
                    placeGetter.canTravel = place.canTravel;
                    placeGetter.name = place.name; 
                    placeGetter.placeType = place.placeType;
                    placeGetter.salvage = place.salvage;
                    placeGetter.fleetCount = fleetsAtLocation[i][j].length;

                    if(place.placeType == PlaceType.PLANET) {
                        placeGetter.hasRefinery =  _planets[place.childId].hasRefinery;
                        placeGetter.hasShipyard = _planets[place.childId].hasShipyard;
                        placeGetter.availableMineral = _planets[place.childId].availableMineral;
                        placeGetter.isMiningPlanet = _planets[place.childId].isMiningPlanet;
                    }
                    else if(place.placeType == PlaceType.STAR) {
                        placeGetter.luminosity = _stars[place.childId].luminosity;
                    }
                    else if(place.placeType == PlaceType.ASTEROID) {
                        placeGetter.availableMineral = _asteroids[place.childId].availableMineral;
                    }
                }
                foundCoordinatePlaces[counter] = placeGetter;
                counter++;
            }
        }
        return foundCoordinatePlaces;
    }

    function _getCoordinatePlace(uint _x, uint _y) internal view returns (Place memory) {
        return _places[_coordinatePlaces[_x][_y]];
    }

    function getPlaceId(uint _x, uint _y) public view returns (uint) {
        return (_coordinatePlaces[_x][_y]);
    }

    function getPlaceName(uint _x, uint _y) external view returns(string memory) {
        return _places[getPlaceId(_x, _y)].name;
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
    function _requestToken() internal {
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
        _previousBalance += _amount * 98 / 100;
    }

    // Function to mine, refine, transfer unrefined Token
    function allocateToken() public {
        uint newAmount = Token.balanceOf(address(this)) - _previousBalance;
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
            _previousBalance = Token.balanceOf(address(this));
        }
    }

    function getPlanetAtLocation(uint _x, uint _y) internal view returns (Planet memory) {
        Planet memory planet;
        Place memory place = _places[_coordinatePlaces[_x][_y]];
        if(place.placeType == PlaceType.PLANET) {
            planet = _planets[place.childId];
        }
        return planet;
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

    //shared core implementation for any kind of mineral/salvage collection
    function _gather(address _player, uint _locationAmount, uint _coolDown) internal returns(uint) {
        require(_locationAmount > 0, 'MAP: nothing to gather');
        require(fleetMiningCooldown[_player] <= block.timestamp, 'MAP: gather on cooldown');

        uint availableCapacity = Fleet.getMineralCapacity(_player) - Fleet.getMineral(_player); //max amount of mineral fleet can carry minus what fleet already is carrying
        require(availableCapacity > 0, 'MAP: fleet max capacity');
        
        uint maxGather = Helper.getMin(availableCapacity, Fleet.getMiningCapacity(_player));
        uint gatheredAmount = Helper.getMin(_locationAmount, maxGather); //the less of fleet maxGather and how much amount place has

        Fleet.setMineral(_player, Fleet.getMineral(_player) + gatheredAmount);
        fleetMiningCooldown[_player] = block.timestamp + (_coolDown / _timeModifier);

        emit MineralGathered(_player, gatheredAmount);
        return gatheredAmount;
    }

    //collect salvage from a coordinate
    function collect() external {
        (uint fleetX, uint fleetY) = getFleetLocation(msg.sender);
        require(_placeExists[fleetX][fleetY] == true, 'MAPS: no place');
        _places[_coordinatePlaces[fleetX][fleetY]].salvage -=
            _gather(msg.sender, _places[_coordinatePlaces[fleetX][fleetY]].salvage, _miningCooldown / _collectCooldownReduction);
    }
 
    //Fleet can mine mineral depending their fleet's capacity and planet available
    function mine() external {
        (uint fleetX, uint fleetY) = getFleetLocation(msg.sender);
        require(_placeExists[fleetX][fleetY] == true, 'MAPS: no place');
        Place memory miningPlace = _places[_coordinatePlaces[fleetX][fleetY]];

        //if mining a planet
        if(miningPlace.placeType == PlaceType.PLANET) {
            Planet memory miningPlanet = _planets[miningPlace.childId];
            _planets[miningPlanet.id].availableMineral -=
                _gather(msg.sender, miningPlanet.availableMineral, _miningCooldown);
        }
        //else if mining an asteroid
        else if(miningPlace.placeType == PlaceType.ASTEROID) {
            Asteroid memory miningAsteroid = _asteroids[miningPlace.childId];
            _asteroids[miningAsteroid.id].availableMineral -=
                _gather(msg.sender, miningAsteroid.availableMineral, _miningCooldown / _asteroidCooldownReduction);
        }
        _requestToken();
    }
    
    function refine() external {
        address player = msg.sender;
        require(getPlanetAtFleetLocation(player).hasRefinery == true, "MAP: Fleet not at a refinery");

        uint playerMineral = Fleet.getMineral(player);
        require(playerMineral > 0, "MAP: Player/Fleet has no mineral");
        Fleet.setMineral(player, 0);

        Token.safeTransfer(player, playerMineral);
        _previousBalance -= playerMineral;
        emit MineralRefined(player, playerMineral);
        _requestToken();
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

       //Every 1000 experience, travel is reduced by 1% up to 50%
       uint travelDiscount = Helper.getMin(50, Fleet.getExperience(_fleet) / 1000);
       return ((distance**2 * _baseTravelCost * fleetSize) * ((100-travelDiscount) / 100)) / Treasury.getCostMod();
    }

    function getFleetTravelCooldown(address _fleet, uint _x, uint _y) public view returns (uint) {
       uint distance = getDistanceFromFleet(_fleet, _x, _y);
       return _baseTravelCooldown + (distance*_travelCooldownPerDistance);
    }

    // ship travel to _x and _y
    function travel(uint _x, uint _y) external {
        require(_placeExists[_x][_y] == true, 'MAPS: place unexplored');
        require(_places[_coordinatePlaces[_x][_y]].canTravel == true, 'MAPS: no travel');
        address sender = msg.sender;
        require(block.timestamp >= travelCooldown[sender], "MAPS: jump drive recharging");
        require(getDistanceFromFleet(sender, _x, _y) <= _maxTravel, "MAPS: cannot travel that far");
        require(Fleet.getFleetSize(sender) >= _minTravelSize, "MAPS: fleet too small");
        require(Fleet.isInBattle(sender) == false, "MAPS: in battle or takeover");

        uint travelCost = getFleetTravelCost(sender, _x, _y);
        Treasury.pay(sender, travelCost);
        Fleet.addExperience(sender, travelCost);

        _addTravelCooldown(sender, getFleetTravelCooldown(sender, _x, _y));

        (uint fleetX, uint fleetY) =  getFleetLocation(sender);
        _setFleetLocation(sender, fleetX, fleetY, _x, _y);
    }

    //player can set recall spot if at a shipyard
    function setRecall(uint _x, uint _y) external {
        (uint fleetX, uint fleetY) =  getFleetLocation(msg.sender);
        require(isShipyardLocation(fleetX, fleetY) == true, 'MAP: no shipyard');
        fleetLastShipyardPlace[msg.sender] = _coordinatePlaces[_x][_y];
    }

    //set travel cooldown or increase it
    function _addTravelCooldown(address _fleet, uint _seconds) internal {
        uint cooldownTime = _seconds / _timeModifier;
        if(travelCooldown[_fleet] > block.timestamp) {
            travelCooldown[_fleet] += cooldownTime;
        }
        else {
            travelCooldown[_fleet] = block.timestamp + cooldownTime;
        }
    }

    //recall player to last shipyard visited
    function recall(bool _goToHaven) external {
        require(Fleet.getFleetSize(msg.sender) < _minTravelSize, "FLEET: too large for recall");

        uint recallX;
        uint recallY;
        if(_goToHaven != true) {
            recallX = _places[fleetLastShipyardPlace[msg.sender]].coordX;
            recallY = _places[fleetLastShipyardPlace[msg.sender]].coordY;
        }

        (uint fleetX, uint fleetY) =  getFleetLocation(msg.sender);
        _setFleetLocation(msg.sender, fleetX, fleetY, recallX, recallY);
    }

    function setFleetLocation(address _player, uint _xFrom, uint _yFrom, uint _xTo, uint _yTo) external onlyEditor {
        _setFleetLocation(_player, _xFrom, _yFrom, _xTo, _yTo);
    }

    //change fleet location in fleet mapping
    function _setFleetLocation(address _player, uint _xFrom, uint _yFrom, uint _xTo, uint _yTo) internal {
        address[] memory fleetsAtFromLocation = fleetsAtLocation[_xFrom][_yFrom]; //list of fleets at from location
        uint numFleetsAtLocation = fleetsAtFromLocation.length; //number of fleets at from location
        /* this loop goes through fleets at the player's "from" location and when it finds the fleet,
            it removes puts the last element in the array in that fleets place and then removes the last element */
        for(uint i=0;i<numFleetsAtLocation;i++) {
            if(fleetsAtFromLocation[i] == _player) {
                fleetsAtLocation[_xFrom][_yFrom][i] = fleetsAtLocation[_xFrom][_yFrom][numFleetsAtLocation-1]; //assign last element in array to where fleet was
                fleetsAtLocation[_xFrom][_yFrom].pop(); //remove last element in array
            }
        }

        //add fleet to new location fleet list
        fleetsAtLocation[_xTo][_yTo].push(_player);
        fleetLocation[_player][0] = _xTo;
        fleetLocation[_player][1] = _yTo;
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
    function setBaseTravelCost(uint _new) external onlyOwner {
        _baseTravelCost = _new;
    }

    // setting to 0 removes base travel cooldown
    function setTimeModifier(uint _new) external onlyOwner {
        _timeModifier = _new;
    }

    function getTimeModifier() external view returns(uint) {
        return _timeModifier;
    }
}