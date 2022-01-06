// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;


import "./interfaces/ITreasury.sol";
import "./interfaces/IFleet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libs/ShibaBEP20.sol";
import "./libs/Editor.sol";

// interface for the MasterShiba farming contract
interface IRewardsPool {
    function deposit(uint256 _pid, uint256 _amount) external;
    function pendingNova(uint256 _pid, address _user) external view returns (uint256);
}
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

contract JackPotManager is Editor {

    IRewardsPool public Rewards; // MasterShiba farming contract
    ShibaBEP20 public Nova; // NOVA Token
    IFleet public Fleet; // Fleet Contract

    JackPot[] public jackpot; // ordered list of jackpot planets
    mapping (uint => mapping (uint => uint)) jackpotCoords; // assigns coords to jackpot ID

    uint public pid; // pool id for the specified shadow pool token
    address public token; // token used for the shadow pool
    uint public rewardsBalance; // balance of NOVA minus unrefined NOVA in the contract
    uint public unrefinedNova; // current balance of NOVA that is unrefined (mined but not refined) for the contract

    // mapping (address => mapping(uint => uint)) playerUnrefinedNova; // unrefined nova from jackpot location

    constructor (
        IRewardsPool _rewards,
        ShibaBEP20 _nova,
        IFleet _fleet,
        uint _pid,
        address _token
    ) {
        Rewards = _rewards;
        Nova = _nova;
        Fleet = _fleet;
        pid = _pid;
        token = _token;
    }

    struct JackPot {
        uint coordX;
        uint coordY;
        uint8 starDist;
        uint novaBalance;
        uint unrefinedBalance;
    }



    // after deploying and sending the shadow token to this contract, 
    // use this function to setup the pool deposit
    function initialDeposit() external onlyOwner {
        uint _amount = IERC20(token).balanceOf(address(this));
        Rewards.deposit(pid, _amount);
    }

    // calls the farming contract deposit function with the set pid and amount of 0 to harvest rewards 
    function _refill() internal {
        Rewards.deposit(pid, 0);
    }

    // gets the current pending nova from the farm contract awaiting harvest
    function getPendingRewards() public view returns(uint){
        return Rewards.pendingNova(pid, address(this));
    }

    // transfers NOVA from this contract to the owner, used for contract maintenance 
    function withdrawNOVA(uint _amount) external onlyOwner {
        Nova.transfer(msg.sender, _amount);
    }

    // transfers the shadow token to the owner, used for maintenance
    function withdrawToken(uint _amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, _amount);
    }


}