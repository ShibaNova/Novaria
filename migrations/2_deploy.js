advanceTime = (time) => {
  return new Promise((resolve, reject) => {
    web3.currentProvider.send({
      jsonrpc: '2.0',
      method: 'evm_increaseTime',
      params: [time],
      id: new Date().getTime()
    }, (err, result) => {
      if (err) { return reject(err) }
      return resolve(result)
    })
  })
}

const deployfarm = true

const reuseNovaToken = false
const reuseTreasury = false
const reuseShadowPool = false
const mainnet = false

let novaTokenAddress 
let shadowPoolAddress 
let treasuryAddress 

if (mainnet) {
  novaTokenAddress = '0x56E344bE9A7a7A1d27C854628483Efd67c11214F'
  shadowPoolAddress = '0x830f743BE5c238B97637b623aE448a740180Ac18'
  treasuryAddress = '0xB0e7b04Bee18BF0F2b8667cfd85313Da6b5de8D8'
} else {
  novaTokenAddress = '0xAab1a7Fcc77922528a83dC26a91fED6Fa066901e'
  shadowPoolAddress = '0xB1e18121D3de327b0991bf665F86a5e60e54ec42'
  treasuryAddress = '0x3C4d8F5D6A787bAa16FF0Ce7172ab808F7bba182'
}


const NovaToken = artifacts.require('NovaToken')
const ShadowPool = artifacts.require('ShadowPool')
const Treasury = artifacts.require('Treasury')
const MapContract = artifacts.require('Map')
const Fleet = artifacts.require('Fleet')
const MasterShiba = artifacts.require('MasterShiba')
const BasicToken = artifacts.require('BasicToken')

const _feeManager = '0x87b62B5d7c729e7C9ed28be460caDF5823228799'
const _devaddress = '0x729F3cA74A55F2aB7B584340DDefC29813fb21dF'
const _novaPerBlock = '1000000000000000000'
const _startBlock = '17182802'
const kj = '0x509CC3b01e4e4BD8CE810AA9C10D89d05E0FB03A'
const ll = '0xa12C28e569a7564420aa437F3d3dA29aED648707'
// SET PREVIOUS MAP ADDRESS
const prevMap = '0xdBa8908cED6dcaB5398Db255AC3BAF65837c0E5D'
const farmContract = '0x8A4f4c7F4804D30c718a76B3fde75f2e0cFd8712'
const shadowPoolToken = '0x1d47a4Fc357101829874b66Ec4c3d8e132256276'


