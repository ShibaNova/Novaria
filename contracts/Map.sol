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
        _maxTravel = 10; //AU
        _rewardsTimer = 0;
        _timeModifier = 50;
        _miningCooldown = 1800; //30 minutes
        _minTravelSize = 25;
        _collectCooldownReduction = 5;
        _asteroidCooldownReduction = 3;

        _placeTypes.push('empty');
        _placeTypes.push('hostile');
        _placeTypes.push('star');
        _placeTypes.push('planet');
        _placeTypes.push('asteroid');

        _addStar(2, 2, 'Solar', 9); // first star
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
    mapping (uint => bool) isPaused; // can pause token mining for mining planets
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

    string[] _placeTypes; // list of placeTypes

    struct Place {
        uint id; //native key 
        string placeType;
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
        string placeType;
        uint salvage;
        uint fleetCount;
        bool hasRefinery;
        bool hasShipyard;
        uint availableMineral;
        bool canTravel;
        uint luminosity;
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

    function _addPlace(string memory _placeType, uint _childId, uint _x, uint _y, string memory _name, bool _canTravel) internal {
        require(_placeExists[_x][_y] == false, 'Place already exists');
        uint placeId = _places.length;
        _places.push(Place(placeId, _placeType, _childId, _x, _y, _name, 0, 0xd9145CCE52D386f254917e481eB44e9943F39138, _canTravel));

        //set place in coordinate mapping
        _placeExists[_x][_y] = true;
        _coordinatePlaces[_x][_y] = placeId;
    }

    function _addEmpty(uint _x, uint _y) internal {
        _addPlace('empty', 0, _x, _y, '', true);
    }

    function _addHostile(uint _x, uint _y) internal {
        _addPlace('hostile', 0, _x, _y, '', false);
    }

    function _addAsteroid(uint _x, uint _y, uint _amount) internal {
        uint asteroidId = _asteroids.length;
        _asteroids.push(Asteroid(asteroidId, _places.length, _amount));
        _addPlace('asteroid', 0, _x, _y, '', true);
    }

    function _addStar(uint _x, uint _y, string memory _name, uint _luminosity) internal {
        //add star to stars list
        uint starId = _stars.length;
        _stars.push(Star(starId, _places.length, _luminosity, 0, 0));

        _addPlace('star', starId, _x, _y, _name, false);
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

        _addPlace('planet', planetId, _x, _y, _name, true);
        emit NewPlanet(_starId, _x, _y);
    }

    function getExploreCost(uint _x, uint _y) public view returns(uint) {
        return Helper.getDistance(0, 0, _x, _y) * 4 * 10**19 / Treasury.getCostMod();
    }

    //player explore function
    function explore(uint _x, uint _y) external {
        address sender = msg.sender;
        require(getDistanceFromFleet(sender, _x, _y) == 1, "MAPS: explore too far");
        uint exploreCost = getExploreCost(_x, _y);
        Treasury.pay(sender, exploreCost);
        Fleet.addExperience(sender, exploreCost);
        _createRandomPlaceAt(_x, _y, sender);
        //8, 6; distance = sqrt(100) = 10AU = 500 NOVA
    }

    //create a random place at given coordinates
    function _createRandomPlaceAt(uint _x, uint _y, address _creator) internal {
        require(_placeExists[_x][_y] == false, 'Place already exists');
        uint rand = Helper.getRandomNumber(100, _x + _y);
        if(rand >= 50 && rand <= 69) {
           _addHostile(_x, _y); 
        }
        else if(rand >= 70 && rand <= 79) {
            uint asteroidPercent = Helper.getRandomNumber(8, _x + _y) + 2;
            uint asteroidAmount = (asteroidPercent * Token.balanceOf(address(Treasury))) / 100;
            _previousBalance += asteroidAmount;
            Token.safeTransferFrom(address(Treasury), address(this), asteroidAmount); //send asteroid NOVA to Map contract
            _addAsteroid(_x, _y, 98 * asteroidAmount / 100);
        }
        else if(rand >= 80 && rand <= 99) {
            uint nearestStar = _getNearestStar(_x, _y);
            uint nearestStarX = _places[_stars[nearestStar].placeId].coordX;
            uint nearestStarY = _places[_stars[nearestStar].placeId].coordY;

            //new planet must be within 3 AU off nearest star
            if(rand >= 79 && rand <= 94 && Helper.getDistance(_x, _y, nearestStarX, nearestStarY) <= 3) {
                bool isMiningPlanet = false;
                bool hasShipyard = false;
                bool hasRefinery = false;
                uint planetAttributeSelector = Helper.getRandomNumber(20, rand);
                if(planetAttributeSelector <= 10) {
                    isMiningPlanet = true;
                }
                else if(planetAttributeSelector >= 11 && planetAttributeSelector <=13) {
                    hasRefinery = true;
                }
                else if(planetAttributeSelector >= 14 && planetAttributeSelector <= 18) {
                    hasShipyard = true;
                }
                else { hasShipyard = true; hasRefinery = true; }
                _addPlanet(nearestStar, _x, _y, 'planet', isMiningPlanet, hasRefinery, hasShipyard);

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
            else if(rand >= 95 && Helper.getDistance(_x, _y, nearestStarX, nearestStarY) > 7) {
                _addStar(_x, _y, 'star', Helper.getRandomNumber(9, rand) + 1);
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
        require(Helper.isEqual(namePlace.name, namePlace.placeType), 'MAP: already named');
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

    /* get coordinatePlaces cannot handle a map box larger than 255 */
    function getCoordinatePlaces(uint _lx, uint _ly, uint _rx, uint _ry) external view returns(PlaceGetter[] memory) {
        uint xDistance = (_rx - _lx) + 1;
        uint yDistance = (_ry - _ly) + 1;
        uint numCoordinates = xDistance * yDistance;
        require(xDistance * yDistance < 256, 'MAP: Too much data in loop');

        PlaceGetter[] memory foundCoordinatePlaces = new PlaceGetter[]((numCoordinates));

        uint counter = 0;
        for(uint i=_lx; i<=_rx;i++) {
            for(uint j=_ly; j<=_ry;j++) {
                PlaceGetter memory placeGetter;

                if(_placeExists[i][j] == true) {
                    Place memory place = _places[_coordinatePlaces[i][j]];
                    placeGetter.canTravel = place.canTravel;
                    placeGetter.name = place.name; 
                    placeGetter.placeType = place.placeType;
                    placeGetter.salvage = place.salvage;
                    placeGetter.fleetCount = fleetsAtLocation[i][j].length;

                    if(Helper.isEqual(place.placeType, 'planet')) {
                        placeGetter.hasRefinery =  _planets[place.childId].hasRefinery;
                        placeGetter.hasShipyard = _planets[place.childId].hasShipyard;
                        placeGetter.availableMineral = _planets[place.childId].availableMineral;
                    }
                    if(Helper.isEqual(place.placeType, 'star')) {
                        placeGetter.luminosity = _stars[place.childId].luminosity;
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

    //three different return statements to avoid stack too deep error
    function getCoordinateInfo(uint _x, uint _y) external view returns (string memory, string memory, uint, bool, bool, uint, uint, bool) {
        
        if(_placeExists[_x][_y] == true) {
            Place memory place  = _places[_coordinatePlaces[_x][_y]];
            uint fleetCount = fleetsAtLocation[_x][_y].length;
            if(Helper.isEqual(place.placeType, 'planet')) {
                return(place.name, place.placeType, place.salvage,
                _planets[place.childId].hasShipyard, _planets[place.childId].hasRefinery, _planets[place.childId].availableMineral, fleetCount, _planets[place.childId].isMiningPlanet);
            }
            return(place.name, place.placeType, place.salvage, false, false, 0, fleetCount, false);
        }
        return ("", "", 0, false, false, 0, 0, false);
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
        if(Helper.isEqual(place.placeType, 'planet')) {
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

        _mineralGained(_player, int(gatheredAmount));
        fleetMiningCooldown[_player] = block.timestamp + (_coolDown / _timeModifier);

        //requestToken();
        emit MineralGathered(_player, gatheredAmount);
        return gatheredAmount;
    }

    //collect salvage from a coordinate
    function collect(uint _x, uint _y) external {
        _places[_coordinatePlaces[_x][_y]].salvage -=
            _gather(msg.sender, _places[_coordinatePlaces[_x][_y]].salvage, _miningCooldown / _collectCooldownReduction);
    }
 
    //Fleet can mine mineral depending their fleet's capacity and planet available
    function mine() external {
        (uint fleetX, uint fleetY) = getFleetLocation(msg.sender);
        require(_placeExists[fleetX][fleetY] == true, 'MAPS: no place');
        Place memory miningPlace = _places[_coordinatePlaces[fleetX][fleetY]];

        //if mining a planet
        if(Helper.isEqual(miningPlace.placeType, "planet")) {
            Planet memory miningPlanet = _planets[miningPlace.childId];
            require(isPaused[miningPlanet.placeId] != true, "MAP: mineral is paused");
            _planets[miningPlanet.id].availableMineral -=
                _gather(msg.sender, miningPlanet.availableMineral, _miningCooldown);
        }

        //if mining an asteroid
        else if(Helper.isEqual(miningPlace.placeType, "asteroid")) {
            Asteroid memory miningAsteroid = _asteroids[miningPlace.childId];
            _asteroids[miningAsteroid.id].availableMineral -=
                _gather(msg.sender, miningAsteroid.availableMineral, _miningCooldown / _asteroidCooldownReduction);
        }
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
        //requestToken();
    }

    // mineral gained can also be negative; used for player attacks and mining
    function _mineralGained(address _player, int _amount) internal {
        uint startAmount = Fleet.getMineral(_player);

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
        uint finalMineralAmount = uint(Helper.getMin(Fleet.getMineralCapacity(_player), newAmount));

        //set player's mineral
        Fleet.setMineral(_player, finalMineralAmount);

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

       //Every 1000 experience, travel is reduced by 1% up to 50%
       uint travelDiscount = Helper.getMin(50, Fleet.getExperience(_fleet) / 1000);
       return ((distance**2 * _baseTravelCost * fleetSize) * ((100-travelDiscount) / 100)) / Treasury.getCostMod();
    }

    function getFleetTravelCooldown(address _fleet, uint _x, uint _y) public view returns (uint) {
       uint distance = getDistanceFromFleet(_fleet, _x, _y);
       return _baseTravelCooldown + (distance*_travelCooldownPerDistance);
    }

    function getCurrentTravelCooldown (address _fleet) external view returns(uint) {
        return travelCooldown[_fleet];
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

        //if player travels from a shipyard planet, set this planet as player's recall spot
        if(isShipyardLocation(fleetX, fleetY)) {
            fleetLastShipyardPlace[sender] = _coordinatePlaces[_x][_y];
        }
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
        (uint fleetX, uint fleetY) =  getFleetLocation(msg.sender);

        uint recallX;
        uint recallY;
        if(_goToHaven != true) {
            uint shipyardX = _places[fleetLastShipyardPlace[msg.sender]].coordX;
            uint shipyardY = _places[fleetLastShipyardPlace[msg.sender]].coordY;
            if(isShipyardLocation(shipyardX, shipyardY)) {
                recallX = shipyardX;
                recallY = shipyardY;
            }
        }

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

    function getTimeModifier() external view returns(uint) {
        return _timeModifier;
    }
}