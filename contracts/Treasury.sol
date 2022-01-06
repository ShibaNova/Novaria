// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./libs/ShibaBEP20.sol";
import "./libs/Editor.sol";

contract Treasury is Editor {

    constructor(
        ShibaBEP20 _Nova,
        address _feeManager
    ) {
        Nova = _Nova;
        feeManager = _feeManager;
    }

    uint costModifier = 10;
    uint public moneyPotRate = 80; // initially 80% of funds go directly to money pot
    address public feeManager; // address that handles the money pot
    ShibaBEP20 public Nova; // nova token address
    uint public totalWithdrawn; // total amount of fees withdrawn
    uint public totalDeposit; // total amount of fees withdrawn
    uint public totalPaid; // total amount of fees sent to the feeManager (money pot)

    event NewMoneyPotRate(uint newRate);
    event NewFeeManager(address newFeeManager);
    event NewNovaAddress(address newNova);

    

    // sets how much of the fees go to the fee manager (money pot)
    function setMoneyPotRate(uint _rate) external onlyOwner {
        moneyPotRate = _rate;
        emit NewMoneyPotRate(_rate);
    }

    function setFeeManager(address _newAddress) external onlyOwner {
        feeManager = _newAddress;
        emit NewFeeManager(_newAddress);
    }

    function setNovaAddress(address _newAddress) external onlyOwner {
        Nova = ShibaBEP20(_newAddress);
        emit NewNovaAddress(_newAddress);
    } 

    function pay(address _from, uint _amount) external {
        deposit(_from, _amount *(100-moneyPotRate));
        Nova.transferFrom(_from, feeManager, _amount * moneyPotRate);
        totalPaid = totalPaid + (_amount *(100-moneyPotRate));
        totalPot = totalPot + ( _amount * moneyPotRate);
    }

    function deposit(address _from, uint _amount) external {
        Nova.transferFrom(_from, address(this), _amount);
        totalDeposit = totalDeposit + _amount;
    }

    // function to withdraw fees from Treasury
    function withdraw (address _recipient, uint _amount) public onlyEditor {
        Nova.transfer(_recipient, _amount);
        totalWithdrawn = totalWithdrawn + _amount;
    }
}