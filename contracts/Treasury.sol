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
        dev1 = 0x509CC3b01e4e4BD8CE810AA9C10D89d05E0FB03A;
        dev2 = 0xa12C28e569a7564420aa437F3d3dA29aED648707;
        team = 0x729F3cA74A55F2aB7B584340DDefC29813fb21dF;
        costModifier = 100;
        moneyPotRate = 80;
        coderRoyaltiesRate = 4;
        teamRate = 6;
    }

    uint costModifier;
    uint public moneyPotRate; // initially 80% of funds go directly to money pot
    uint public teamRate; // payment for full time people
    uint public coderRoyaltiesRate; // dev royalties
    address public feeManager; // address that handles the money pot
    ShibaBEP20 public Token; // nova token address
    uint public totalWithdrawn; // total amount of fees withdrawn
    uint public totalDeposit; // total amount of fees collected in Treasury
    uint public totalPot; // total amount of fees sent to the feeManager (money pot)
    uint public totalFee; // total fees paid in the game
    address dev1; 
    address dev2;
    address team;

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
        deposit(_from, _amount *(100-moneyPotRate-teamRate-coderRoyaltiesRate) / 100);
        Token.safeTransferFrom(_from, feeManager, _amount * moneyPotRate / 100);
        Token.safeTransferFrom(_from, dev1, _amount * coderRoyaltiesRate / 2 / 100);
        Token.safeTransferFrom(_from, dev2, _amount * coderRoyaltiesRate / 2 / 100);
        Token.safeTransferFrom(_from, team, _amount * teamRate / 100);
        totalPot = totalPot + ( _amount * moneyPotRate / 100);
        totalFee = totalFee + _amount;
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

    function getCostMod() external view returns(uint) {
        return costModifier;
    }

    function setCostMod(uint _new) external onlyOwner {
        costModifier = _new;
    }

    function approveContract(address _contract) external onlyOwner {
        Token.approve(_contract, 0xffffffffffffffffff);
    }

}