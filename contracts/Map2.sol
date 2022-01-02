// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./libs/Editor.sol";
import "./libs/Helper.sol";
import "./interfaces/ITreasury.sol";

contract Map2 is Editor {

    ITreasury public Treasury;
    uint public travelCost = 10**18; // NOVA cost to travel 1 distance

    // constructor (
    //     ITreasury _treasury
    // ) {
    //     Treasury = _treasury;
    // }

    struct PlaceType {
        string handle;
        address contractAddress;
        bool isActive;
    }

    PlaceType[] placeTypes;

    function getPlaceType(string memory _handle) public view returns(PlaceType memory) {
        for (uint i = 0; i < placeTypes.length; i++) {
            if (Helper.isEqual(placeTypes[i].handle, _handle)) {
                return placeTypes[i];
            }
        }
    }

    function addPlaceType(string memory _handle, address _contractAddress, bool _isActive) public {
        placeTypes.push(PlaceType(_handle, _contractAddress, _isActive));
        
    }

    struct Place {
        string name;
        PlaceType placeType;
        bool isDmz;
        bool isRefinery;
        bool isActive;
    }
    // Coordinates return the place
    mapping (uint => mapping(uint => Place)) public coordinatePlaces;
    // Use inputs of address and 0 or 1 to return coords (0=x, 1=y)
    mapping (address => uint[]) playerLocation; 

    // Coordinates return list of players at location
    mapping (uint => mapping(uint => address[])) playersAtLocation;
    

    // Creates a place at specified coordinates with a place type
    function setPlace(uint _x, uint _y, string  memory _name, string memory _placeType, bool _isDmz, bool _isRefinery, bool _isActive) public { 
        coordinatePlaces[_x][_y] = Place(_name, getPlaceType(_placeType), _isDmz, _isRefinery, _isActive);
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

    function getPlace(uint _x, uint _y) external view returns (Place memory) {
        return coordinatePlaces[_x][_y];
    }

    /* 
        Problem? - need to set initial location
    */
    function setInitialLocation() external {
        playerLocation[msg.sender] = [0, 0];
    }
    function _setPlayerLocation (address _player, uint _x, uint _y) public {
        uint x = playerLocation[_player][0];
        uint y = playerLocation[_player][1];
        _deletePlayerFromLocation(_player, x, y);
        playerLocation[_player] = [_x, _y];
        playersAtLocation[_x][_y].push(_player);
    }

    function _deletePlayerFromLocation (address _player, uint _x, uint _y) internal {
        for (uint i = 0; i < playersAtLocation[_x][_y].length; i++) {
            if (playersAtLocation[_x][_y][i] == _player) {
                playersAtLocation[_x][_y][i] == playersAtLocation[_x][_y][playersAtLocation[_x][_y].length-1];
                playersAtLocation[_x][_y].pop();
            }
            return;
        }
    }

    // Returns both x and y coordinates
    function getPlayerLocation (address _player) public view returns(uint x, uint y) {
        return (playerLocation[_player][0], playerLocation[_player][1]);
    }

    // Will this function cause errors when a place has hundreds of players?
    function getPlayersAtLocation (uint _x, uint _y) public view returns(address[] memory) {
       return playersAtLocation[_x][_y];
    }

    // Travel function, needs size modifier & restriciton on travel distance
    function travel( uint _x, uint _y) external {
        uint _amount = getDistance(msg.sender, _x, _y) * travelCost;
        Treasury.deposit(msg.sender, _amount);
        _setPlayerLocation(msg.sender, _x, _y);
    }

    function getDistance (address _player, uint _x, uint _y) public view returns(uint) {
        uint oldX = playerLocation[_player][0];
        uint oldY = playerLocation[_player][1];
        uint x = (_x > oldX ? _x-oldX : oldX-_x);
        uint y = (_y > oldY ? _y-oldY : oldY-_y);
        return _distance(x, y);
    }

    function _distance(uint x, uint y) internal pure returns(uint) {
        uint value = x**2 + y**2;
        return Helper._sqrt(value);
    }
}
