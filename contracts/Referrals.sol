pragma solidity ^0.8.7;


import "./libs/ShibaBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./libs/Editor.sol";

interface IFleet {
    function playerExists(address _player) external view returns (bool);
}

contract Referrals is Editor {
    using SafeBEP20 for ShibaBEP20;

    constructor(
        ShibaBEP20 _token,
        IFleet _fleet
    ) {
        Token = _token;
        Fleet = _fleet;
        referralRate = 25000000000000000000;
    }

    ShibaBEP20 public Token; // nova token address
    IFleet public Fleet; // fleet contract
    uint public referralRate; // how much token per referral

    mapping (address => bool) public addressReferred; // checks if referral is already registered
    mapping (address => bool) public  referralAddressPaid;
    mapping (address => address) public getReferrer; 
    mapping (address => uint) public referralBalance; // current generated balance minus previously withdrawn
    mapping (address => address[]) public referralsByAddress;

    // Step 1 - new user has to use this function to approve the referrer before joining the game
    function addReferral (address _referrer) external {
        address referred = msg.sender;
        require(addressReferred[referred] == false, 'REFERRALS: USER ALREADY REGISTERED REFERRAL');
        require(Fleet.playerExists(referred) == false, 'REFERRALS: USER ALREADY REGISTERED');
        addressReferred[referred] = true;
        getReferrer[referred] = _referrer;
        referralsByAddress[_referrer].push(referred);
    }

    function checkReferrals (address _referrer) external view returns(uint) {
        uint pendingReferrals;
        for (uint i = 0; i < referralsByAddress[_referrer].length; i++) {
            if (Fleet.playerExists(referralsByAddress[_referrer][i]) == true && referralAddressPaid[referralsByAddress[_referrer][i]] == false) {
                pendingReferrals++;
            }
        }
        return pendingReferrals;
    }

    function getReferralBonus () external {
        address referrer = msg.sender;
        uint pendingReferrals;
        // Check if a referred wallet has bought the game
        for (uint i = 0; i < referralsByAddress[referrer].length; i++) {
            if (Fleet.playerExists(referralsByAddress[referrer][i]) == true && referralAddressPaid[referralsByAddress[referrer][i]] == false) {
                pendingReferrals++;
                referralAddressPaid[referralsByAddress[referrer][i]] = true;           
            }
        }
        // Clean up addresses that bought in, doesn't have to be perfect
        for (uint i = 0; i < referralsByAddress[referrer].length; i++) {
            if (referralAddressPaid[referralsByAddress[referrer][i]]) {
                referralsByAddress[referrer][i] = referralsByAddress[referrer][referralsByAddress[referrer].length-1];
                referralsByAddress[referrer].pop();
            }
        }
        require(Token.balanceOf(address(this)) >= (referralRate * pendingReferrals), 'REFERRAL: Not enough token to pay out referrals, contact Dev team');
        Token.safeTransfer(referrer, (referralRate * pendingReferrals));
    }

    // be sure to use appropriate decimals
    function setReferralRate (uint _newRate) external onlyOwner {
        referralRate = _newRate; 
    }

    function withdraw (address _recipient, uint _amount) external onlyOwner {
        Token.safeTransfer(_recipient, _amount);
    }
}