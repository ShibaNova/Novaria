// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/access/Ownable.sol";
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
contract Ships is Ownable {

    // required contracts to interact
    ShibaBEP20 public Nova; // NOVA Token is game currency
    IDryDock public DryDock; // DryDock Contract manages the capital ship
    ITreasury public Treasury; // Treasury contract manages NOVA spending

    // List of Events
    event NewTreasury(address newAddress);
    event NewNovaAddress(address newNova);
    event NewDryDock(address newDryDock);
    event NewViper(uint Id, address Player);
    event NewMole(uint Id, address Player);
    event NewCorvette(uint Id, address Player);
    event NewChallenger(uint Id, address Player);
    event NewMustang(uint Id, address Player);

    // General Mappings
    mapping (address => bool) public purchaser; // addresses that can call functions in this contract
    mapping (address => bool) public building; // player can only build one order of ships at a time
    mapping (address => uint) public buildTime; // time when a player can claim their build ships


    // structs, required mappings, and variables for each ship
    struct Viper {
        uint amount;
        uint max;
        uint16 attack;
        uint16 armor;
        uint capacity;
        
    }
    Viper[] public vipers;
    mapping (uint => address) public viperOwner;
    mapping (address => uint) public viperId;
    mapping (address => uint) public viperCount;
    mapping (address => uint) public vipersInQueue;
    uint public viperMax = 5000; // max # of ships
    uint16 public viperAttack = 1;
    uint16 public viperArmor = 5;
    uint public viperCapacity = 0; // NOVA carry capacity
    uint public viperCost = 10**18; // cost in NOVA
    uint16 public viperBuildTime = 60; // seconds


    struct Mole {
        uint amount;
        uint max;
        uint16 attack;
        uint16 armor;
        uint capacity;
        
    }
    Mole[] public moles;
    mapping (uint => address) public moleOwner;
    mapping (address => uint) public moleId;
    mapping (address => uint) public moleCount;
    mapping (address => uint) public molesInQueue;
    uint public moleMax = 1000; // max # of ships
    uint16 public moleAttack = 0;
    uint16 public moleArmor = 10;
    uint public moleCapacity = 5; // NOVA carry capacity
    uint public moleCost = 2*10**18; // cost in NOVA
    uint16 public moleBuildTime = 120; // seconds

    struct Mustang {
        uint amount;
        uint max;
        uint16 attack;
        uint16 armor;
        uint capacity;
        
    }
    Mustang[] public mustangs;
    mapping (uint => address) public mustangOwner;
    mapping (address => uint) public mustangId;
    mapping (address => uint) public mustangCount;
    mapping (address => uint) public mustangResearch;
    mapping (address => uint) public mustangsInQueue;
    uint public mustangResearchCost = 100*10**18; // base reasearch cost in NOVA
    uint public mustangMax = 10000; // max # of ships
    uint16 public mustangAttack = 1;
    uint16 public mustangArmor = 5;
    uint public mustangCapacity = 0; // NOVA carry capacity
    uint public mustangCost = 10**18; // cost in NOVA
    uint16 public mustangBuildTime = 10; // seconds
    bool public mustangActive = false; // can ship be used

    struct Corvette {
        uint amount;
        uint max;
        uint16 attack;
        uint16 armor;
        uint capacity;
        
    }
    Corvette[] public corvettes;
    mapping (uint => address) public corvetteOwner;
    mapping (address => uint) public corvetteId;
    mapping (address => uint) public corvetteCount;
    mapping (address => uint) public corvetteResearch;
    mapping (address => uint) public corvettesInQueue;
    uint public corvetteResearchCost = 100*10**18; // base reasearch cost in NOVA
    uint public corvetteMax = 10000; // max # of ships
    uint16 public corvetteAttack = 1;
    uint16 public corvetteArmor = 5;
    uint public corvetteCapacity = 0; // NOVA carry capacity
    uint public corvetteCost = 10**18; // cost in NOVA
    uint16 public corvetteBuildTime = 10; // seconds
    bool public corvetteActive = false; // can ship be used

    struct Challenger {
        uint amount;
        uint max;
        uint16 attack;
        uint16 armor;
        uint capacity;
        uint16 hanger;
    }
    Challenger[] public challengers;
    mapping (uint => address) public challengerOwner;
    mapping (address => uint) public challengerId;
    mapping (address => uint) public challengerCount;
    mapping (address => uint) public challengerResearch;
    mapping (address => uint) public challengersInQueue;
    uint public challengerResearchCost = 100*10**18; // base reasearch cost in NOVA
    uint public challengerMax = 10000; // max # of ships
    uint16 public challengerAttack = 1;
    uint16 public challengerArmor = 5;
    uint public challengerCapacity = 0; // NOVA carry capacity
    uint public challengerCost = 10**18; // cost in NOVA
    uint16 public challengerBuildTime = 10; // seconds
    uint16 public challengerHanger = 100; // extra fighter space
    bool public challengerActive = false; // can ship be used


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

    // Helper functions to retreive ship information
    

    // Ship builiding Functions
    // Build the structs for every ship, including capital (external)
    function _buildViper(uint _amount) internal {
        require(viperCount[msg.sender] == 0, "SHIPS: can only have 1 viper struct");
        viperCount[msg.sender]++;
        uint _cost = _amount * viperCost;
        Nova.transferFrom(msg.sender, address(Treasury), _cost);
        Treasury.sendFee();
        uint _id = vipers.length;
        vipers.push(Viper({
            amount: _amount,
            max: viperMax,
            attack: viperAttack,
            armor: viperArmor,
            capacity: viperCapacity
        }));
        viperOwner[_id] = msg.sender;
        viperId[msg.sender] = _id;
        emit NewViper(_id, msg.sender);
    } 

    function _buildMole(uint _amount) internal {
        require(moleCount[msg.sender] == 0, "SHIPS: can only have 1 mole struct");
        moleCount[msg.sender]++;
        uint _cost = _amount * moleCost;
        Nova.transferFrom(msg.sender, address(Treasury), _cost);
        Treasury.sendFee();
        uint _id = moles.length;
        moles.push(Mole({
            amount: _amount,
            max: moleMax,
            attack: moleAttack,
            armor: moleArmor,
            capacity: moleCapacity
        }));
        moleOwner[_id] = msg.sender;
        moleId[msg.sender] = _id;
        emit NewMole(_id, msg.sender);
    } 

     function _buildCorvette(uint _amount) internal {
        require(corvetteActive == true, "SHIPS: ship is not yet available");
        require(corvetteCount[msg.sender] == 0, "SHIPS: can only have 1 corvette struct");
        corvetteCount[msg.sender]++;
        uint _cost = _amount * corvetteCost;
        Nova.transferFrom(msg.sender, address(Treasury), _cost);
        Treasury.sendFee();
        uint _id = corvettes.length;
        corvettes.push(Corvette({
            amount: _amount,
            max: corvetteMax,
            attack: corvetteAttack,
            armor: corvetteArmor,
            capacity: corvetteCapacity
        }));
        corvetteOwner[_id] = msg.sender;
        corvetteId[msg.sender] = _id;
        emit NewCorvette(_id, msg.sender);
    }    

    function _buildMustang(uint _amount) internal {
        require(mustangActive == true, "SHIPS: ship is not yet available");
        require(mustangCount[msg.sender] == 0, "SHIPS: can only have 1 mustang struct");
        mustangCount[msg.sender]++;
        uint _cost = _amount * mustangCost;
        Nova.transferFrom(msg.sender, address(Treasury), _cost);
        Treasury.sendFee();
        uint _id = mustangs.length;
        mustangs.push(Mustang({
            amount: _amount,
            max: mustangMax,
            attack: mustangAttack,
            armor: mustangArmor,
            capacity: mustangCapacity
        }));
        mustangOwner[_id] = msg.sender;
        mustangId[msg.sender] = _id;
        emit NewMustang(_id, msg.sender);
    } 

    function _buildChallenger(uint _amount) internal {
        require(challengerActive == true, "SHIPS: ship is not yet available");
        require(challengerCount[msg.sender] == 0, "SHIPS: can only have 1 challenger struct");
        challengerCount[msg.sender]++;
        uint _cost = _amount * challengerCost;
        Nova.transferFrom(msg.sender, address(Treasury), _cost);
        Treasury.sendFee();
        uint _id = challengers.length;
        challengers.push(Challenger({
            amount: _amount,
            max: challengerMax,
            attack: challengerAttack,
            armor: challengerArmor,
            capacity: challengerCapacity,
            hanger: challengerHanger
        }));
        challengerOwner[_id] = msg.sender;
        challengerId[msg.sender] = _id;
        emit NewChallenger(_id, msg.sender);
    }     

    function buildBase(string memory _name) external {
        address _sender = msg.sender;
        DryDock.buildCapShip(_sender, _name);
        _buildViper(0);
        _buildMole(0);
    }

    //Functions to research the ships so they can be built
    function researchCorvette() external {
        require(corvetteResearch[msg.sender] == 0, "SHIPS: ship already researched");
        corvetteResearch[msg.sender]++;
        Nova.transferFrom(msg.sender, address(Treasury), corvetteResearchCost);
        Treasury.sendFee();
        _buildCorvette(0);
    }

    function researchMustang() external {
        require(mustangResearch[msg.sender] == 0, "SHIPS: ship already researched");
        mustangResearch[msg.sender]++;
        Nova.transferFrom(msg.sender, address(Treasury), mustangResearchCost);
        Treasury.sendFee();
        _buildMustang(0);
    }

    function researchChallenger() external {
        require(challengerResearch[msg.sender] == 0, "SHIPS: ship already researched");
        challengerResearch[msg.sender]++;
        Nova.transferFrom(msg.sender, address(Treasury), challengerResearchCost);
        Treasury.sendFee();
        _buildChallenger(0);
    }

    //Functions to modify the ship attributes and variables

    //Updates the capital ship power and carry capacity in DryDock
    function _updatePower(address _player) internal {
        uint _capId = DryDock.getOwnerShipId(_player);
        uint _viperId = viperId[_player];
        uint _moleId = moleId[_player];
        uint _mustangId = mustangId[_player];
        uint _corvetteId = corvetteId[_player];
        uint _challengerId = challengerId[_player];
        uint _amount = 
            (vipers[_viperId].amount * vipers[_viperId].attack) +
            (corvettes[_corvetteId].amount * corvettes[_corvetteId].attack) +
            (mustangs[_mustangId].amount * mustangs[_mustangId].attack) +
            (challengers[_challengerId].amount * challengers[_challengerId].attack) +
            (moles[_moleId].amount * moles[_moleId].attack);
        DryDock.setPower(_capId, _amount);
    }
    function _updateCarry(address _player) internal {
        uint _capId = DryDock.getOwnerShipId(_player);
        uint _viperId = viperId[_player];
        uint _moleId = moleId[_player];
        uint _mustangId = mustangId[_player];
        uint _corvetteId = corvetteId[_player];
        uint _challengerId = challengerId[_player];
        uint _amount = 
            (vipers[_viperId].amount * vipers[_viperId].capacity) +
            (corvettes[_corvetteId].amount * corvettes[_corvetteId].capacity) +
            (mustangs[_mustangId].amount * mustangs[_mustangId].capacity) +
            (challengers[_challengerId].amount * challengers[_challengerId].capacity) +
            (moles[_moleId].amount * moles[_moleId].capacity);
        DryDock.setCarryCapacity(_capId, _amount);
    }
    //Add a ship without associated cost - future feature
    function addViper(uint _amount, address _player) external onlyPurchaser{
        uint _id = viperId[_player];
        require(vipers[_id].amount + _amount <= vipers[_id].max, "SHIPS: cannot build more than max");
        vipers[_id].amount = vipers[_id].amount + _amount;
        _updatePower(_player);
        _updateCarry(_player);
    }
    //Build a ship with the NOVA and time cost
    function buildViper(uint _amount) external {
        require(building[msg.sender] != true, "SHIPS: Player already has active build order");
        building[msg.sender] = true;
        uint _id = viperId[msg.sender];
        require(vipers[_id].amount + _amount <= vipers[_id].max, "SHIPS: cannot build more than max");
        Nova.transferFrom(msg.sender, address(Treasury), _amount*viperCost);
        Treasury.sendFee();
        buildTime[msg.sender] = block.timestamp + (_amount * viperBuildTime);
        vipersInQueue[msg.sender] = _amount;
    }
    //Claim built ships
    function claimVipers () external {
        require(building[msg.sender] == true, "SHIPS: Player has no active build order");
        building[msg.sender] = false;
        require(block.timestamp >= buildTime[msg.sender], "SHIPS: Build order not ready");
        buildTime[msg.sender] = 0;
        uint _id = viperId[msg.sender];
        require(vipers[_id].amount + vipersInQueue[msg.sender] <= vipers[_id].max, "SHIPS: cannot build more than max");
        uint _amount = vipersInQueue[msg.sender];
        vipersInQueue[msg.sender] = 0;
        vipers[_id].amount = vipers[_id].amount + _amount;
        _updatePower(msg.sender);
        _updateCarry(msg.sender);
    }
    //Remove ships
    function subVipers(address _player, uint _amount) external onlyPurchaser {
        uint _id = viperId[_player];
        if (vipers[_id].amount - _amount <= 0) {
            vipers[_id].amount = 0;
        } else {
            vipers[_id].amount = vipers[_id].amount - _amount;
        }
        _updatePower(_player);
        _updateCarry(_player);
    }
    
    //Add a ship without associated cost - future feature
    function addMole(uint _amount, address _player) external onlyPurchaser{
        uint _id = moleId[_player];
        require(moles[_id].amount + _amount <= moles[_id].max, "SHIPS: cannot build more than max");
        moles[_id].amount = moles[_id].amount + _amount;
        _updatePower(_player);
        _updateCarry(_player);
    }
    //Build a ship with the NOVA and time cost
    function buildMole(uint _amount) external {
        require(building[msg.sender] != true, "SHIPS: Player already has active build order");
        building[msg.sender] = true;
        uint _id = moleId[msg.sender];
        require(moles[_id].amount + _amount <= moles[_id].max, "SHIPS: cannot build more than max");
        Nova.transferFrom(msg.sender, address(Treasury), _amount*moleCost);
        Treasury.sendFee();
        buildTime[msg.sender] = block.timestamp + (_amount * moleBuildTime);
        molesInQueue[msg.sender] = _amount;
    }
    //Claim built ships
    function claimMoles () external {
        require(building[msg.sender] == true, "SHIPS: Player has no active build order");
        building[msg.sender] = false;
        require(block.timestamp >= buildTime[msg.sender], "SHIPS: Build order not ready");
        buildTime[msg.sender] = 0;
        uint _id = moleId[msg.sender];
        require(moles[_id].amount + molesInQueue[msg.sender] <= moles[_id].max, "SHIPS: cannot build more than max");
        uint _amount = molesInQueue[msg.sender];
        molesInQueue[msg.sender] = 0;
        moles[_id].amount = moles[_id].amount + _amount;
        _updatePower(msg.sender);
        _updateCarry(msg.sender);
    }
    //Remove ships
    function subMoles(address _player, uint _amount) external onlyPurchaser {
        uint _id = moleId[_player];
        if (moles[_id].amount - _amount <= 0) {
            moles[_id].amount = 0;
        } else {
            moles[_id].amount = moles[_id].amount - _amount;
        }
        _updatePower(_player);
        _updateCarry(_player);
    }
    
    //Add a ship without associated cost - future feature
    function addCorvette(uint _amount, address _player) external onlyPurchaser{
        uint _id = corvetteId[_player];
        require(corvettes[_id].amount + _amount <= corvettes[_id].max, "SHIPS: cannot build more than max");
        corvettes[_id].amount = corvettes[_id].amount + _amount;
        _updatePower(_player);
        _updateCarry(_player);
    }
    //Build a ship with the NOVA and time cost
    function buildCorvette(uint _amount) external {
        require(building[msg.sender] != true, "SHIPS: Player already has active build order");
        building[msg.sender] = true;
        uint _id = corvetteId[msg.sender];
        require(corvettes[_id].amount + _amount <= corvettes[_id].max, "SHIPS: cannot build more than max");
        Nova.transferFrom(msg.sender, address(Treasury), _amount*corvetteCost);
        Treasury.sendFee();
        buildTime[msg.sender] = block.timestamp + (_amount * corvetteBuildTime);
        corvettesInQueue[msg.sender] = _amount;
    }
    //Claim built ships
    function claimCorvettes () external {
        require(building[msg.sender] == true, "SHIPS: Player has no active build order");
        building[msg.sender] = false;
        require(block.timestamp >= buildTime[msg.sender], "SHIPS: Build order not ready");
        buildTime[msg.sender] = 0;
        uint _id = corvetteId[msg.sender];
        require(corvettes[_id].amount + corvettesInQueue[msg.sender] <= corvettes[_id].max, "SHIPS: cannot build more than max");
        uint _amount = corvettesInQueue[msg.sender];
        corvettesInQueue[msg.sender] = 0;
        corvettes[_id].amount = corvettes[_id].amount + _amount;
        _updatePower(msg.sender);
        _updateCarry(msg.sender);
    }
    //Remove ships
    function subCorvettes(address _player, uint _amount) external onlyPurchaser {
        uint _id = corvetteId[_player];
        if (corvettes[_id].amount - _amount <= 0) {
            corvettes[_id].amount = 0;
        } else {
            corvettes[_id].amount = corvettes[_id].amount - _amount;
        }
        _updatePower(_player);
        _updateCarry(_player);
    }
    
    //Add a ship without associated cost - future feature
    function addMustang(uint _amount, address _player) external onlyPurchaser{
        uint _id = mustangId[_player];
        require(mustangs[_id].amount + _amount <= mustangs[_id].max, "SHIPS: cannot build more than max");
        mustangs[_id].amount = mustangs[_id].amount + _amount;
        _updatePower(_player);
        _updateCarry(_player);
    }
    //Build a ship with the NOVA and time cost
    function buildMustang(uint _amount) external {
        require(building[msg.sender] != true, "SHIPS: Player already has active build order");
        building[msg.sender] = true;
        uint _id = mustangId[msg.sender];
        require(mustangs[_id].amount + _amount <= mustangs[_id].max, "SHIPS: cannot build more than max");
        Nova.transferFrom(msg.sender, address(Treasury), _amount*mustangCost);
        Treasury.sendFee();
        buildTime[msg.sender] = block.timestamp + (_amount * mustangBuildTime);
        mustangsInQueue[msg.sender] = _amount;
    }
    //Claim built ships
    function claimMustangs () external {
        require(building[msg.sender] == true, "SHIPS: Player has no active build order");
        building[msg.sender] = false;
        require(block.timestamp >= buildTime[msg.sender], "SHIPS: Build order not ready");
        buildTime[msg.sender] = 0;
        uint _id = mustangId[msg.sender];
        require(mustangs[_id].amount + mustangsInQueue[msg.sender] <= mustangs[_id].max, "SHIPS: cannot build more than max");
        uint _amount = mustangsInQueue[msg.sender];
        mustangsInQueue[msg.sender] = 0;
        mustangs[_id].amount = mustangs[_id].amount + _amount;
        _updatePower(msg.sender);
        _updateCarry(msg.sender);
    }
    //Remove ships
    function subMustangs(address _player, uint _amount) external onlyPurchaser {
        uint _id = mustangId[_player];
        if (mustangs[_id].amount - _amount <= 0) {
            mustangs[_id].amount = 0;
        } else {
            mustangs[_id].amount = mustangs[_id].amount - _amount;
        }
        _updatePower(_player);
        _updateCarry(_player);
    }
    
    //Add a ship without associated cost - future feature
    function addChallenger(uint _amount, address _player) external onlyPurchaser{
        uint _id = challengerId[_player];
        require(challengers[_id].amount + _amount <= challengers[_id].max, "SHIPS: cannot build more than max");
        challengers[_id].amount = challengers[_id].amount + _amount;
        _updatePower(_player);
        _updateCarry(_player);
        uint _hangerSpace = _amount * challengers[_id].hanger;
        addViperMax(_hangerSpace, _player);
    }
    //Build a ship with the NOVA and time cost
    function buildChallenger(uint _amount) external {
        require(building[msg.sender] != true, "SHIPS: Player already has active build order");
        building[msg.sender] = true;
        uint _id = challengerId[msg.sender];
        require(challengers[_id].amount + _amount <= challengers[_id].max, "SHIPS: cannot build more than max");
        Nova.transferFrom(msg.sender, address(Treasury), _amount*challengerCost);
        Treasury.sendFee();
        buildTime[msg.sender] = block.timestamp + (_amount * challengerBuildTime);
        challengersInQueue[msg.sender] = _amount;
    }
    //Claim built ships
    function claimChallengers () external {
        require(building[msg.sender] == true, "SHIPS: Player has no active build order");
        building[msg.sender] = false;
        require(block.timestamp >= buildTime[msg.sender], "SHIPS: Build order not ready");
        buildTime[msg.sender] = 0;
        uint _id = challengerId[msg.sender];
        require(challengers[_id].amount + challengersInQueue[msg.sender] <= challengers[_id].max, "SHIPS: cannot build more than max");
        uint _amount = challengersInQueue[msg.sender];
        challengersInQueue[msg.sender] = 0;
        challengers[_id].amount = challengers[_id].amount + _amount;
        _updatePower(msg.sender);
        _updateCarry(msg.sender);
        uint _hangerSpace = _amount * challengers[_id].hanger;
        addViperMax(_hangerSpace, msg.sender);
    }
    //Remove ships
    function subChallengers(address _player, uint _amount) external onlyPurchaser {
        uint _id = challengerId[_player];
        if (challengers[_id].amount - _amount <= 0) {
            challengers[_id].amount = 0;
        } else {
            challengers[_id].amount = challengers[_id].amount - _amount;
        }
        _updatePower(_player);
        _updateCarry(_player);
        uint _hangerSpace = _amount * challengers[_id].hanger;
        subViperMax(_hangerSpace, msg.sender);
    }
    //Functions to update the attributes of the ships
    function addViperMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = viperId[_player];
        vipers[_id].max = vipers[_id].max + _amount;
    }
    function addViperAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = viperId[_player];
        vipers[_id].attack = vipers[_id].attack + _amount;
        _updatePower(_player);
    }
    function addViperArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = viperId[_player];
        vipers[_id].armor = vipers[_id].armor + _amount;
    }
    function addViperCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = viperId[_player];
        vipers[_id].capacity = vipers[_id].capacity + _amount;
        _updateCarry(_player);
    }
    function subViperMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = viperId[_player];
        vipers[_id].max = vipers[_id].max - _amount;
    }
    function subViperAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = viperId[_player];
        vipers[_id].attack = vipers[_id].attack - _amount;
        _updatePower(_player);
    }
    function subViperArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = viperId[_player];
        vipers[_id].armor = vipers[_id].armor - _amount;
    }
    function subViperCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = viperId[_player];
        vipers[_id].capacity = vipers[_id].capacity - _amount;
        _updateCarry(_player);
    }
    function addMoleMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = moleId[_player];
        moles[_id].max = moles[_id].max + _amount;
    }
    function addMoleAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = moleId[_player];
        moles[_id].attack = moles[_id].attack + _amount;
        _updatePower(_player);
    }
    function addMoleArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = moleId[_player];
        moles[_id].armor = moles[_id].armor + _amount;
    }
    function addMoleCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = moleId[_player];
        moles[_id].capacity = moles[_id].capacity + _amount;
        _updateCarry(_player);
    }
    function subMoleMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = moleId[_player];
        moles[_id].max = moles[_id].max - _amount;
    }
    function subMoleAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = moleId[_player];
        moles[_id].attack = moles[_id].attack - _amount;
        _updatePower(_player);
    }
    function subMoleArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = moleId[_player];
        moles[_id].armor = moles[_id].armor - _amount;
    }
    function subMoleCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = moleId[_player];
        moles[_id].capacity = moles[_id].capacity - _amount;
        _updateCarry(_player);
    }
    function addCorvetteMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = corvetteId[_player];
        corvettes[_id].max = corvettes[_id].max + _amount;
    }
    function addCorvetteAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = corvetteId[_player];
        corvettes[_id].attack = corvettes[_id].attack + _amount;
        _updatePower(_player);
    }
    function addCorvetteArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = corvetteId[_player];
        corvettes[_id].armor = corvettes[_id].armor + _amount;
    }
    function addCorvetteCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = corvetteId[_player];
        corvettes[_id].capacity = corvettes[_id].capacity + _amount;
        _updateCarry(_player);
    }
    function subCorvetteMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = corvetteId[_player];
        corvettes[_id].max = corvettes[_id].max - _amount;
    }
    function subCorvetteAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = corvetteId[_player];
        corvettes[_id].attack = corvettes[_id].attack - _amount;
        _updatePower(_player);
    }
    function subCorvetteArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = corvetteId[_player];
        corvettes[_id].armor = corvettes[_id].armor - _amount;
    }
    function subCorvetteCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = corvetteId[_player];
        corvettes[_id].capacity = corvettes[_id].capacity - _amount;
        _updateCarry(_player);
    }
    function addMustangMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = mustangId[_player];
        mustangs[_id].max = mustangs[_id].max + _amount;
    }
    function addMustangAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = mustangId[_player];
        mustangs[_id].attack = mustangs[_id].attack + _amount;
        _updatePower(_player);
    }
    function addMustangArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = mustangId[_player];
        mustangs[_id].armor = mustangs[_id].armor + _amount;
    }
    function addMustangCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = mustangId[_player];
        mustangs[_id].capacity = mustangs[_id].capacity + _amount;
        _updateCarry(_player);
    }
    function subMustangMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = mustangId[_player];
        mustangs[_id].max = mustangs[_id].max - _amount;
    }
    function subMustangAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = mustangId[_player];
        mustangs[_id].attack = mustangs[_id].attack - _amount;
        _updatePower(_player);
    }
    function subMustangArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = mustangId[_player];
        mustangs[_id].armor = mustangs[_id].armor - _amount;
    }
    function subMustangCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = mustangId[_player];
        mustangs[_id].capacity = mustangs[_id].capacity - _amount;
        _updateCarry(_player);
    }
    function addChallengerMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = challengerId[_player];
        challengers[_id].max = challengers[_id].max + _amount;
    }
    function addChallengerAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = challengerId[_player];
        challengers[_id].attack = challengers[_id].attack + _amount;
        _updatePower(_player);
    }
    function addChallengerArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = challengerId[_player];
        challengers[_id].armor = challengers[_id].armor + _amount;
    }
    function addChallengerCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = challengerId[_player];
        challengers[_id].capacity = challengers[_id].capacity + _amount;
        _updateCarry(_player);
    }
    function subChallengerMax(uint _amount, address _player) public onlyPurchaser {
        uint _id = challengerId[_player];
        challengers[_id].max = challengers[_id].max - _amount;
    }
    function subChallengerAttack(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = challengerId[_player];
        challengers[_id].attack = challengers[_id].attack - _amount;
        _updatePower(_player);
    }
    function subChallengerArmor(uint16 _amount, address _player) public onlyPurchaser {
        uint _id = challengerId[_player];
        challengers[_id].armor = challengers[_id].armor - _amount;
    }
    function subChallengerCapacity(uint _amount, address _player) public onlyPurchaser {
        uint _id = challengerId[_player];
        challengers[_id].capacity = challengers[_id].capacity - _amount;
        _updateCarry(_player);
    }
    //Challengers are special and have hanger space
    //The following functions manage changing the hanger size
    function
}