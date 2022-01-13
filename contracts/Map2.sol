// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import './libs/Editor.sol';
import './libs/Helper.sol';
import './libs/ShibaBEP20.sol';
import './libs/SafeBEP20.sol';

contract Map is Editor {
    using SafeBEP20 for ShibaBEP20;

    constructor (
        ShibaBEP20 _nova
    ) {
        Nova = _nova;

        placeTypes.push('star');
        placeTypes.push('planet');
        placeTypes.push('jumpgate');

        _addPlace('uncharted', 0, 0, 0);
        _addStar(2, 2, 9); // first star
        _addPlanet(0, 0, 0, false, true, true); //Haven
        _addPlanet(0, 3, 4, true, false, false); //unrefined planet
        _addPlanet(0, 1, 6, true, false, false); //unrefined planet
    }

    uint public previousBalance = 0;
    ShibaBEP20 public Nova; // NOVA Token

    string[] public placeTypes; // list of placeTypes

    // Coordinates return the place id
    mapping (uint => mapping(uint => uint)) public coordinatePlaceIds;

    struct Place {
        string placeType;
        uint childId;
        uint coordX;
        uint coordY;
    }
    Place[] public places;

    struct Planet {
        uint placeId;
        uint starId;
        uint starDistance;
        bool isMiningPlanet;
        uint availableNova;
        bool hasRefinery;
        bool hasShipyard;
    }
    Planet[] public planets;

    struct Star {
        uint placeId;
        uint luminosity;
        uint totalMiningPlanets;
        uint totalMiningPlanetDistance;
    }
    Star[] public stars;

    struct Jumpgate {
        uint placeId;
    }
    Jumpgate[] jumpgates;

    function _addPlace(string memory _placeType, uint _childId, uint _x, uint _y) internal {
        require(coordinatePlaceIds[_x][_y] == 0, 'Place already exists in these coordinates');
        places.push(Place(_placeType, _childId, _x, _y));
        uint placeId = places.length - 1;

        //set place in coordinate mapping
        coordinatePlaceIds[_x][_y] = placeId;

        //link child place to place
        if(Helper.isEqual(_placeType, 'planet')) {
            planets[_childId].placeId = placeId;
        }
        else if(Helper.isEqual(_placeType, 'star')) {
            stars[_childId].placeId = placeId;
        }
        else if(Helper.isEqual(_placeType, 'jumpgate')) {
        }
    }

    function _addStar(uint _x, uint _y, uint _luminosity) internal {
        //add star to stars list
        stars.push(Star(0, _luminosity, 0, 0));
        _addPlace('star', stars.length - 1, _x, _y);
    }

    function addStar(uint _x, uint _y, uint _luminosity) external onlyOwner {
        _addStar(_x, _y, _luminosity);
    }

    function _addPlanet(uint _starId, uint _x, uint _y, bool _isMiningPlanet, bool _hasRefinery, bool _hasShipyard) internal {
        uint starX = places[stars[_starId].placeId].coordX;
        uint starY = places[stars[_starId].placeId].coordY;
        uint starDistance = Helper.getDistance(starX*10, starY*10, _x*10, _y*10);

        //add planet info to star
        if(_isMiningPlanet) {
            stars[_starId].totalMiningPlanetDistance += starDistance;
            stars[_starId].totalMiningPlanets += 1;
        }

        planets.push(Planet(0, _starId, starDistance, _isMiningPlanet, 0, _hasRefinery, _hasShipyard));
        _addPlace('planet', planets.length - 1, _x, _y);
    }

    function addPlanet(uint _starId, uint _x, uint _y, bool _isMiningPlanet, bool _hasRefinery, bool _hasShipyard) external onlyOwner{
        _addPlanet(_starId, _x, _y, _isMiningPlanet, _hasRefinery, _hasShipyard);
    }

    /* get coordinatePlaceIds cannot handle a map box larger than 255 */
    function getCoordinatePlaces(uint _lx, uint _ly, uint _rx, uint _ry) external view returns(uint[] memory) {
        uint xDistance = (_rx - _lx) + 1;
        uint yDistance = (_ry - _ly) + 1;
        uint numCoordinates = xDistance * yDistance;
        require( xDistance * yDistance < 256, 'MAP: Too much data in loop');

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

    function getPlaceId(uint _x, uint _y) external view returns (uint) {
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

    function allocateNova() external {
        uint newAmount = Nova.balanceOf(address(this)) - previousBalance;
        require(newAmount > 0, 'PLACEMANAGER: no Nova to allocate');

        uint totalStarLuminosity = getTotalLuminosity();

        //loop through planets and add new nova
        for(uint i=0; i<planets.length; i++) {
            Planet memory planet = planets[i];

            if(planet.isMiningPlanet) {
                Star memory star = stars[planet.starId];

                uint newStarSystemNova = newAmount * (star.luminosity / totalStarLuminosity);

                uint newUNova = newStarSystemNova;
                //if more than one planet in star system
                if(star.totalMiningPlanets > 1) {
                    newUNova = newStarSystemNova * (star.totalMiningPlanetDistance - planet.starDistance) / (star.totalMiningPlanetDistance * (star.totalMiningPlanets - 1));
                }
                planets[i].availableNova += newUNova;
            }
        }
        previousBalance = Nova.balanceOf(address(this));
    }
}