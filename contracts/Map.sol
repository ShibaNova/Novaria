// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import './libs/Editor.sol';
import './libs/Helper.sol';
import './libs/ShibaBEP20.sol';
import './libs/SafeBEP20.sol';
import "./interfaces/ITreasury.sol";
import "./interfaces/IShadowPool.sol";
import "./interfaces/IFleet.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract Map is Editor {
    using SafeBEP20 for ShibaBEP20;

    constructor (
         ShibaBEP20 _token,
         ITreasury _treasury
        //IShadowPool _shadowPool,
        //IFleet _fleet
    ) {
        //Token = ShibaBEP20(0xd9145CCE52D386f254917e481eB44e9943F39138);
         //Treasury = ITreasury(0xd8b934580fcE35a11B58C6D73aDeE468a2833fa8);
         Token = _token;
         Treasury = _treasury;
        //Fleet = IFleet(0xD7ACd2a9FD159E69Bb102A1ca21C9a3e3A5F771B);
        ShadowPool = IShadowPool(0x0c5a18Eb2748946d41f1EBe629fF2ecc378aFE91);

        previousBalance = 0;
        _baseTravelCost = 10**15;
        _baseTravelCooldown = 2700; //45 minutes
        _travelCooldownPerDistance = 900; //15 minutes
        _maxTravel = 5; //AU
        _rewardsTimer = 0;
        _timeModifier = 1;
        _miningCooldown = 3600; //30 minutes
        _minTravelSize = 25;
        _collectCooldownReduction = 5;
        _asteroidCooldownReduction = 3;
    }

    ShibaBEP20 public Token; // TOKEN Token
    ITreasury public Treasury; //Contract that collects all Token payments
    IShadowPool public ShadowPool; //Contract that collects Token emissions
    IFleet public Fleet; // Fleet Contract

    uint public previousBalance; // helper for allocating Token
    uint _rewardsMod; // = x/100, the higher the number the more rewards sent to this contract
    uint _rewardsTimer; // Rewards can only be pulled from shadow pool every 4 hours?
    uint public rewardsDelay;
    uint  _timeModifier; //allow all times to be changed
    uint _miningCooldown; // how long before 
    uint _minTravelSize; //min. fleet size required to travel
    uint _collectCooldownReduction;
    uint _asteroidCooldownReduction;

    // Fleet Info and helpers
    mapping (address => uint[2]) fleetLocation; //address to [x,y] array
    mapping(uint => mapping (uint => address[])) fleetsAtLocation; //reverse index to see what fleets are at what location

    mapping (address => uint) public fleetTravelCooldown; // limits how often fleets can travel
    mapping (address => uint) public fleetMiningCooldown; // limits how often a fleet can mine mineral
    mapping (address => uint) public fleetLastShipyardPlace; // last shipyard place that fleet visited
    mapping (address => uint) public fleetMineralRefined; // last shipyard place that fleet visited
    
    uint _baseTravelCooldown; 
    uint _travelCooldownPerDistance; 
    uint _baseTravelCost; // Token cost to travel 1 AU
    uint _maxTravel; // max distance a fleet can travel in 1 jump

    enum PlaceType{ UNEXPLORED, EMPTY, HOSTILE, STAR, PLANET, ASTEROID, WORMHOLE }

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
        uint activeBattleCount;
    }
    Place[] public places;
    mapping (uint => mapping(uint => bool)) _placeExists;
    mapping (uint => mapping(uint => uint)) public coordinatePlaces;

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
        address discoverer;
        uint activeBattleCount;
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

    struct Wormhole {
        uint id;
        uint placeId;
    }
    Wormhole[] _wormholes;

    event NewShadowPool(address _new);
    event NewFleet(address _new);
    event NewToken(address _new);
    event NewTreasury(address _new);
    event NewRewardsMod(uint _new);
    event MineralRefined(address _fleet, uint _amount);
    event MineralGathered(address _fleet, uint _amount);
    event NewPlanet(uint _star, uint _x, uint _y);
    event NewStar(uint _x, uint _y);

    function startingPlaces() external {
        _addStar(2, 2, 'Alpha Centauri', 9); // first star
        _addPlanet(0, 0, 0, 'Haven', false, true, true); //Haven
        _addHostile(0, 1);
        _addEmpty(1, 0);
        _addEmpty(2, 0);
        _addPlanet(0, 3, 0, 'Cetrus 22A', true, false, false); //mining planet

        _addHostile(1, 2);
        _addHostile(1, 4);
        _addHostile(2, 1);
        _addEmpty(2, 3);
        _addWormhole(3, 2); // wormhole
        _addHostile(2, 4);
        _addHostile(3, 4);
        _addPlanet(0, 4, 5, 'Cetrus 22B', true, false, false); //mining planet
        _addPlanet(0, 5, 4, 'Gallifrey', false, false, true); //shipyard planet

        _addStar(14, 14, 'Rigel', 3); // first star
        _addWormhole(8, 20); // wormhole
        _addPlanet(1, 12, 12, 'Caprica', true, false, false); //mining planet
        _addPlanet(1, 15, 17, 'Chemicals R US', false, true, false); //refinery planet
    }

    function _addPlace(PlaceType _placeType, uint _childId, uint _x, uint _y, string memory _name, bool _canTravel) internal {
        require(_placeExists[_x][_y] == false, 'Place already exists');
        uint placeId = places.length;
        places.push(Place(placeId, _placeType, _childId, _x, _y, _name, 0, tx.origin, _canTravel, 0));

        //set place in coordinate mapping
        _placeExists[_x][_y] = true;
        coordinatePlaces[_x][_y] = placeId;
    }

    function _addEmpty(uint _x, uint _y) internal {
        _addPlace(PlaceType.EMPTY, 0, _x, _y, '', true);
    }

    function _addHostile(uint _x, uint _y) internal {
        _addPlace(PlaceType.HOSTILE, 0, _x, _y, '', false);
    }

    function _addWormhole(uint _x, uint _y) internal {
        uint wormholeId = _wormholes.length;
        _wormholes.push(Wormhole(wormholeId, places.length));
        _addPlace(PlaceType.WORMHOLE, wormholeId, _x, _y, '', true);
    }

    function getWormholes() external view returns(Wormhole[] memory) {
        return _wormholes;
    }

    function _addAsteroid(uint _x, uint _y, uint _percent) internal {
        uint asteroidId = _asteroids.length;
        uint asteroidAmount = (_percent * Treasury.getAvailableAmount()) / 100;
        Token.safeTransferFrom(address(Treasury), address(this), asteroidAmount); //send asteroid NOVA to Map contract

        uint amountAfterBurn = (98 * asteroidAmount) / 100; //subtract 2% for burn
        previousBalance += amountAfterBurn;
        _asteroids.push(Asteroid(asteroidId, places.length, amountAfterBurn));
        _addPlace(PlaceType.ASTEROID, asteroidId, _x, _y, '', true);
    }

    function _addStar(uint _x, uint _y, string memory _name, uint _luminosity) internal {
        //add star to stars list
        uint starId = _stars.length;
        _stars.push(Star(starId, places.length, _luminosity, 0, 0));

        _addPlace(PlaceType.STAR, starId, _x, _y, _name, false);
        emit NewStar(_x, _y);
    }

    function _addPlanet(uint _starId, uint _x, uint _y, string memory _name, bool _isMiningPlanet, bool _hasRefinery, bool _hasShipyard) internal {
        uint starX = places[_stars[_starId].placeId].coordX;
        uint starY = places[_stars[_starId].placeId].coordY;
        uint starDistance = Helper.getDistance(starX, starY, _x, _y);

        //add planet info to star
        if(_isMiningPlanet) {
            _stars[_starId].totalMiningPlanetDistance += starDistance;
            _stars[_starId].totalMiningPlanets += 1;
        }

        uint planetId = _planets.length;
        _planets.push(Planet(planetId, places.length, _starId, starDistance, _isMiningPlanet, 0, _hasRefinery, _hasShipyard));

        _addPlace(PlaceType.PLANET, planetId, _x, _y, _name, true);
        emit NewPlanet(_starId, _x, _y);
    }

    function getExploreCost(uint _x, uint _y, address _player) public view returns(uint) {
       //Every 500 experience, exploring is reduced by 1% up to 50%
       uint distanceFromHaven = Helper.getDistance(0, 0, _x, _y);
       uint exploreDiscount = Helper.getMin(50, Fleet.getExperience(_player) / 500);
       uint baseExploreCost = (distanceFromHaven * 2 * 10**18) / Treasury.getCostMod();
       return (baseExploreCost * (100-exploreDiscount)) / 100;
    }

    //player explore function
    function explore(uint _x, uint _y) external {
        address sender = msg.sender;
        require(getDistanceFromFleet(sender, _x, _y) <= 2, "MAPS: explore too far");
        uint exploreCost = getExploreCost(_x, _y, sender);
        Treasury.pay(sender, exploreCost);
        Fleet.addExperience(sender, exploreCost*3); //triple experience for exploring
        _createRandomPlaceAt(_x, _y);
    }

    //create a random place at given coordinates
    function _createRandomPlaceAt(uint _x, uint _y) internal {
        require(_placeExists[_x][_y] == false, 'Place already exists');
        uint rand = (_rewardsTimer + (_x * _y) + _x + _y + places.length) % 100;
        if(rand >= 0 && rand <= 1) {
            _addWormhole(_x, _y);
        }
        else if(rand >= 2 && rand <= 16) {
            _addEmpty(_x, _y);
        }
        else if(rand >= 17 && rand <= 28) {
            _addAsteroid(_x, _y, (places.length % 10) + 10);
        }
        else if(rand >= 29 && rand <= 65) {
            _addHostile(_x, _y); 
        }
        else if(rand >= 66 && rand <= 99) {
            uint nearestStar = _getNearestStar(_x, _y);
            uint nearestStarX = places[_stars[nearestStar].placeId].coordX;
            uint nearestStarY = places[_stars[nearestStar].placeId].coordY;

            //new planet must be within 3 AU off nearest star
            if(rand >= 66 && rand <= 79 && Helper.getDistance(_x, _y, nearestStarX, nearestStarY) <= 3) {
                bool isMiningPlanet;
                bool hasShipyard;
                bool hasRefinery;
                uint planetAttributeSelector = places.length % 20;
                if(planetAttributeSelector <= 7) {
                    isMiningPlanet = true;
                    _rewardsTimer = 0; // get rewards going to planet right away when new one is discovered
                }
                else if(planetAttributeSelector >= 8 && planetAttributeSelector <=13) {
                    hasRefinery = true;
                }
                else if(planetAttributeSelector >= 14 && planetAttributeSelector <= 18) {
                    hasShipyard = true;
                }
                else { hasShipyard = true; hasRefinery = true; }
                _addPlanet(nearestStar, _x, _y, '', isMiningPlanet, hasRefinery, hasShipyard);

                //if planet has a shipyard, add shipyard to Fleet contract
                if(hasShipyard == true) {
                    address placeOwner = address(this); //map owns shipyards on refinery planets and gets fees which are then disbursed to mining planets
                    if(hasRefinery != true) {
                        placeOwner = msg.sender;
                    }
                    Fleet.addShipyard(string(abi.encodePacked('Shipyard', Strings.toString(_x), Strings.toString(_y))), placeOwner, _x, _y, 5);
                }
            }
            //new star must be more than 7 AU away from nearest star
            else if(rand >= 80 && Helper.getDistance(_x, _y, nearestStarX, nearestStarY) > 7) {
                _addStar(_x, _y, '', (places.length % 7) + 2);
            }
            else {
                _addHostile(_x, _y);
            }
        }
        else {//should never happen, but just in case
           _addEmpty(_x, _y);
        }
    }

    function changeName(uint _x, uint _y, string memory _name) external {
        require(bytes(_name).length <= 12, 'MAP: place name too long');
        Place storage namePlace = places[coordinatePlaces[_x][_y]];
        require(msg.sender == namePlace.discoverer, 'MAP: not discoverer');
        require(namePlace.placeType == PlaceType.PLANET || namePlace.placeType == PlaceType.STAR, 'MAP: not named');
        require(Helper.isEqual(namePlace.name, ""), 'MAP: already named');
        namePlace.name = _name;
    }

    function _getNearestStar(uint _x, uint _y) internal view returns(uint) {
        uint nearestStar;
        uint nearestStarDistance;
        for(uint i=0; i<_stars.length; i++) {
            uint starDistance = Helper.getDistance(_x, _y, places[_stars[i].placeId].coordX, places[_stars[i].placeId].coordY);
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
        for(uint j=_ly+7; j>_ly; j--) {
            for(uint i=_lx; i<=_lx+6; i++) {
                foundCoordinatePlaces[counter++] = getPlaceInfo(i, j-1);
            }
        }
        return foundCoordinatePlaces;
    }

    function getPlaceInfo(uint _x, uint _y) public view returns(PlaceGetter memory) {
        PlaceGetter memory placeGetter;

        if(_placeExists[_x][_y] == true) {
            Place memory place = places[coordinatePlaces[_x][_y]];
            placeGetter.canTravel = place.canTravel;
            placeGetter.name = place.name; 
            placeGetter.placeType = place.placeType;
            placeGetter.salvage = place.salvage;
            placeGetter.fleetCount = fleetsAtLocation[_x][_y].length;
            placeGetter.discoverer = place.discoverer;

            placeGetter.activeBattleCount = place.activeBattleCount;

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
        return placeGetter;
    }

    function _getPlanetAtLocation(uint _x, uint _y) internal view returns (Planet memory) {
        Planet memory planet;
        Place memory place = places[coordinatePlaces[_x][_y]];
        if(place.placeType == PlaceType.PLANET) {
            planet = _planets[place.childId];
        }
        return planet;
    }

    function getPlanetAtFleetLocation(address _sender) internal view returns (Planet memory) {
        (uint fleetX, uint fleetY) =  getFleetLocation(_sender);
        return _getPlanetAtLocation(fleetX, fleetY);
    }

    function isRefineryLocation(uint _x, uint _y) external view returns (bool) {
        return _getPlanetAtLocation(_x, _y).hasRefinery;
    }

    function isShipyardLocation(uint _x, uint _y) public view returns (bool) {
        return _getPlanetAtLocation(_x, _y).hasShipyard;
    }

    function requestToken() external onlyOwner {
        _requestToken();
    }

    function _requestToken() internal {
        if (block.timestamp >= _rewardsTimer && _rewardsMod > 0) {
            ShadowPool.replenishPlace();

            uint amount = (Token.balanceOf(address(ShadowPool)) * _rewardsMod) / 100;
            if (amount > 0) {
                Token.safeTransferFrom(address(ShadowPool), address(this), amount);
            }
            _rewardsTimer = block.timestamp + rewardsDelay;
            allocateToken();
        }
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

                    uint newStarSystemToken = (newAmount * star.luminosity) / totalStarLuminosity;

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

       //Every 500 experience, travel is reduced by 1% up to 90%
       uint travelDiscount = Helper.getMin(90, Fleet.getExperience(_fleet) / 500);
       return (((distance**2 * _baseTravelCost * fleetSize) * (100-travelDiscount)) / 100) / Treasury.getCostMod();
    }

    function getFleetTravelCooldown(address _fleet, uint _x, uint _y) public view returns (uint) {
       uint distance = getDistanceFromFleet(_fleet, _x, _y);
       return (_baseTravelCooldown + (distance*_travelCooldownPerDistance)) / _timeModifier;
    }

    // ship travel to _x and _y
    function travel(uint _x, uint _y) external {
        require(_placeExists[_x][_y] == true, 'MAPS: place unexplored');
        require(places[coordinatePlaces[_x][_y]].canTravel == true, 'MAPS: no travel');
        address sender = msg.sender;
        require(block.timestamp >= fleetTravelCooldown[sender], "MAPS: jump drive recharging");
        require(getDistanceFromFleet(sender, _x, _y) <= _maxTravel, "MAPS: cannot travel that far");
        require(Fleet.getFleetSize(sender) >= _minTravelSize, "MAPS: fleet too small");
        require(Fleet.isInBattle(sender) != true, "MAPS: in battle or takeover");

        uint travelCost = getFleetTravelCost(sender, _x, _y);
        Treasury.pay(sender, travelCost);
        Fleet.addExperience(sender, travelCost);

        fleetTravelCooldown[sender] = block.timestamp + getFleetTravelCooldown(sender, _x, _y);

        (uint fleetX, uint fleetY) =  getFleetLocation(sender);
        _setFleetLocation(sender, fleetX, fleetY, _x, _y);
    }

    //wormhole travel
    function tunnel(uint _x, uint _y) external {
        address sender = msg.sender;
        //confirm valid source and destination
        require(_placeExists[_x][_y] == true, 'MAPS: place unexplored');
        require(places[coordinatePlaces[_x][_y]].placeType == PlaceType.WORMHOLE, 'MAPS: dest. not wormhole');
        (uint fleetX, uint fleetY) = getFleetLocation(sender);
        require(places[coordinatePlaces[fleetX][fleetY]].placeType == PlaceType.WORMHOLE, 'MAPS: src not wormhole');

        //make sure not in battle or shipyard takeover
        require(Fleet.isInBattle(sender) != true, "MAPS: in battle or takeover");

        //pay cost (10% of normal travel cost for that distance)
        uint travelCost = getFleetTravelCost(sender, _x, _y) / 10;
        Treasury.pay(sender, travelCost);
        Fleet.addExperience(sender, travelCost);

        _setFleetLocation(sender, fleetX, fleetY, _x, _y);
    }

    //player can set recall spot if at a shipyard
    function setRecall() external {
        (uint fleetX, uint fleetY) =  getFleetLocation(msg.sender);
        require(isShipyardLocation(fleetX, fleetY) == true, 'MAP: no shipyard');
        fleetLastShipyardPlace[msg.sender] = coordinatePlaces[fleetX][fleetY];
    }

    //recall player to last shipyard visited
    function recall(bool _goToHaven) external {
        require(Fleet.getFleetSize(msg.sender) < _minTravelSize, "FLEET: too large for recall");

        uint recallX;
        uint recallY;
        if(_goToHaven != true) {
            recallX = places[fleetLastShipyardPlace[msg.sender]].coordX;
            recallY = places[fleetLastShipyardPlace[msg.sender]].coordY;
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

    function addSalvageToPlace(uint _x, uint _y, uint _amount) external onlyEditor {
        //get place and add it to place
        places[coordinatePlaces[_x][_y]].salvage += _amount * 98 / 100;
    }

    // When Token allocated for salvage gets added to contract, call this function
    function increasePreviousBalance(uint _amount) external onlyEditor {
        previousBalance += _amount * 98 / 100;
    }

    //collect salvage from a coordinate
    function collect() external {
        (uint fleetX, uint fleetY) = getFleetLocation(msg.sender);
        require(_placeExists[fleetX][fleetY] == true, 'MAPS: no place');
        places[coordinatePlaces[fleetX][fleetY]].salvage -=
            _gather(msg.sender, places[coordinatePlaces[fleetX][fleetY]].salvage, _miningCooldown / _collectCooldownReduction);
    }
 
    //Fleet can mine mineral depending their fleet's capacity and planet available
    function mine() external {
        (uint fleetX, uint fleetY) = getFleetLocation(msg.sender);
        require(_placeExists[fleetX][fleetY] == true, 'MAPS: no place');
        Place memory miningPlace = places[coordinatePlaces[fleetX][fleetY]];

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
        previousBalance -= playerMineral;
        emit MineralRefined(player, playerMineral);
        fleetMineralRefined[player] += playerMineral;
        _requestToken();
    }

    function adjustActiveBattleCount(uint _x, uint _y, int _amount) external onlyEditor {
        places[coordinatePlaces[_x][_y]].activeBattleCount = uint(int(places[coordinatePlaces[_x][_y]].activeBattleCount) + _amount);
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