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
       // IFleet _fleet
    ) {
        Token = ShibaBEP20(0x9249DAcc91cddB8C67E9a89e02E071085dE613cE);
        Treasury = ITreasury(0x42bCB57E0617728A7E4e13D8cD6458879cd576D1);
       // ShadowPool = _shadowPool;
       // Fleet = _fleet;

        previousBalance = 0;
        baseTravelCost = 10**15;
        baseTravelCooldown = 2700; //45 minutes
        travelCooldownPerDistance = 900; //15 minutes
        maxTravel = 10; //AU
        rewardsTimer = 0;
        timeModifier = 100;
        miningCooldown = 1800; //30 minutes

        placeTypes.push('star');
        placeTypes.push('planet');
        placeTypes.push('jumpgate');

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
    uint public rewardsMod; // = x/100, the higher the number the more rewards sent to this contract
    uint rewardsTimer; // Rewards can only be pulled from shadow pool every 4 hours?
    uint rewardsDelay;
    mapping (uint => bool) isPaused; // can pause token mineing for jackpots
    uint timeModifier; //allow all times to be changed
    uint miningCooldown; // how long before 

    // Fleet Info and helpers
    mapping (address => uint[2]) fleetLocation; //address to [x,y] array
    mapping(uint => mapping (uint => address[])) fleetsAtLocation; //reverse index to see what fleets are at what location

    mapping(address => uint) public fleetMineral; //amount of mineral a fleet is carrying
    mapping (address => uint) travelCooldown; // limits how often fleets can travel
    mapping (address => uint) fleetMiningCooldown; // limits how often a fleet can mine mineral
    
    uint public baseTravelCooldown; 
    uint public travelCooldownPerDistance; 
    uint public baseTravelCost; // Token cost to travel 1 AU
    uint public maxTravel; // max distance a fleet can travel in 1 jump

    string[] public placeTypes; // list of placeTypes

    struct Place {
        uint id; //native key 
        string placeType;
        uint childId;
        uint coordX;
        uint coordY;
        string name;
        uint salvage;
    }
    Place[] public places;
    mapping (uint => mapping(uint => bool)) public placeExists;
    mapping (uint => mapping(uint => uint)) public coordinatePlaces;

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
    Planet[] public planets;

    struct Star {
        uint id; //native key
        uint placeId; //foreign key to places
        uint luminosity;
        uint totalMiningPlanets;
        uint totalMiningPlanetDistance;
    }
    Star[] public stars;

    struct Jumpgate {
        uint id; //native key
        uint placeId; //foreign key to places
        uint tetheredGateId;
        address owner;
        uint gateFee;
    }
    Jumpgate[] jumpgates;

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
        require(placeExists[_x][_y] == false, 'Place already exists in these coordinates');
        uint placeId = places.length;
        places.push(Place(placeId, _placeType, _childId, _x, _y, _name, 0));

        //set place in coordinate mapping
        placeExists[_x][_y] = true;
        coordinatePlaces[_x][_y] = placeId;
    }

    function _addStar(uint _x, uint _y, string memory _name, uint _luminosity) internal {
        //add star to stars list
        uint starId = stars.length;
        stars.push(Star(starId, places.length, _luminosity, 0, 0));

        _addPlace('star', starId, _x, _y, _name);
        emit NewStar(_x, _y);
    }

    function addStar(uint _x, uint _y, string memory _name, uint _luminosity) external onlyOwner {
        _addStar(_x, _y, _name, _luminosity);
    }

    function _addPlanet(uint _starId, uint _x, uint _y, string memory _name, bool _isMiningPlanet, bool _hasRefinery, bool _hasShipyard) internal {
        uint starX = places[stars[_starId].placeId].coordX;
        uint starY = places[stars[_starId].placeId].coordY;
        uint starDistance = Helper.getDistance(starX, starY, _x, _y);

        //add planet info to star
        if(_isMiningPlanet) {
            stars[_starId].totalMiningPlanetDistance += starDistance;
            stars[_starId].totalMiningPlanets += 1;
        }

        uint planetId = planets.length;
        planets.push(Planet(planetId, places.length, _starId, starDistance, _isMiningPlanet, 0, _hasRefinery, _hasShipyard));

        _addPlace('planet', planetId, _x, _y, _name);
        emit NewPlanet(_starId, _x, _y);
    }

    function addPlanet(uint _starId, uint _x, uint _y, string memory _name, bool _isMiningPlanet, bool _hasRefinery, bool _hasShipyard) external onlyOwner{
        _addPlanet(_starId, _x, _y, _name, _isMiningPlanet, _hasRefinery, _hasShipyard);
    }

    function _addJumpgate(address _owner, uint _x, uint _y) internal {

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
                foundCoordinatePlaces[counter] = places[coordinatePlaces[i][j]];
                counter++;
            }
        }
        return foundCoordinatePlaces;
    }

    function _getCoordinatePlace(uint _x, uint _y) internal view returns (Place memory) {
        return places[coordinatePlaces[_x][_y]];
    }

    function getCoordinateInfo(uint _x, uint _y) external view returns (string memory, string memory, uint, bool, bool, uint) {
        string memory placeName;
        string memory placeType;
        uint salvage;
        bool hasShipyard;
        bool hasRefinery;
        uint mineral;

        if(placeExists[_x][_y]) {
            Place memory place  = places[coordinatePlaces[_x][_y]];
            placeName = place.name;
            placeType = place.placeType;
            salvage = place.salvage;
            if(Helper.isEqual(placeType, 'planet')) {
                Planet memory planet = planets[place.childId];
                hasShipyard = planet.hasShipyard;
                hasRefinery = planet.hasRefinery;
                mineral = planet.availableMineral;
            }
        }
        return (placeName, placeType, salvage, hasShipyard, hasRefinery, mineral);
    }

    function getPlaceId(uint _x, uint _y) public view returns (uint) {
        return (coordinatePlaces[_x][_y]);
    }

    function getPlaceName(uint _x, uint _y) external view returns(string memory) {
        return places[getPlaceId(_x, _y)].name;
    }

    // currently no check for duplicates
    function addPlaceType(string memory _name) external onlyOwner {
        placeTypes.push(_name);
    }

    // get total star luminosity
    function getTotalLuminosity() public view returns(uint) {
        uint totalLuminosity = 0;
        for(uint i=0; i<stars.length; i++) {
            if(stars[i].totalMiningPlanets > 0) {
                totalLuminosity += stars[i].luminosity;
            }
        }
        return totalLuminosity;
    }

    // Pulls token from the shadow pool, eventually internal function
    //PROBLEM: does not function - review 
    function requestToken() external onlyOwner{
        if (block.timestamp >= rewardsTimer) {
            ShadowPool.replenishPlace(address(this), rewardsMod);
            rewardsTimer = block.timestamp + rewardsDelay;
            allocateToken();
        }
    }
    
    function addSalvageToPlace(uint _x, uint _y, uint _amount) external onlyEditor {
        //get place and add it to place
        places[coordinatePlaces[_x][_y]].salvage += _amount * 98 / 100;
        
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
            for(uint i=0; i<planets.length; i++) {
                Planet memory planet = planets[i];

                if(planet.isMiningPlanet) {
                    Star memory star = stars[planet.starId];

                    uint newStarSystemToken = newAmount * (star.luminosity / totalStarLuminosity);

                    uint newMineral = newStarSystemToken;
                    //if more than one planet in star system
                    if(star.totalMiningPlanets > 1) {
                        newMineral = newStarSystemToken * (star.totalMiningPlanetDistance - planet.starDistance) /
                            (star.totalMiningPlanetDistance * (star.totalMiningPlanets - 1));
                    }
                    planets[i].availableMineral += newMineral;
                }
            }
            previousBalance = Token.balanceOf(address(this));
        }
    }

    function getPlanetAtLocation(uint _x, uint _y) internal view returns (Planet memory) {
        Place memory place = places[coordinatePlaces[_x][_y]];
        require(Helper.isEqual(place.placeType, 'planet'), 'No planet found at this location.');
        return planets[place.childId];
    }

    function getPlanetAtFleetLocation(address _sender) internal view returns (Planet memory) {
        (uint fleetX, uint fleetY) =  getFleetLocation(_sender);
        return getPlanetAtLocation(fleetX, fleetY);
    }

    function isRefineryLocation(uint _x, uint _y) external view returns (bool) {
        return getPlanetAtLocation(_x, _y).hasRefinery;
    }

    function isShipyardLocation(uint _x, uint _y) external view returns (bool) {
        return getPlanetAtLocation(_x, _y).hasShipyard;
    }

    //collect salvage from a coordinate
    function collect(uint _x, uint _y) external {
        uint collectSpeedMultiplier = 5;
        address player = msg.sender;
        Place memory place  = places[coordinatePlaces[_x][_y]];
        require(place.salvage > 0, 'MAP: no salvage');

        require(fleetMiningCooldown[player] <= block.timestamp, 'MAP: mining on cooldown');

        uint availableCapacity = Fleet.getMaxMineralCapacity(player) - fleetMineral[player]; //max amount of mineral fleet can carry minus what fleet already is carrying
        require(availableCapacity > 0, 'MAP: fleet cannot carry any more mineral');
        uint collectedAmount = Helper.getMin(availableCapacity, Fleet.getMiningCapacity(player));
        _mineralGained(player, int(collectedAmount));
        fleetMiningCooldown[player] = block.timestamp + ((miningCooldown / collectSpeedMultiplier) / timeModifier);
    }
 
    //Fleet can mine mineral depending their fleet's capacity and planet available
    function mine() external {
        address player = msg.sender;
        Planet memory planet = getPlanetAtFleetLocation(player);
        require(fleetMiningCooldown[player] <= block.timestamp, 'MAP: mining on cooldown');
        require(planet.availableMineral > 0, 'MAP: no mineral found');
        require(isPaused[planet.placeId] != true, "MAP: mineral is paused");

        uint availableCapacity = Fleet.getMaxMineralCapacity(player) - fleetMineral[player]; //max amount of mineral fleet can carry minus what fleet already is carrying
        require(availableCapacity > 0, 'MAP: fleet cannot carry any more mineral');

        uint miningCapacity = Fleet.getMiningCapacity(player);
        
        uint maxMine = Helper.getMin(availableCapacity, miningCapacity);
        uint minedAmount = Helper.getMin(planet.availableMineral, maxMine); //the less of fleet maxMine and how much mineral planet has available
        planets[planet.id].availableMineral -= minedAmount;

        _mineralGained(player, int(minedAmount));
        fleetMiningCooldown[player] = block.timestamp + (miningCooldown / timeModifier);

        //requestToken();
        emit MineralMined(player, minedAmount);
    }
    
    function refine() external {
        address player = msg.sender;
        Planet memory planet = getPlanetAtFleetLocation(player);
        require(planet.hasRefinery == true, "MAP: Fleet not at a refinery");

        uint playerMineral = fleetMineral[player];
        require(playerMineral > 0, "MAP: Player/Fleet has no mineral");
        fleetMineral[player] = 0;

        Token.safeTransfer(player, playerMineral);
        previousBalance -= playerMineral;
        emit MineralRefined(player, playerMineral);
        //requestToken();
    }

    function getFleetMineral(address _player) external view returns(uint) {
        return fleetMineral[_player];
    }

    function mineralGained(address _player, int _amount) external {
        _mineralGained(_player, _amount);
    }

    // remember to set to onlyEditor
    // mineral gained can also be negative; used for player attacks and mining
    function _mineralGained(address _player, int _amount) internal {
        uint startAmount = fleetMineral[_player];
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
       return (distance**2 * baseTravelCost * fleetSize) / Treasury.getCostMod();
    }

    function getFleetTravelCooldown(address _fleet, uint _x, uint _y) public view returns (uint) {
       uint distance = getDistanceFromFleet(_fleet, _x, _y);
       return baseTravelCooldown + (distance*travelCooldownPerDistance);
    }

    // ship travel to _x and _y
    function travel(uint _x, uint _y) external {
        address player = msg.sender;
        require(block.timestamp >= travelCooldown[player], "MAPS: Jump drive still recharging or mineral containment in process");

        uint distance = getDistanceFromFleet(player, _x, _y);
        require(distance <= maxTravel, "MAPS: cannot travel that far");

        uint travelCost = getFleetTravelCost(player, _x, _y);
        Treasury.pay(player, travelCost);

        _addTravelCooldown(player, getFleetTravelCooldown(player, _x, _y));

        (uint fleetX, uint fleetY) =  getFleetLocation(player);
        address[] memory fleetsAtFromLocation = fleetsAtLocation[fleetX][fleetY]; //list of fleets at from location
        uint numFleetsAtLocation = fleetsAtFromLocation.length; //number of fleets at from location

        // PROBLEM: we need to remove this loop. Is there a reason we're storing fleets at location instead of just creating a function that returns this info?
        /* this loop goes through fleets at the player's "from" location and when it finds the fleet,
            it removes puts the last element in the array in that fleets place and then removes the last element */
        for(uint i=0;i<numFleetsAtLocation;i++) {
            if(fleetsAtFromLocation[i] == player) {
                fleetsAtLocation[fleetX][fleetY][i] = fleetsAtLocation[fleetX][fleetY][numFleetsAtLocation-1]; //assign last element in array to where fleet was
                fleetsAtLocation[fleetX][fleetY].pop(); //remove last element in array
            }
        }

        //add fleet to new location fleet list
        fleetsAtLocation[_x][_y].push(player);
        _setFleetLocation(player, _x, _y);

        //exit any battles targeted at player
        Fleet.endBattle(player);
    }

    //set travel cooldown or increase it
    function _addTravelCooldown(address _fleet, uint _seconds) internal {
        uint cooldownTime = _seconds / timeModifier;
        if(travelCooldown[_fleet] > block.timestamp) {
            travelCooldown[_fleet] += cooldownTime;
        }
        else {
            travelCooldown[_fleet] = block.timestamp + cooldownTime;
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
        maxTravel = _new;
    }    

    // Setting to 0 removes the secondary cooldown period
    function setTravelTimePerDistance(uint _new) external onlyOwner {
        travelCooldownPerDistance = _new;
    }

    // setting to 0 removes base travel cooldown
    function setBaseTravelCooldown(uint _new) external onlyOwner {
        baseTravelCooldown = _new;
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
        rewardsMod = _new; // can set to 0 to turn off Token incoming to contract
        emit NewRewardsMod(_new);
    }
    function setRewardsTimer(uint _new) external onlyOwner {
        rewardsTimer = _new;
    }
    function setRewardsDelay(uint _new) external onlyOwner {
        rewardsDelay = _new;
    }
    // Pause unrefined token mining at a jackpot planet
    function setPaused(uint _id,bool _isPaused) external onlyOwner{
        isPaused[_id] = _isPaused;
    }
    function setBaseTravelCost(uint _new) external onlyOwner {
        baseTravelCost = _new;
    }

    // setting to 0 removes base travel cooldown
    function setTimeModifier(uint _new) external onlyOwner {
        timeModifier = _new;
    }
}

