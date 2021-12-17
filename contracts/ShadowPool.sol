// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";

// The shadow pool is a contract that manages a single-token
// staking pool. The goal of this is to divert funds from the 
// farming contract by being the only owner of the token in the 
// staking pool. Then this contract can disburse the emissions.

contract ShadowPool is Ownable {


}