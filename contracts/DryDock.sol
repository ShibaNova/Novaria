// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/ShibaBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./interfaces/ITreasury.sol";

contract DryDock is Ownable {
    using SafeBEP20 for ShibaBEP20;

    event NewCapitalShip(uint shipID, string name);
    event NewBaseCapCost(uint newCost);
    event NewFighterCost(uint newCost); 
    event NewMaxFighters(uint16 newMax);
    event NewMinerCost(uint newCost);
    event NewMaxMiners(uint16 newMax);
    event NewWeightMax(uint newWeight);
    event NewTreasury(address newAddress);
    event NewNovaAddress(address newNova);

    ShibaBEP20 public Nova;
    address public Treasury;
    uint public baseCapCost = 100 * 10**18; // = 100 nova. amount of nova the base capital ship costs.
    uint public valueCapCost = baseCapCost * 3; 
    uint public superCapCost = baseCapCost * 10;
    uint public fighterCost = 10**18; // = 1 nova, cost of fighters can be changed
    uint16 public currentMaxFighters = 1000;
    uint public minerCost = 10*10**18; // == 10 nova, cost can by changed
    uint16 public currentMaxMiners = 1000;
    uint public weightMax = 10**18; // defines the NOVA carry capacity of the capital ship, dependant upon the number of miners

    // Be sure to set this contract as a purchaser after deployment
    constructor(
        ShibaBEP20 _Nova,
        address _Treasury
        
    ) {
        Nova = _Nova;
        Treasury = _Treasury;
    }


    // Info of the player's capital ship
    struct CapitalShip {
        string name;
        uint16 fighters;
        uint16 maxFighters;
        uint8 powerMod;
        uint16 miners;
        uint16 maxMiners;
        uint256 carryCapacity;
        uint16 wins;
        uint16 losses;
    }

    CapitalShip[] public capitalShips;

    mapping (uint => address) public capitalShipOwner;
    mapping (address => uint) public ownerShipId;
    mapping (address => uint) ownerCapitalShipCount;
    mapping (address => bool) public purchaser;

    // set treasury address
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "DRYDOCK: Cannot set treasury to 0 address");
        Treasury = _treasury;
        emit NewTreasury(_treasury);
    }

    //update the nova token address
    function setNovaAddrss(address _newAddress) external onlyOwner {
        Nova = ShibaBEP20(_newAddress);
        emit NewNovaAddress(_newAddress);
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

    function getOwnerCapitalShipCount(address _owner) external view returns(uint) {
        return ownerCapitalShipCount[_owner];
    }

    function getCapShpiOwner(uint _id) external view returns (address) {
        return capitalShipOwner[_id];
    }

    function getOwnerShipId(address _owner) external view returns (uint) {
        return ownerShipId[_owner];
    }

    function capShipLength() public view returns (uint256) {
        return capitalShips.length;
    }

    // get capital ship personal record
    function getCapitalShipRecord(uint256 _id) external view returns(
            string memory name,
            uint16 wins,
            uint16 losses
            ) {
            return (
                capitalShips[_id].name,
                capitalShips[_id].wins,
                capitalShips[_id].losses
            );
    }

    // get capital ship combat stats and mining power
    function getCapitalShip(uint256 _id) external view returns(
            uint16 fighters,
            uint16 maxFighters,
            uint8 powerMod,
            uint16 miners,
            uint16 maxMiners,
            uint256 carryCapacity
        ) {
            return (
                capitalShips[_id].fighters,
                capitalShips[_id].maxFighters,
                capitalShips[_id].powerMod,
                capitalShips[_id].miners,
                capitalShips[_id].maxMiners,
                capitalShips[_id].carryCapacity
            );
        }
    
    // external function to build capital ship, _sender should be the address of the player, not the contracts interacting with this
    function buildCapShip (
        address _sender,
        string memory _name, 
        uint _amount, 
        uint16 _startFighters, 
        uint16 _currentMaxFighters, 
        uint16 _startMiners, 
        uint16 _currentMaxMiners
        ) external onlyPurchaser {
            require(ownerCapitalShipCount[_sender] == 0, "DRYDOCK: Each player can only have one Capital Ship");
            ownerCapitalShipCount[msg.sender]++;
            Nova.transferFrom(_sender, Treasury, _amount);
            ITreasury(Treasury).sendFee();
            uint id = capShipLength();
            capitalShips.push(CapitalShip({
                name: _name, 
                fighters: _startFighters, 
                maxFighters: _currentMaxFighters,
                powerMod: 0, 
                miners: _startMiners, 
                maxMiners: _currentMaxMiners, 
                carryCapacity: _startMiners * weightMax, 
                wins: 0, 
                losses: 0
                }));

        capitalShipOwner[id] = _sender;
        ownerShipId[_sender] = id;
        ownerCapitalShipCount[_sender]++;
        emit NewCapitalShip(id, _name);
    }

    // internal function to build capital ship, 
    function _buildCapShip (
        string memory _name, 
        uint _amount, 
        uint16 _startFighters, 
        uint16 _currentMaxFighters, 
        uint16 _startMiners, 
        uint16 _currentMaxMiners
        ) private {
            require(ownerCapitalShipCount[msg.sender] == 0, "DRYDOCK: Each player can only have one Capital Ship");
            ownerCapitalShipCount[msg.sender]++;
            Nova.transferFrom(msg.sender, Treasury, _amount);
            ITreasury(Treasury).sendFee();
            uint id = capShipLength();
            capitalShips.push(CapitalShip({
                name: _name, 
                fighters: _startFighters, 
                maxFighters: _currentMaxFighters,
                powerMod: 0, 
                miners: _startMiners, 
                maxMiners: _currentMaxMiners, 
                carryCapacity: _startMiners * weightMax, 
                wins: 0, 
                losses: 0
                }));

        capitalShipOwner[id] = msg.sender;
        ownerShipId[msg.sender] = id;
        emit NewCapitalShip(id, _name);
    }

    // set the cost of the base capital ship, this also sets the cost for the value packs
    // ex: _amount = 10 * 10**18, then base cost is 10 nova
    function setBasicCost (uint _amount) external onlyOwner {
        baseCapCost = _amount;
        emit NewBaseCapCost (_amount);
    }

    // funciton to build the basic capital ship with 10 fighters and 1 miner
    function buildCapBasic(string memory _name) external {
        uint _amount = baseCapCost; 
        uint16 _startFighters = 10;
        uint16 _currentMaxFighters = currentMaxFighters; 
        uint16 _startMiners = 1; 
        uint16 _currentMaxMiners = currentMaxMiners;
        _buildCapShip(_name, _amount, _startFighters, _currentMaxFighters, _startMiners, _currentMaxMiners);
    }

    function buildCapValue(string memory _name) external {
        uint _amount = valueCapCost; 
        uint16 _startFighters = 100;
        uint16 _currentMaxFighters = currentMaxFighters; 
        uint16 _startMiners = 3; 
        uint16 _currentMaxMiners = currentMaxMiners;
        _buildCapShip(_name, _amount, _startFighters, _currentMaxFighters, _startMiners, _currentMaxMiners);
    }
    
    function buildCapSuper(string memory _name) external {
        uint _amount = superCapCost; 
        uint16 _startFighters = 500;
        uint16 _currentMaxFighters = currentMaxFighters + 100; 
        uint16 _startMiners = 10; 
        uint16 _currentMaxMiners = currentMaxMiners;
        _buildCapShip(_name, _amount, _startFighters, _currentMaxFighters, _startMiners, _currentMaxMiners);
    }

    // functions to add/sub/buy fighters, add/sub are for other contract interactions
    function addFighter (address _sender, uint16 _value) external onlyPurchaser {
        uint _id = ownerShipId[_sender];
        require(capitalShips[_id].fighters + _value <= capitalShips[_id].maxFighters, 
            "DRYDOCK: cannot have more than your max amount of fighters");
        capitalShips[_id].fighters = capitalShips[_id].fighters + _value;
    }

    // 10 is the min amount of fighters you're allowed to have
    function subFighter (address _sender, uint16 _value) external onlyPurchaser {
        uint _id = ownerShipId[_sender];
        if (capitalShips[_id].fighters - _value <= 10) {
            capitalShips[_id].fighters = 10;
        } else {
        capitalShips[_id].fighters = capitalShips[_id].fighters - _value;
        }
    }
    
    function buyFighters (uint16 _value) external {
        uint _id = ownerShipId[msg.sender];
        Nova.transferFrom(msg.sender, Treasury, fighterCost);
        ITreasury(Treasury).sendFee();
        require(capitalShips[_id].fighters + _value <= capitalShips[_id].maxFighters, 
            "DRYDOCK: cannot have more than your max amount of fighters");
        capitalShips[_id].fighters = capitalShips[_id].fighters + _value;
    }

    // allows owner to set a new fighter cost
    function setFighterCost(uint _value) external onlyOwner {
        fighterCost = _value;
        emit NewFighterCost(_value);
    }

    // owner can modify maxFighters
    function setMaxFighters(uint16 _value) external onlyOwner {
        currentMaxFighters = _value; 
        emit NewMaxFighters(_value);
    }

    // functions to add/sub/buy miners, similar structure to fighters
    function addMiner(address _sender, uint16 _value) external onlyPurchaser {
        uint _id = ownerShipId[_sender];
        require(capitalShips[_id].miners + _value <= capitalShips[_id].maxMiners, 
            "DRYDOCK: cannot have more than your max amount of miners");
        capitalShips[_id].miners = capitalShips[_id].miners + _value;
        capitalShips[_id].carryCapacity = capitalShips[_id].miners * weightMax;
    }
    
    function subMiner (address _sender, uint16 _value) external onlyPurchaser {
        uint _id = ownerShipId[_sender];
        if (capitalShips[_id].miners - _value <= 0) {
            capitalShips[_id].miners = 0;
        } else {
        capitalShips[_id].miners = capitalShips[_id].miners - _value;
        }
        capitalShips[_id].carryCapacity = capitalShips[_id].miners * weightMax;
    }
    
    function buyMiners (uint16 _value) external {
        uint _id = ownerShipId[msg.sender];
        Nova.transferFrom(msg.sender, Treasury, minerCost);
        ITreasury(Treasury).sendFee();
        require(capitalShips[_id].miners + _value <= capitalShips[_id].maxMiners, 
            "DRYDOCK: cannot have more than your max amount of miners");
        capitalShips[_id].miners = capitalShips[_id].miners + _value;
        capitalShips[_id].carryCapacity = capitalShips[_id].miners * weightMax;
    }

    // allows owner to set a new miner cost
    function setMinerCost(uint _value) external onlyOwner {
        minerCost = _value;
        emit NewMinerCost(_value);
    }

    // owner can modify maxMiners
    function setMaxMiners(uint16 _value) external onlyOwner {
        currentMaxMiners = _value; 
        emit NewMaxMiners(_value);
    }

    // set how much nova a miner can carry
    function setWeightMax(uint _value) external onlyOwner {
        weightMax = _value;
        emit NewWeightMax(_value);
    }

    // set the fleet's powerMod
    function addPowerMod(uint8 _value, address _sender) external onlyPurchaser {
        uint _id = ownerShipId[_sender];
        require(capitalShips[_id].powerMod + _value <= 255, "DRYDOCK: player's powerMod is capped");
        capitalShips[_id].powerMod = capitalShips[_id].powerMod + _value;
    }

    function subPowerMod(uint8 _value, address _sender) external onlyPurchaser {
        uint _id = ownerShipId[_sender];
        if (capitalShips[_id].powerMod - _value <= 0) {
            capitalShips[_id].powerMod = 0;
        } else {
        capitalShips[_id].powerMod = capitalShips[_id].powerMod + _value;
        }
    }

    

}