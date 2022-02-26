// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

library Helper {

    function isEqual(string memory _str1, string memory _str2) internal pure returns (bool) {
        return keccak256(abi.encodePacked(_str1)) == keccak256(abi.encodePacked(_str2));
    }

    function _sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // Create random number <= _mod
    function getRandomNumber(uint _mod) internal view returns(uint){
        return uint(keccak256(abi.encodePacked(block.timestamp, blockhash(20)))) % _mod;
    }

    function getDistance(uint x1, uint y1, uint x2, uint y2) internal pure returns (uint) {
        uint x = (x1 > x2 ? (x1 - x2) : (x2 - x1));
        uint y = (y1 > y2 ? (y1 - y2) : (y2 - y1));
        return _sqrt(x**2 + y**2);
    }

    //get minimum between 2 numbers
    function getMin(uint num1, uint num2) internal pure returns(uint) {
        if(num1 < num2) {
            return num1;
        }
        else {
            return num2;
        }
    }
}

