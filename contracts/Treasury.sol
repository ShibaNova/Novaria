// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/ShibaBEP20.sol";

contract Treasury is Ownable {

    constructor(
        ShibaBEP20 _Nova,
        address _feeManager
    ) {
        Nova = _Nova;
        feeManager = _feeManager;
    }

    address public feeManager; // address that handles the money pot
    ShibaBEP20 public Nova; // nova token address
    uint public moneyPotRate = 80; // initially 80% of funds go directly to money pot
    uint public totalWithdrawn; // total amount of fees withdrawn
    uint public totalPot; // total amount of fees sent to the feeManager (money pot)

    event NewMoneyPotRate(uint newRate);
    event NewFeeManager(address newFeeManager);
    event NewNovaAddress(address newNova);

    mapping (address => bool) public distributor;

    // distributors can manage the funds sent to the treasury
    modifier onlyDistributor {
        require(isDistributor(msg.sender));
        _;
    }

    function isDistributor(address _distributor) public view returns(bool) {
        return distributor[_distributor] == true ? true : false;
    }

    function addDistributor(address[] memory _distributor) external onlyOwner {
        for (uint i = 0; i < _distributor.length; i++) {
        require(distributor[_distributor[i]] == false, "DRYDOCK: Address is already a distributor");
        distributor[_distributor[i]] = true;
        }
    }
    // Deactivate a distributor
    function deactivateDistributor ( address _distributor) public onlyOwner {
        require(distributor[_distributor] == true, "DRYDOCK: Address is not a distributor");
        distributor[_distributor] = false;
    }

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

    // function for treasury to send funds to the fee manager
    function _sendFee() internal {
        uint _amount = Nova.balanceOf(address(this)) * moneyPotRate / 100;
        Nova.transfer(feeManager, _amount);
        totalPot = totalPot + _amount;
    }

    function deposit(address _from, uint _amount) external {
        Nova.transferFrom(_from, address(this), _amount);
        _sendFee();
    }

    // function to withdraw fees from Treasury
    function withdraw (address _recipient, uint _amount) public onlyDistributor {
        Nova.transfer(_recipient, _amount);
        totalWithdrawn = totalWithdrawn + _amount;
    }
}