module.exports = async function (deployer, network, accounts) {


    let nova
  
    if(!reuseNovaToken) {
      await deployer.deploy(NovaToken)
      nova = await NovaToken.deployed()
      await nova.setupSNova(nova.address)
    } else {
      nova= await NovaToken.at(novaTokenAddress)
    }


    let treasury
  
    if(!reuseTreasury) {
      await deployer.deploy(Treasury, nova.address, _feeManager)
      treasury = await Treasury.deployed()
      await treasury.setKJfr6(kj)
      await treasury.setlloY1(ll)
    } else {
      treasury = await Treasury.at(treasuryAddress)
    }

    await deployer.deploy(MapContract, nova.address, treasury.address)
    const map = await MapContract.deployed()

    await deployer.deploy(Fleet, map.address, treasury.address, nova.address)
    const fleet = await Fleet.deployed()

    let masterShiba 
    let basicToken
    if (deployfarm) {
      await deployer.deploy(BasicToken, 'BST', 'BST')
      basicToken = await BasicToken.deployed()
      await deployer.deploy(MasterShiba, nova.address, _devaddress, _feeManager, _novaPerBlock, _startBlock)
      masterShiba = await MasterShiba.deployed()
      await basicToken.approve(masterShiba.address, '1000000000000000000000')
      await basicToken._mint(accounts[0], '10')
      await advanceTime(10) 
      await masterShiba.add(800, basicToken.address, 0, false)
      await nova.mint(accounts[0], '1000000000000000000000000')
      await nova.mint(accounts[1], '1000000000000000000000000')
      await nova.mint(accounts[2], '1000000000000000000000000')
      await nova.mint(accounts[3], '1000000000000000000000000')
    }
     
    let shadowPool 
    
    if(!reuseShadowPool) {
      await deployer.deploy(ShadowPool, masterShiba.address, nova.address, 1, basicToken.address)
      shadowPool = await ShadowPool.deployed()
    } else {
      shadowPool = await ShadowPool.at(shadowPoolAddress)
    }

    // farm contract testing
    await nova.mint(shadowPool.address, '1000000000000000000000')
    await nova.transferOwnership(masterShiba.address)

    // contract setup map and fleet only, still requires additional treasury and shadowpool setup
    await map.setFleet(fleet.address)
    await map.setEditor([fleet.address])
    await map.setShadowPool(shadowPool.address)
    await map.setRewardsMod(10)
    await map.setRewardsDelay(3600)

    await fleet.setEditor([map.address])
    await fleet.setEditor([accounts[0]])

    // Treasury setup
    await treasury.approveContract(map.address)
    await treasury.setEditor([map.address])

    // additional setup for deploy of nova token
    // await nova.approve(treasury.address, '0xffffffffffffffffff')
    // await nova.approve(fleet.address, '0xffffffffffffffffff')

    // ShadowPool

    await shadowPool.tokenApproval(accounts[0], nova.address, '100000000000000000000000000000000')
    
    await shadowPool.tokenApproval(map.address, nova.address, '100000000000000000000000000000000')
    await shadowPool.setEditor([map.address, accounts[0]])
    if(!reuseShadowPool) {
      await shadowPool.tokenApproval(masterShiba.address, basicToken.address, '100000000000000000000000000000000')
      await shadowPool.tokenApproval(accounts[0], basicToken.address, '100000000000000000000000')
      await basicToken._mint(shadowPool.address, '10')
      await advanceTime(10) 
      await shadowPool.initialDeposit()
    } 

    await basicToken.approve(masterShiba.address, '100000000000000000000')
    await nova.approve(masterShiba.address, '100000000000000000000000000')
    
    await advanceTime(60*60*24*2) 
    await masterShiba.deposit(0, '10')
    await shadowPool.getPendingRewards()
    // testnet only
    // await map.requestToken()
    // await shadowPool.deactivateEditor(prevMap)
    // await shadowPool.replenishPlace(map.address, 10)

     if(!reuseNovaToken) {
         await map.requestToken()
         await map.startingPlaces(), {from:accounts[0]}
         // game startup
         await nova.approve(treasury.address, '0xffffffffffffffffff', {from: accounts[0]})
         await nova.approve(fleet.address, '0xffffffffffffffffff', {from: accounts[0]})
         await fleet.insertCoinHere('fleet1', {from: accounts[0]})

         await nova.approve(treasury.address, '0xffffffffffffffffff', {from: accounts[1]})
         await nova.approve(fleet.address, '0xffffffffffffffffff', {from: accounts[1]})
         await fleet.insertCoinHere('fleet2', {from: accounts[1]})

         await nova.approve(treasury.address, '0xffffffffffffffffff', {from: accounts[2]})
         await nova.approve(fleet.address, '0xffffffffffffffffff', {from: accounts[2]})
         await fleet.insertCoinHere('fleet3', {from: accounts[2]})

         //build ships
        await fleet.buildShips(0, 0, 0, 25, "5250000000000000000", {from: accounts[1]})
        await fleet.buildShips(0, 0, 0, 2500, "525000000000000000000", {from: accounts[2]})
         await advanceTime(86400 * 2)
        await fleet.claimShips(0,25, {from:accounts[1]})
        await fleet.claimShips(0,2500, {from:accounts[2]})
        await map.travel(3,2, {from:accounts[1]})
        await map.travel(2,3, {from:accounts[2]})
         await advanceTime(86400 * 2)
        await map.travel(3,2, {from:accounts[2]})
         await advanceTime(86400 * 2)
        await map.travel(0,0, {from:accounts[2]})

         //86400 seconds in a day
         await advanceTime(86400 * 2) // 10 Days
    }

};

/*
const fleet = await Fleet.deployed();
fleet.getShipyards();
await fleet.initiateShipyardTakeover(1, 3, {from:accounts[1]});
const map = await Map.deployed();
map.getPlaceInfo(1, 0);
*/