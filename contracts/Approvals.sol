// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/ShibaBEP20.sol";

// Contract to create a button for users to approve all NOVARIA contracts.
// If there are multiple new contracts to replace, it may be better to just
// redeploy this contract with only the necessary contracts to save gas.
contract Approvals is Ownable {

    constructor(
        ShibaBEP20 _Nova
    ) {
        Nova = _Nova;
    }

    ShibaBEP20 public Nova; // Nova token
    mapping (address => bool) public contractApproval;
    address[] addressList;
    uint256 max = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    function addContract(address _contract, bool _isActive) public onlyOwner {
        for (uint i=0; i < addressList.length; i++) {
            require(addressList[i] != _contract, "APPROVALS: contract already added");
        }
        contractApproval[_contract] = _isActive;
        addressList.push(_contract);
    }

    function editContract(address _contract, bool _isActive) external onlyOwner {
        for (uint i=0; i < addressList.length; i++) {
            require(addressList[i] == _contract, "APPROVALS: contract not added");
        }
        contractApproval[_contract] = _isActive;
    }

    function approveAll(address _sender) external {
        for (uint i=0; i < addressList.length; i++) {
            if (contractApproval[addressList[i]] == true) {
                Nova.approve(addressList[i], max);
            }
        }
    }
}