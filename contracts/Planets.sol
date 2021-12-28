// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Planets is Ownable {

    // simple contract to provide an array of planets that can be used 
    // as destinations for other contracts

    struct Planet {
        string name;
        uint distance;
        uint x;
        uint y;
    }

    Planet[] public planets;

    function planetsLength() external view returns (uint) {
        return planets.length;
    }

    function createPlanet (string memory _name, uint _distance) external onlyOwner {
        planets.push(Planet({name: _name, distance: _distance}));
    }

    function getPlanetInfo (uint _id) external view returns (string memory name, uint distance) {
        return (planets[_id].name, planets[_id].distance);
    }
}




function prepareLaunch ()
    uint launchTime = block.timestamp round up to next hour;


function cancelLaunch ()


function launchTravel()
    require(current timestamp < launchTime + 15 minutes?)
    uint arrival = launchTime + 8hrs;