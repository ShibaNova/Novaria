// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libs/ShibaBEP20.sol";
import "./libs/Editor.sol";

// The shadow pool is a contract that manages a single-token
// staking pool. The goal of this is to divert funds from the 
// farming contract by being the only owner of the token in the 
// staking pool. Then this contract can disburse the emissions.

interface IRewardsPool {
    function deposit(uint256 _pid, uint256 _amount) external;
}

contract ShadowPool is Editor {

    IRewardsPool public Rewards;
    ShibaBEP20 public Nova;

    uint public pid;
    address public token;

    mapping(address => bool) public jackpot;

    constructor (
        IRewardsPool _rewards,
        ShibaBEP20 _nova,
        uint _pid,
        address _token
    ) {
        Rewards = _rewards;
        Nova = _nova;
        pid = _pid;
        token = _token;
    }

    // after deploying and sending the shadow token to this contract, 
    // use this function to setup the pool deposit
    function initialDeposit() external onlyOwner {
        uint _amount = IERC20(token).balanceOf(address(this));
        Rewards.deposit(pid, _amount);
    }

    // gets the current pending nova from the farm contract awaiting harvest
    function getPendingRewards() public view returns(uint){
        return Rewards.pendingNova(pid, address(this));
    }
    function replenishPlace(address _jackpot, uint _value) external onlyEditor returns(uint){
        Rewards.deposit(pid, 0);
        require(_value <= 100, "SHADOWPOOL: value must be less than 100% of the pool balance");
        uint _amount = IERC20(token).balanceOf(address(this)) * _value / 100;
        Nova.transferFrom(address(this), _jackpot, _amount);
        return _amount;
    }

    // transfers the shadow token to the owner, used for maintenance
    function withdrawToken(uint _amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, _amount);
    }

    // transfers NOVA from this contract to the owner, used for contract maintenance 
    function withdrawNOVA(uint _amount) external onlyOwner {
        Nova.safeTransfer(msg.sender, _amount);
    }
}