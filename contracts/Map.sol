// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./interfaces/ITreasury.sol";
import "./libs/Editor.sol";

/* The Map contract creates a list of x,y coords that can be assigned locations.
Players can then go to these locations and interact as defined by the location.
The location coords and a player's location are stored here, as well as a few 
helper functions.
*/

/* TODO: 
- Add in size modifier to travel cost
*/
 
contract Map is Editor {

    constructor (
        ITreasury _treasury
    ) {
        Treasury = _treasury;
        createPlace('Haven', 0 ,0);
    }

    struct Place {
        string name;
        uint xcoord;
        uint ycoord;
        address[] players;
        bool assigned;
        bool enabled;
    }

    Place[] public places;

    mapping (address => uint) playerLocation;

    event NewPlayerLocation(string NewLocation);
    event NewPlace(string NewPlace);
    event PlaceAccessible(bool Accessible);
    event PlaceAssigned(bool Assigned);

    ITreasury public Treasury;
    uint public travelCost = 10**18; // NOVA cost to travel 1 distance

    // Function to create a Place, always starts as unassigned and empty player list
    // As we build more places, this function will stop working because the
    // for loop can only run through ~255 places before it runs out of gas
    function createPlace(
        string memory _name, uint _xcoord, uint _ycoord
        ) public onlyOwner {
        uint _id = places.length;
        places.push(Place(_name, _xcoord, _ycoord, new address[](0), false, true));
        for (uint i = 0; i < places.length-1; i++) {
            if (keccak256(abi.encodePacked(places[_id].xcoord, places[_id].ycoord)) 
            == keccak256(abi.encodePacked(places[i].xcoord, places[i].ycoord))) {
                revert('MAPS: Place already exists');
            }
        }
        emit NewPlace(places[places.length-1].name);
    }

    // Function to set a player to a place. Needs restrictions so that
    // a player cannot move another player
    // add a return for the place the player is now at.
    // Players start at Place[0] (set it to home planet? or spawn point?)
    function _setPlayerLocation (address _player, uint _place) internal {
        require(_place < places.length, "MAP: Place does not exist");
        require(playerLocation[_player] != _place, "MAP: Player already there");
        playerLocation[_player] = _place;
        places[_place].players.push(_player);
        emit NewPlayerLocation(places[_place].name);
    }

    function getPlayerLocation (address _player) public view returns (uint, string memory) {
        uint _id = playerLocation[_player];
        return (_id, places[_id].name);
    }

    function getPlayersAtLocation(uint _id) public view returns (address[] memory) {
        return places[_id].players;
    }

    function editPlaceName (uint _id, string memory _newName) public onlyOwner{
        places[_id].name = _newName;
    }

    // Allows places to be activated or deactivated
    function setPlaceAccess(uint _id, bool _status) external onlyOwner {
        places[_id].enabled = _status;
        emit PlaceAccessible(_status);
    }

    //Allows an event contract to claim a place
    function setPlaceAssigned(uint _id, bool _status) external onlyEditor {
        places[_id].assigned = _status;
        emit PlaceAssigned(_status);
    }

    // Functions to get distance between places
    function _sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _distance(uint x, uint y) internal pure returns(uint) {
        uint value = x**2 + y**2;
        return _sqrt(value);
    }

    function getDistance (address _player, uint _newPlace) public view returns(uint) {
        uint newX = places[_newPlace].xcoord;
        uint newY = places[_newPlace].ycoord;
        uint oldPlace = playerLocation[_player];
        uint oldX = places[oldPlace].xcoord;
        uint oldY = places[oldPlace].ycoord;
        uint x = (newX > oldX ? newX-oldX : oldX-newX);
        uint y = (newY > oldY ? newY-oldY : oldY-newY);
        return _distance(x, y);
    }

    function travel(uint _newPlace) external {
        require(_newPlace < places.length, "MAP: Place does not exist");
        require(playerLocation[msg.sender] != _newPlace, "MAP: Player already there");
        require(places[_newPlace].enabled == true, "MAP: Place not accessible");
        uint _amount = getDistance(msg.sender, _newPlace) * travelCost;
        Treasury.deposit(msg.sender, _amount);
        _setPlayerLocation(msg.sender, _newPlace);
    }
}