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
        ShibaBEP20 _token,
        ITreasury _treasury,
        IShadowPool _shadowPool,
        IFleet _fleet
    ) {
        Token = _token;
        Treasury = _treasury;
        ShadowPool = _shadowPool;
        Fleet = _fleet;

        previousBalance = 0;
        baseTravelCost = 10;
        baseCooldown = 2700; //45 minutes
        cooldownMod = 900; //15 minutes
        maxTravel = 5000; //AU
        rewardsTimer = 0;

        placeTypes.push('star');
        placeTypes.push('planet');
        placeTypes.push('jumpgate');

        _addPlace('uncharted', 0, 0, 0);
        _addStar(2, 2, 9); // first star
        _addPlanet(0, 0, 0, false, true, true); //Haven
        _addPlanet(0, 3, 4, true, false, false); //unrefined planet
        _addPlanet(0, 1, 6, true, false, false); //unrefined planet
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


    // Fleet Info and helpers
    mapping (address => uint[2]) fleetLocation; //address to [x,y] array
    mapping(address => uint) public fleetMineral; //amount of mineral a fleet is carrying
    address[] public fleetList; //all addresses that started the game  
    mapping(address => bool) isFleet; // flag so fleet can only be loaded once  
    mapping (address => uint) travelCooldown; // limits how often fleets can travel
    // travelCooldown = block.timestamp + baseCooldown + (distance * cooldownMod(in seconds))
    uint public baseCooldown; 
    uint public cooldownMod; 
    uint public baseTravelCost; // Token cost to travel 1 AU
    uint public maxTravel; // max distance a fleet can travel in 1 jump

    string[] public placeTypes; // list of placeTypes

    // Coordinates return the place id
    mapping (uint => mapping(uint => uint)) public coordinatePlaceIds;

    struct Place {
        uint id; //native key 
        string placeType;
        uint childId;
        uint coordX;
        uint coordY;
    }
    Place[] public places;

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
    event MineralTransferred(address _from, address _to, uint _amount);
    event MineralRefined(address _fleet, uint _amount);
    event MineralMined(address _fleet, uint _amount);
    event NewPlanet(uint _star, uint _x, uint _y);
    event NewStar(uint _x, uint _y);

    function _addPlace(string memory _placeType, uint _childId, uint _x, uint _y) internal {
        require(coordinatePlaceIds[_x][_y] == 0, 'Place already exists in these coordinates');
        uint placeId = places.length;
        places.push(Place(placeId, _placeType, _childId, _x, _y));

        //set place in coordinate mapping
        coordinatePlaceIds[_x][_y] = placeId;
    }

    function _addStar(uint _x, uint _y, uint _luminosity) internal {
        //add star to stars list
        uint starId = stars.length;
        stars.push(Star(starId, places.length, _luminosity, 0, 0));

        _addPlace('star', starId, _x, _y);
        emit NewStar(_x, _y);
    }

    function addStar(uint _x, uint _y, uint _luminosity) external onlyOwner {
        _addStar(_x, _y, _luminosity);
    }

    function _addPlanet(uint _starId, uint _x, uint _y, bool _isMiningPlanet, bool _hasRefinery, bool _hasShipyard) internal {
        uint starX = places[stars[_starId].placeId].coordX;
        uint starY = places[stars[_starId].placeId].coordY;
        uint starDistance = Helper.getDistance(starX, starY, _x, _y);

        //add planet info to star
        if(_isMiningPlanet) {
            stars[_starId].totalMiningPlanetDistance += starDistance;
            stars[_starId].totalMiningPlanets += 1;
        }

        uint planetId = planets.length;
        planets.push(Planet(planetId, 0, _starId, starDistance, _isMiningPlanet, 0, _hasRefinery, _hasShipyard));

        _addPlace('planet', planetId, _x, _y);
        emit NewPlanet(_starId, _x, _y);
    }

    function addPlanet(uint _starId, uint _x, uint _y, bool _isMiningPlanet, bool _hasRefinery, bool _hasShipyard) external onlyOwner{
        _addPlanet(_starId, _x, _y, _isMiningPlanet, _hasRefinery, _hasShipyard);
    }

    function _addJumpgate(address _owner, uint _x, uint _y) internal {

    }

    /* get coordinatePlaceIds cannot handle a map box larger than 255 */
    function getCoordinatePlaces(uint _lx, uint _ly, uint _rx, uint _ry) external view returns(uint[] memory) {
        uint xDistance = (_rx - _lx) + 1;
        uint yDistance = (_ry - _ly) + 1;
        uint numCoordinates = xDistance * yDistance;
        require(xDistance * yDistance < 256, 'MAP: Too much data in loop');

        uint[] memory foundCoordinatePlaceIds = new uint[]((numCoordinates));

        uint counter = 0;
        for(uint i=_lx; i<=_rx;i++) {
            for(uint j=_ly; j<=_ry;j++) {
                foundCoordinatePlaceIds[counter] = coordinatePlaceIds[i][j];
                counter++;
            }
        }
        return foundCoordinatePlaceIds;
    }

    function getPlaceId(uint _x, uint _y) public view returns (uint) {
        return (coordinatePlaceIds[_x][_y]);
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

    // Function to mine, refine, transfer unrefined Token
    function allocateToken() public {
        uint newAmount = Token.balanceOf(address(this)) - previousBalance;
        require(newAmount > 0, 'MAP: no Token to allocate');

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

    function getPlanetAtLocation(uint _x, uint _y) internal view returns (Planet memory) {

        Place memory place = places[coordinatePlaceIds[_x][_y]];

        require(Helper.isEqual(place.placeType, 'No planet found at this location.'));

        return planets[place.childId];
    }

    function getPlanetAtFleetLocation(address _sender) internal view returns (Planet memory) {
        (uint fleetX, uint fleetY) =  getFleetLocation(_sender);
        return getPlanetAtLocation(fleetX, fleetY);
        //return getPlanetAtLocation(getFleetLocation(_sender));
    }

    function isRefineryLocation(uint _x, uint _y) external view returns (bool) {
        return getPlanetAtLocation(_x, _y).hasRefinery;
    }

    function isShipyardLocation(uint _x, uint _y) external view returns (bool) {
        return getPlanetAtLocation(_x, _y).hasShipyard;
    }

    //Fleet can mine Mineral depending their fleet's capacity
    function mine() external {
        address sender = msg.sender;
        Planet memory planet = getPlanetAtFleetLocation(sender);

        require(planet.availableMineral > 0, 'MAP: no mineral found');
        require(isPaused[planet.placeId] != true, "MAP: mineral is paused");
        
        // uint maxMine = Fleet.getTokenCapacity[sender] - fleetMineral(sender);
        //link to fleets, will have to edit maxMine with above
        uint maxMine = 100;

        uint minedAmount = Helper.getMin(planet.availableMineral, maxMine);
        
        planets[planet.id].availableMineral -= minedAmount;
        
        fleetMineral[sender] += minedAmount;
        // requestToken();
        emit MineralMined(sender, minedAmount);
    }
    
    function refine() external {
        address sender = msg.sender;
       Planet memory planet = getPlanetAtFleetLocation(sender);

        require(planet.hasRefinery == true, "MAP: Fleet not at a refinery");
        require(fleetMineral[sender] > 0, "MAP: Fleet has no unrefined Token");

        uint totalMineral = fleetMineral[sender];
        fleetMineral[sender] = 0;
        Token.safeTransfer(sender, totalMineral);
        previousBalance = previousBalance - totalMineral;
        emit MineralRefined(sender, totalMineral);
    }

    // remember to set to onlyEditor
    // Allows players to take unrefined token from other players
    function transferMineral(address _sender, address _receiver, uint _percent) external {
        //uint amount = ((fleetMineral(_sender) * _percent / 100) <= (Fleet.getTokenCapacity[_player] - getFleetMineral(_sender)) ? (getFleetMineral(_sender) * _percent / 100) : (Fleet.getTokenCapacity[_player] - getFleetMineral(_sender)));
        // replace amount with previous line when we have fleet data
        uint amount = (fleetMineral[_sender] * _percent / 100);
        uint transferredMineral; 

            if (amount > fleetMineral[_sender]) {
                amount = 0;
                uint transfer = fleetMineral[_sender];
                fleetMineral[_sender] -= transfer;
                fleetMineral[_receiver] += transfer;
                transferredMineral = transferredMineral + transfer;
            } else if (fleetMineral[_sender] >= amount) {
                uint transfer = amount;
                amount = 0;
                fleetMineral[_sender] -= transfer;
                fleetMineral[_receiver] += transfer;
                transferredMineral += transfer;
            } 
        emit MineralTransferred(_sender, _receiver, transferredMineral);
    }

    //Fleet Location Functions
    // Sets initial fleet location, adds to fleet list
    // needs to be linked to some setup function (when you buy first fleet?)
    function loadFleet(address _sender) external {
        require(isFleet[_sender] != true, "MAP: Fleet is already registered");
        isFleet[_sender] = true;
        fleetLocation[_sender] = [0, 0];
        fleetList.push(_sender);
    }
    // Needs to be set to internal and controlled by travel function
    function _setFleetLocation (address _fleet, uint _x, uint _y) public {
        fleetLocation[_fleet] = [_x, _y];
    }

    // Returns both x and y coordinates
    function getFleetLocation (address _fleet) public view returns(uint x, uint y) {
        return (fleetLocation[_fleet][0], fleetLocation[_fleet][1]);
    }

    // Will this function cause errors when a place has hundreds of fleets?
    function getFleetsAtLocation (uint _x, uint _y) external view returns(address[] memory) {
       address[] memory fleets = new address[](fleetList.length);
       uint counter;
       for (uint i = 0; i < fleetList.length - 1; i++) {
           if (fleetLocation[fleetList[i]][0] == _x && fleetLocation[fleetList[i]][1] == _y) {
               fleets[counter] = fleetList[i];
               counter++;
           }
       }
       return fleets;
    }

     // Travel function, needs size modifier & restriciton on travel distance
    function travel( uint _x, uint _y) external {
        address sender = msg.sender;
        require(isFleet[sender] == true, "MAP: Fleet is not loaded");
        uint distance = getDistanceFromFleet(sender, _x, _y);
        require(block.timestamp >= travelCooldown[sender], "MAPS: Jump drive still recharging");
        require(distance <= maxTravel, "MAPS: cannot travel that far");
        travelCooldown[sender] = block.timestamp + baseCooldown + (distance*cooldownMod);
        uint amount = distance**2 * baseTravelCost *Treasury.getCostMod(); // add size mod
        Treasury.pay(sender, amount);
        _setFleetLocation(sender, _x, _y);
    }

    function getDistanceFromFleet (address _fleet, uint _x, uint _y) public view returns(uint) {
        uint oldX = fleetLocation[_fleet][0];
        uint oldY = fleetLocation[_fleet][1];
        return Helper.getDistance(oldX, oldY, _x, _y);
    }

    // Setting to 0 disables travel
    function setMaxTravel(uint _new) external onlyOwner {
        maxTravel = _new;
    }    

    // Setting to 0 removes the secondary cooldown period
    function setCooldownMod(uint _new) external onlyOwner {
        cooldownMod = _new;
    }

    // setting to 0 removes base travel cooldown
    function setBaseCooldown(uint _new) external onlyOwner {
        baseCooldown = _new;
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
}

