// SPDX-License-Identifier: MIT
 
pragma solidity 0.8.7;
 
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IDryDock.sol";
import "./interfaces/ITreasury.sol";
import "./libs/ShibaBEP20.sol";
 
/*
Ships contract is a database of the ships in player's fleets.
It connects to the DryDock contract to modify the power and
carryCapacity of the capital ship.
 
TO-DO:
- add value packs
- functions to get ship info
- function to set ship variables
*/
contract ShipYard is Ownable {
 
    // required contracts to interact
    ShibaBEP20 public Nova; // NOVA Token is game currency
    IDryDock public DryDock; // DryDock Contract manages the capital ship
    ITreasury public Treasury; // Treasury contract manages NOVA spending
 
    // List of Events
    event NewTreasury(address newAddress);
    event NewNovaAddress(address newNova);
    event NewDryDock(address newDryDock);
 
   
    // General Mappings
    mapping (address => bool) public purchaser; // addresses that can call functions in this contract
    mapping (address => bool) public building; // player can only build one order of ships at a time
    mapping (address => uint) public buildTime; // time when a player can claim their build ships
   
    // Setup functions
    // set treasury address
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "SHIPS: Cannot set treasury to 0 address");
        Treasury = ITreasury(_treasury);
        emit NewTreasury(_treasury);
    }
 
    //update the nova token address
    function setNovaAddress(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "SHIPS: Cannot set to 0 address");
        Nova = ShibaBEP20(_newAddress);
        emit NewNovaAddress(_newAddress);
    }
 
    //update the DryDock Address
    function setDryDock(address _dryDock) external onlyOwner {
        require(_dryDock != address(0), "SHIPS: Cannot set to 0 address");
        DryDock = IDryDock(_dryDock);
        emit NewDryDock(_dryDock);
    }
 
    // Addresses that can purchase ships
     modifier onlyPurchaser {
        require(isPurchaser(msg.sender));
        _;
    }
    // Is address a purchaser?
    function isPurchaser(address _purchaser) public view returns (bool){
        return purchaser[_purchaser] == true ? true : false;
    }
     // Add new purchasers
    function setPurchaser(address[] memory _purchaser) external onlyOwner {
        for (uint i = 0; i < _purchaser.length; i++) {
        require(purchaser[_purchaser[i]] == false, "DRYDOCK: Address is already a purchaser");
        purchaser[_purchaser[i]] = true;
        }
    }
    // Deactivate a purchaser
    function deactivatePurchaser ( address _purchaser) public onlyOwner {
        require(purchaser[_purchaser] == true, "DRYDOCK: Address is not a purchaser");
        purchaser[_purchaser] = false;
    }
 
    event NewShip(address Player, string shipClass);
 
    // set ship class defaults
    struct ShipClass {
        uint size;
        uint attack;
        uint capacity;
        uint armor;
        uint cost; 
        uint max;
        uint researchCost;
    }

    mapping (address => mapping (string => mapping (string => uint))) playerShips;
 
 
    string shipClasses = ["viper", "mole", "corvette"];
 
    mapping (string => ShipClass) shipDefaults;
    constructor() {
        shipDefaults["viper"] = ShipClass(1,1,0,5,1,500,0);
        shipDefaults["mole"] = ShipClass(2,0,5,10,2,100,0);
        shipDefaults["corvette"] = ShipClass(5,4,2,35,12,7,500);
    }
    // Add ship class to shipDefaults
	function addShipClass(string memory _shipClass, 
            uint size, uint attack, uint capacity,
            uint cost, uint max, uint researchCost) 
            external onlyOwner {
        
    }
    
    // Modify the attributes of the shipDefaults
	function modifyShipClassResearchCost(
            string memory _shipClass, 
            uint _researchCost) external onlyOwner {
	    shipDefaults[_shipClass].researchCost = _researchCost;
    }
    // Modify Size
    // Modify attack
    // Modify capacity
    // Modify armor
    // Modify cost
    // Modify max
 
    // Ship building Function
    function buildShips(uint _amount, string memory _shipClass) external {
        uint totalCost = _amount * shipDefaults[_shipClass].cost;
        Nova.transferFrom(msg.sender, address(Treasury), totalCost);
        Treasury.sendFee();
 
        playerShips[myAddress][shipClass]["amount"] += _amount;
        emit NewShip(msg.sender, _shipClass);
 
        //TODO: need to add build time feature
        //TODO: need to add max restriction
    }
 
    function buildBase(string memory _name) external {
        address _sender = msg.sender;
        DryDock.buildCapShip(_sender, _name);
    }
 
    function researchShip(string memory _shipType) external {
        require(playerShips[msg.sender][_shipType]["hasResearched"] == 0, "SHIPS: ship already researched");
        playerShips[msg.sender][_shipType]["hasResearched"] = 1;
        Nova.transferFrom(msg.sender, address(Treasury), shipDefaults[_shipType].researchCost);
        Treasury.sendFee();
    }
 
    //Updates the capital ship power and carry capacity in DryDock
    function _updatePower(address _player) internal {
        uint _capId = DryDock.getOwnerShipId(_player); 
 
        uint totalPower = 0;
        for(uint i=0;i<shipClasses.length;i++) {
            curShipClass = shipClasses[i];
            totalPower += (playerShips[_player][curShipClass]["amount"] * playerShips[_player][curShipClass]["attack"];
        }
        DryDock.setPower(_capId, totalPower);
    }
    function _updateCarry(address _player) internal {
        uint _capId = DryDock.getOwnerShipId(_player);
 
        uint totalCarry = 0;
        for(uint i=0;i<shipClasses.length;i++) {
            curShipClass = shipClasses[i];
            totalCarry += (playerShips[_player][curShipClass]["amount"] * shipDefaults[curShipClass].capacity;
        }
 
        DryDock.setCarryCapacity(_capId, totalCarry);
    }
   
    //Remove ships
    function removeShip(address _player, string memory _shipClass, uint _amount) external onlyPurchaser {
 
        uint shipAmount = playerShips[_player][_shipClass]["amount"];
        playerShips[_player][_shipClass]["amount"] = max(0, shipAmount - _amount);
 
        _updatePower(_player);
        _updateCarry(_player);
    }
}

