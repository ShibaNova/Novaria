// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./interfaces/IFleet.sol";
import "./interfaces/IShadowPool.sol";
import "./interfaces/IMap.sol";
import "./libs/ShibaBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./libs/Editor.sol";
import "./libs/Helper.sol";

/*
 This contract sets a planet as the jackpot planet. The jackpot planet
 is a location that collects NOVA emissions and stores them until a 
 player comes to collect them. 
 The players have to stage their fleets for travel to the planet, 
 travel to the planet, start collecting NOVA, and then return.
 To get to the jackpot planet, everyone has to travel through an
 asteroid field that has few clear paths through. Due to this,
 players often have to fight with other players going to and from the 
 jackpot planet. 
*/

/* TO-DO
- pause function
- planet mining
- combat
- unrefinedNova function
*/

contract PlaceManager is Editor {
    using SafeBEP20 for ShibaBEP20;
    
    constructor (
        IMap _map,
        ShibaBEP20 _nova,
        IFleet _fleet,
        IShadowPool _shadowPool
    ) {
        Map = _map;
        ShadowPool = _shadowPool;
        Nova = _nova;
        Fleet = _fleet;
        rewardsMod = 1;
        previousBalance = 0;
        rewardsTimer = 0;
    }

    IMap public Map;
    IShadowPool public ShadowPool;
    ShibaBEP20 public Nova; // NOVA Token
    IFleet public Fleet; // Fleet Contract
    uint public rewardsMod; // = x/100, the higher the number the more rewards sent to this contract
    uint previousBalance; // contract balance before added Nova
    uint rewardsTimer; // Rewards can only be pulled from shadow pool every 4 hours?

    Jackpot[] public jackpots; // ordered list of jackpot planets
    mapping (uint => mapping (uint => uint)) jackpotCoords; // assigns coords to jackpot ID
    Star[] public stars; // ordered list of stars
    mapping (uint => mapping (uint => uint)) starCoords; // assigns coords to star ID

    uint public starTotal; // sum of the size of all stars, denominator of NOVA allocation
    mapping (uint => uint) public jackpotTotal; // sum of jackpot starDist for a given star, denominator of NOVA allocaiotn
    // User => star => unrefinedNova. Player's current UNova and where is comes from
    mapping(address => mapping(uint => uint)) userUNova;
  
    struct Jackpot {
        uint coordX;
        uint coordY;
        uint starDist; // distance from star determines numerator NOVA allocation between planets of the same star
        uint availableNova;
        uint starId;
    }

    struct Star {
        uint coordX;
        uint coordY;
        uint size; // size determines numerator of NOVA allocation between stars
        uint novaBalance;
        uint unrefinedBalance;
    }

    // transfers NOVA from this contract to the owner, used for contract maintenance 
    function withdrawNOVA(uint _amount) external onlyOwner {
        Nova.safeTransfer(msg.sender, _amount);
    }

    // currently onlyOwner, soon by player exploration
    function createStar (uint _x, uint _y) public onlyOwner {
        // add requirement for duplicates
        // add requirements for placement parameters
        uint _size = Helper.createRandomNumber(10);
        _createStar(_size, _x, _y);
    }

    function _createStar (uint _size, uint _x, uint _y) internal {
        // add requirement for duplicates
        // add requirements for placement parameters
        uint _id = stars.length;
        stars.push(Star(_x, _y, _size, 0, 0));
        starCoords[_x][_y] = _id;
        starTotal = starTotal + _size;
    }

    function createJackpot(uint _starId, uint _x, uint _y) public onlyOwner {
        // add requirement for duplicates
        // add requirements for placement parameters
        uint starX = stars[_starId].coordX;
        uint starY = stars[_starId].coordY;
        uint _dist = Helper.getDistance(starX*10, starY*10, _x*10, _y*10);
        _createJackpot(_dist, _starId, _x, _y);
    }

    function _createJackpot(uint _dist, uint _starId, uint _x, uint _y) internal {
        // add requirement for duplicates
        // add requirements for placement parameters
        uint _id = jackpots.length;
        jackpots.push(Jackpot(_x, _y, _dist, 0, _starId));
        jackpotCoords[_x][_y] = _id;
        jackpotTotal[_starId] = jackpotTotal[_starId] + _dist;
    }

    // set this to internal at some point?
    function allocateNova() public {
        uint _amount = Nova.balanceOf(address(this)) - previousBalance;
        require(_amount > 0, "PLACEMANAGER: no Nova to allocate");
            for (uint i = 0; i < stars.length; i++) {
                uint _allocation = (_amount * stars[i].size / starTotal);
                stars[i].novaBalance = stars[i].novaBalance + _allocation;
                for (uint j = 0; j < jackpots.length; j++) {
                    if (jackpots[j].starId == i) {
                        jackpots[j].availableNova = 
                            jackpots[j].availableNova + (_allocation * jackpots[j].starDist / jackpotTotal[i]);
                    }
                }
            }
        previousBalance = Nova.balanceOf(address(this));
    }

    function setRewardsMod(uint _new) external onlyOwner {
        require(_new <= 100, "PLACEMANAGER: must be <= 100");
        rewardsMod = _new;
    }

    // Pulls nova from the shadow pool
    function requestNova() external onlyOwner{
        if (block.timestamp >= rewardsTimer) {
            ShadowPool.replenishPlace(address(this), rewardsMod);
            rewardsTimer = block.timestamp + 14400;
            allocateNova();
        }
    }

    // function to set ID = 0 of sun and jackpot to coords 0,0 with 0 rewards. 
    // this is required for contract logic to work
    function setInitial() public onlyOwner {
        _createStar(0, 0, 0);
        _createJackpot(0, 0, 0, 0);
    }

    function getJackpotNova(uint _x, uint _y) external view returns (uint) {
         uint _jackpotId = jackpotCoords[_x][_y];
         return jackpots[_jackpotId].availableNova;
    }

    function harvest(uint _x, uint _y) external {
        address _sender = msg.sender;
        uint _playerX;
        uint _playerY;
        (_playerX,) = Map.getPlayerLocation(_sender);
        (,_playerY) = Map.getPlayerLocation(_sender);
        require(_playerX == _x && _playerY == _y, "PLACEMANAGER: Fleet is not here");
        require(jackpotCoords[_x][_y] != 0, "PLACEMANAGER: No jackpot planet located here");
        // uint maxHarvest = Fleet.getNovaCapacity[_player] - getUserUNova(_sender);
        //link to fleets, will have to edit maxHarvest with above
        uint maxHarvest = 10**18;
        uint _jackpotId = jackpotCoords[_x][_y];
        uint _starId = jackpots[_jackpotId].starId;
        uint _amount;
        if (maxHarvest > 0 && jackpots[_jackpotId].availableNova >= maxHarvest) {
            _amount = maxHarvest;
        } else if (maxHarvest > 0 && jackpots[_jackpotId].availableNova < maxHarvest) {
            _amount = jackpots[_jackpotId].availableNova;
        } else {
            _amount = 0;
        }
        jackpots[_jackpotId].availableNova = jackpots[_jackpotId].availableNova - _amount;
        stars[_starId].unrefinedBalance = stars[_starId].unrefinedBalance + _amount;
        require(stars[_starId].unrefinedBalance <= stars[_starId].novaBalance, "PLACEMANAGER: Star does not have enough nova");
        userUNova[_sender][_starId] = userUNova[_sender][_starId] + _amount;
    }

    function refine() external {
        address _sender = msg.sender;
        uint _x;
        uint _y;
        (_x,) = Map.getPlayerLocation(_sender);
        (,_y) = Map.getPlayerLocation(_sender);
        require(Map.isRefinery(_x, _y) == true, "PLACEMANAGER: fleet not at a refinery");
        uint _total;
        for (uint i=0; i < stars.length; i++) {
            uint _amount = userUNova[_sender][i];
            userUNova[_sender][i] = 0;
            stars[i].novaBalance = stars[i].novaBalance - _amount;
            stars[i].unrefinedBalance = stars[i].unrefinedBalance - _amount;
            _total = _total + _amount;
        }
        Nova.safeTransfer(_sender, _total);
    }

    // remember to set to onlyEditor
    // Allows players to take unrefined nova from other players
    function transferUNova(address _sender, address _receiver, uint _percent) external {
        //uint _amount = ((getUserUNova(_sender) * _percent / 100) <= (Fleet.getNovaCapacity[_player] - getUserUNova(_sender)) ? (getUserUNova(_sender) * _percent / 100) : (Fleet.getNovaCapacity[_player] - getUserUNova(_sender)));
        // replace _amount with previous line when we have fleet data
        uint _amount = (getUserUNova(_sender) * _percent / 100);
        for (uint i=0; i < stars.length; i++) {
            while (_amount > 0) {
                if (userUNova[_sender][i] >= _amount) {
                    uint _transfer = _amount;
                    _amount = 0;
                    userUNova[_sender][i] = userUNova[_sender][i] - _transfer;
                    userUNova[_receiver][i] = userUNova[_receiver][i] + _transfer;
                } else {
                    uint _transfer = userUNova[_sender][i];
                    _amount = _amount - _transfer;
                    userUNova[_sender][i] = userUNova[_sender][i] - _transfer;
                    userUNova[_receiver][i] = userUNova[_receiver][i] + _transfer;
                }
            }
        }
    }

    function getUserUNova(address _player) public view returns(uint){
        uint currentUNova;
        for (uint i=0; i < stars.length; i++) {
            currentUNova = currentUNova + userUNova[msg.sender][i];
        }
        return currentUNova;
    }
}