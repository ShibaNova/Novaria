// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

library Helper {

    function isEqual(string memory _str1, string memory _str2) internal pure returns (bool) {
        if(keccak256(abi.encodePacked(_str1)) == keccak256(abi.encodePacked(_str2))) {
            return true;
        }
        return false;
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

    function indexOf(address[] memory A, address a) internal pure returns (uint256, bool) {
        uint256 length = A.length;
        for (uint256 i = 0; i < length; i++) {
            if (A[i] == a) {
                return (i, true);
            }
        }
        return (0, false);
    }

    // get next UTC hour as an epoch timestamp, used for sorting launch groups
    // ex) 1756 UTC returns 1800 UTC
    // _time must be a block.timestamp
    function getLaunchHour(uint _time) public pure returns(uint) {
        return ((_time + 3600 - 1) / 3600 ) * 3600;
    }

    // Create random number <= _mod
    function createRandomNumber (uint _mod) internal view returns(uint){
        return uint(keccak256(abi.encodePacked(block.timestamp, blockhash(20)))) % _mod;
    }

    function getDistance(uint x1, uint y1, uint x2, uint y2) internal pure returns (uint) {
        uint x = (x1 > x2 ? (x1 - x2) : (x2 - x1));
        uint y = (y1 > y2 ? (y1 - y2) : (y2 - y1));
        return _sqrt(x**2 + y**2);
    }
}

