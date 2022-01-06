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

    // Jackpot planets can pull the rewards from the shadowPool
    modifier onlyJackpot {
        require(isJackpot(msg.sender));
        _;
    }

    function isJackpot(address _jackpot) public view returns(bool) {
        return jackpot[_jackpot] == true ? true : false;
    }

    function addJackpot(address[] memory _jackpot) external onlyOwner {
        for (uint i = 0; i < _jackpot.length; i++) {
        require(jackpot[_jackpot[i]] == false, "DRYDOCK: Address is already a jackpot");
        jackpot[_jackpot[i]] = true;
        }
    }

    // Deactivate a jackpot
    function deactivateJackpot ( address _jackpot) public onlyOwner {
        require(jackpot[_jackpot] == true, "DRYDOCK: Address is not a jackpot");
        jackpot[_jackpot] = false;
    }

    function initialDeposit() external onlyOwner {
        uint _amount = IERC20(token).balanceOf(address(this));
        Rewards.deposit(pid, _amount);
    }

    function replenish(address _jackpot, uint _value) external onlyJackpot returns(uint){
        Rewards.deposit(pid, 0);
        require(_value < 100, "SHADOWPOOL: value must be less than 100% of the pool balance");
        uint _amount = IERC20(token).balanceOf(address(this)) * _value / 100;
        Nova.transferFrom(address(this), _jackpot, _amount);
        return _amount;
    }
}