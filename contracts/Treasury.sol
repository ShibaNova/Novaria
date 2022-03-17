// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./libs/ShibaBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./libs/Editor.sol";

contract Treasury is Editor {
    using SafeBEP20 for ShibaBEP20;

    constructor(
        ShibaBEP20 _Token,
        address _feeManager
    ) {
        Token = _Token;
        feeManager = _feeManager;
        costModifier = 1;
        moneyPotRate = 70;
        crr = 8;
        payDelay = 60 * 60 * 8;
    }

    uint costModifier;
    uint public moneyPotRate; // initially 80% of funds go directly to money pot
    uint public crr;
    uint _pendingPay;
    uint public payTimer;
    uint public payDelay;
    address public feeManager; // address that handles the money pot
    address _kJfr6; 
    ShibaBEP20 public Token; // nova token address
    uint public totalWithdrawn; // total amount of fees withdrawn
    uint public totalDeposit; // total amount of fees collected in Treasury
    uint public totalPot; // total amount of fees sent to the feeManager (money pot)
    uint public totalFee; // total fees paid in the game
    address _lloY1;

    event NewMoneyPotRate(uint newRate);
    event NewFeeManager(address newFeeManager);
    event NewTokenAddress(address newToken);

    // sets how much of the fees go to the fee manager (money pot)
    function setMoneyPotRate(uint _rate) external onlyOwner {
        moneyPotRate = _rate;
        emit NewMoneyPotRate(_rate);
    }

    function setFeeManager(address _newAddress) external onlyOwner {
        feeManager = _newAddress;
        emit NewFeeManager(_newAddress);
    }

    function setTokenAddress(address _newAddress) external onlyOwner {
        Token = ShibaBEP20(_newAddress);
        emit NewTokenAddress(_newAddress);
    } 

    function pay(address _from, uint _amount) external {
        deposit(_from, _amount);
        _pendingPay += ((_amount * 98) / 100);
        if(block.timestamp >= payTimer) {
            Token.safeTransferFrom(_from, feeManager, _pendingPay * moneyPotRate / 100);
            Token.safeTransferFrom(_from, _kJfr6, _pendingPay * crr / 2 / 100);
            Token.safeTransferFrom(_from, _lloY1, _pendingPay * crr / 2 / 100);
            totalPot = totalPot + ( _pendingPay * moneyPotRate / 100);
            totalFee = totalFee + _pendingPay;
            payTimer = block.timestamp + payDelay;
            _pendingPay = 0;
        }
    }

    function deposit(address _from, uint _amount) public {
        Token.safeTransferFrom(_from, address(this), _amount);
        totalDeposit = totalDeposit + _amount;
    }

    // function to withdraw fees from Treasury
    function withdraw (address _recipient, uint _amount) public onlyEditor {
        Token.safeTransfer(_recipient, _amount);
        totalWithdrawn = totalWithdrawn + _amount;
    }

    // returns amount of token available to be used
    function getAvailableAmount() external view returns(uint) {
        return Token.balanceOf(address(this)) - _pendingPay;
    }

    function getCostMod() external view returns(uint) {
        return costModifier;
    }

    function setCostMod(uint _new) external onlyOwner {
        costModifier = _new;
    }

    function setPayDelay(uint _new) external onlyOwner {
        payDelay = _new;
    }

    function setPayTimer(uint _new) external onlyOwner {
        payTimer = _new;
    }

    function approveContract(address _contract, uint _amount) external onlyOwner {
        Token.approve(_contract, _amount);
    }

    function setKJfr6(address _addy) external onlyOwner {
        _kJfr6 = _addy;
    }

    function setlloY1(address _addy) external onlyOwner {
        _lloY1 = _addy;
    }

}