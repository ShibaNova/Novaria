// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./libs/Editor.sol";
import "./libs/Helper.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IPlaceManager.sol";

contract Map is Editor {

    constructor (
        ITreasury _treasury
    ) {
        Treasury = _treasury;
        maxTravel = 3;
        cooldownMod = 600;
        placeTypes.push("Star");
        placeTypes.push("Jackpot");
        placeTypes.push("Shipyard");
    }

    IPlaceManager public PlaceManager;
    ITreasury public Treasury;
    uint public travelCost = 10**16; // NOVA cost to travel 1 distance
    address[] public playerList;
    uint public playerCount;
    uint public maxTravel; // max distance a player can travel at once
    mapping (address => uint) travelCooldown; // limits how often players can travel
    uint public cooldownMod; // travelCooldown = block.timestamp + (distance * cooldownMod(in seconds))
    // Defaults: 0 = star, 1 = jackpot, 2 = shipyard
    string[] public placeTypes; // list of placeTypes

    bool public explorationOn; // 
    mapping(uint => mapping (uint => bool)) isExplored; // determines if coordinates were explored
    // Coordinates return the place
    mapping (uint => mapping(uint => Place)) public coordinatePlaces;
    // Use inputs of address and 0 or 1 to return coords (0=x, 1=y)
    mapping (address => uint[]) playerLocation; 
    // mapping so players can only set initial location once
    mapping(address => bool) isPlayer;

    struct Place {
        string name;
        string placeType;
        bool isDmz;
        bool isRefinery;
        bool isActive;
    }

    event NewPlace (uint xcoord, uint ycoord, string placeType, string name);
    event NoNewPlace (uint xcoord, uint ycoord, string message);

    // struct PlaceType {
    //     string handle;
    //     address contractAddress;
    //     bool isActive;
    // }

    // PlaceType[] placeTypes;

    // function getPlaceType(string memory _handle) public view returns(PlaceType memory) {
    //     for (uint i = 0; i < placeTypes.length; i++) {
    //         if (Helper.isEqual(placeTypes[i].handle, _handle)) {
    //             return placeTypes[i];
    //         }
    //     }
    // }

    // function addPlaceType(string memory _handle, address _contractAddress, bool _isActive) public {
    //     placeTypes.push(PlaceType(_handle, _contractAddress, _isActive));
        
    // }
    // Creates a place at specified coordinates with a place type
    function setPlace(uint _x, uint _y, string  memory _name, string memory _placeType, bool _isDmz, bool _isRefinery, bool _isActive) public { 
        coordinatePlaces[_x][_y] = Place(_name, _placeType, _isDmz, _isRefinery, _isActive);
    }
    
    /* get coordinatePlaces cannot handle a map box larger than 255 */
    function getCoordinatePlaces(uint _lx, uint _ly, uint _rx, uint _ry) external view returns(Place[] memory) {
        uint xDistance = (_rx - _lx) + 1;
        uint yDistance = (_ry - _ly) + 1;
        uint numCoordinates = xDistance * yDistance;
        require( xDistance * yDistance < 256, "MAP: Too much data in loop");

        Place[] memory foundCoordinatePlaces= new Place[]((numCoordinates));

        uint counter = 0;
        for(uint i=_lx; i<=_rx;i++) {
            for(uint j=_ly; j<=_ry;j++) {
                foundCoordinatePlaces[counter] = coordinatePlaces[i][j];
                counter++;
            }
        }
        return foundCoordinatePlaces;
    }

    function getPlace(uint _x, uint _y) external view returns (
        string memory name,
        string memory placeType,
        bool isDmz,
        bool isRefinery,
        bool isActive
    ) {
        return (coordinatePlaces[_x][_y].name,
        coordinatePlaces[_x][_y].placeType,
        coordinatePlaces[_x][_y].isDmz,
        coordinatePlaces[_x][_y].isRefinery,
        coordinatePlaces[_x][_y].isActive);
    }

    function isRefinery(uint _x, uint _y) external view returns(bool) {
        return coordinatePlaces[_x][_y].isRefinery;
    }

    // Sets initial player location, adds to player list, adds to player count
    // needs to be linked to some setup funciton
    function setInitialLocation(address _sender) external {
        require(isPlayer[_sender] != true, "MAP: Player is already registered");
        isPlayer[_sender] = true;
        playerLocation[_sender] = [0, 0];
        playerCount++;
        playerList.push(_sender);
    }
    // Needs to be set to internal and controlled by travel function
    function _setPlayerLocation (address _player, uint _x, uint _y) public {
        playerLocation[_player] = [_x, _y];
    }

    // Returns both x and y coordinates
    function getPlayerLocation (address _player) public view returns(uint x, uint y) {
        return (playerLocation[_player][0], playerLocation[_player][1]);
    }

    // Will this function cause errors when a place has hundreds of players?
    function getPlayersAtLocation (uint _x, uint _y) public view returns(address[] memory) {
       address[] memory players = new address[](playerList.length);
       uint counter;
       for (uint i = 0; i < playerList.length - 1; i++) {
           if (playerLocation[playerList[i]][0] == _x && playerLocation[playerList[i]][1] == _y) {
               players[counter] = playerList[i];
               counter++;
           }
       }
       return players;
    }

    // Travel function, needs size modifier & restriciton on travel distance
    function travel( uint _x, uint _y) external {
        address _sender = msg.sender;
        uint _distance = getDistanceFromPlayer(_sender, _x, _y);
        require(block.timestamp >= travelCooldown[_sender], "MAPS: Jump drive still recharging");
        require(_distance <= maxTravel, "MAPS: cannot travel that far");
        travelCooldown[_sender] = block.timestamp + (_distance*cooldownMod);
        uint _amount = _distance * travelCost *Treasury.getCostMod();
        Treasury.pay(_sender, _amount);
        _setPlayerLocation(_sender, _x, _y);
    }

    function getDistanceFromPlayer (address _player, uint _x, uint _y) public view returns(uint) {
        uint oldX = playerLocation[_player][0];
        uint oldY = playerLocation[_player][1];
        Helper.getDistance(oldX, oldY, _x, _y);
    }

    // Setting to 0 disables travel
    function setMaxTravel(uint _new) external onlyOwner {
        maxTravel = _new;
    }    

    // Setting to 0 removes the cooldown period
    function setCooldownMod(uint _new) external onlyOwner {
        cooldownMod = _new;
    }

    // add renaming function, initial is type+coords (create concat helper), cooldown for renaming
    // Exploration functions
    // Players can explore uncharted coordinates and possibly find new places
    // Current options include a star or jackpot
    // Stars and shipyards cannot be within 5 coordinate points, jackpots 2
    function explore(uint _x, uint _y, string memory _name) external {
        require(explorationOn == true, "MAPS: Exploring not active");
        require(isExplored[_x][_y] != true, "MAPS: locaiton already explored");
        // Do not let exploration happen in newbie area
        require(_x > 5, "MAPS: cannot explore in this area");
        require(_y > 5, "MAPS: cannot explore in this area");
        isExplored[_x][_y] = true;
        // explore NOVA cost
        uint _rand1 = Helper.createRandomNumber(10);
        // need to fix to not emit "nonewplace" for all loop iterations
        // loop to look for other stars
         for(uint i=_x-5; i<=_x+5;i++) {
             for(uint j=_y-5; j<=_y+5;j++) {
                 // checks if any placetypes returned are a star type
                 if (Helper.isEqual(coordinatePlaces[i][j].placeType, placeTypes[0])) { // change to while loop?
                     
                     // if there is a star
                     // check to see if a jackpot planet can be made
                     if (_rand1 > 9) { // 10% chance of creating jackpot planet
                        for(uint k=_x-2; i<=_x+2;k++) {
                            for(uint l=_y-2; l<=_y+2;l++) {
                                if (Helper.isEqual(coordinatePlaces[k][l].placeType, placeTypes[1])) {
                                    // do nothing
                                } else {
                                    setPlace(_x, _y, _name, placeTypes[1], false, false, true);
                                    uint _starId = PlaceManager.getStarId(_x, _y);
                                    PlaceManager.createJackpot(_starId, _x, _y);
                                    emit NewPlace(_x, _y, placeTypes[1], _name);
                                    break;
                                }
                            }
                        }
                     } 
                     // if a jackpot planet is not made, check if a shipyard can be made
                     else if (_rand1 <3) { // 20% chance of creating shipyard planet
                         if (Helper.isEqual(coordinatePlaces[i][j].placeType, placeTypes[3])) {
                            // do nothing

                         } else {
                             setPlace(_x, _y, _name, placeTypes[3], true, true, true);
                             // insert shipyard creation function
                             emit NewPlace(_x, _y, placeTypes[3], _name);
                             break;
                         }
                     }

                // if there is not a star
                 }  else if (_rand1 >5) {
                         setPlace(_x, _y, _name, placeTypes[0], false, false, true);
                         PlaceManager.createStar(_x, _y);
                         emit NewPlace(_x, _y, placeTypes[0], _name);
                         break;
                 } else {
                         // do nothing
                 }
                
             }
         }

    }

    function setExplorationOn (bool _isActive) external onlyOwner {
        explorationOn = _isActive;
    }

    // currently no check for duplicates
    function addPlaceType(string memory _name) external onlyOwner {
        placeTypes.push(_name);
    }

    function setPlaceManager(address _new) external onlyOwner {
        require(_new != address(0));
        PlaceManager = IPlaceManager(_new);
    }

}
