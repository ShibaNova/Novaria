// SPDX-License-Identifier: MIT
 
pragma solidity 0.8.7;

import "./libs/Editor.sol";

contract Combat is Editor {

    // groups player's fleets together for mass battles
    struct LaunchGroup {
        uint earliestLaunchTime;
        uint fleetPower;
        uint arrivalTime;
        uint fleetID;
        bool hasLaunched;
    }

    LaunchGroup[] public launchGroups;

    
    // get next UTC hour as an epoch timestamp, used for sorting launch groups
    // ex) 1756 UTC returns 1800 UTC
    // _time must be a block.timestamp
    function getLaunchHour(uint _time) public pure returns(uint) {
        return ((_time + 3600 - 1) / 3600 ) * 3600;
    }

    // function to check to see if there is a launch group already initiated for 
    // the current hour
    function isLaunchGroupAvailable() public view returns(bool) {
        for (uint i = 0; i < launchGroups.length; i++) {
            if (launchGroups[i].earliestLaunchTime == getLaunchHour(block.timestamp)) {
                return true;
            } else {
                return false;
            }
        }
    }

    // Join or create a launch group
    function prepareLaunch() external {
        require(DryDock.getLaunchStatus(msg.sender) == false, "JACKPOT: Fleet is already busy elsewhere");
        DryDock.setLaunched(msg.sender, true);
        if (isLaunchGroupAvailable() == true) {
            _joinLaunch(msg.sender);
        } else {
            _createLaunch(msg.sender);
        }
    }

    // Join launch group function
    function _joinLaunch(address _player) internal {
            //complete this
    }

    // create launch group function 
    function _createLaunch(address _player) internal {
        uint _id = DryDock.getOwnerShipId(msg.sender);
        launchGroups.push(LaunchGroup({
            earliestLaunchTime: getLaunchHour(block.timestamp),
            fleetPower: 
            arrivalTime:
            fleetID:
            hasLaunched: false
        }))

    }
}