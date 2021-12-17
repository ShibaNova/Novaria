// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IDryDock.sol";
import "./interfaces/IPlanets.sol";

// This contract sets a planet as the jackpot planet. The jackpot planet
// is a location that collects NOVA emissions and stores them until a 
// player comes to collect them. 
// The players have to stage their fleets for travel to the planet, 
// travel to the planet, start collecting NOVA, and then return.
// To get to the jackpot planet, everyone has to travel through an
// asteroid field that has few clear paths through. Due to this,
// players often have to fight with other players going to and from the 
// jackpot planet. 

contract JackPot is Ownable {



}