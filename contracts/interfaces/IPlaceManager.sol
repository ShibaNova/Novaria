// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IPlaceManager {
    function createStar (uint _x, uint _y) external;
    function createJackpot(uint _starId, uint _x, uint _y) external;
    function getJackpotNova(uint _x, uint _y) external view returns (uint);
    function transferUNova(address _sender, address _receiver, uint _percent) external;
    function getUserUNova(address _player) external view returns(uint);
    function getStarId(uint _x, uint _y) external view returns (uint);
} 