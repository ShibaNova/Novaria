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

const deployedNovaToken = false
const deployedTreasury = false
const deployedShadowPool = false
const novaTokenAddress = '0x56E344bE9A7a7A1d27C854628483Efd67c11214F'
const shadowPoolAddress = '0x318C38d8140Cb1d4CeF6E40743457c4224d07Fd8'
const treasuryAddress = '0xB0e7b04Bee18BF0F2b8667cfd85313Da6b5de8D8'

const NovaToken = artifacts.require('NovaToken')
const ShadowPool = artifacts.require('ShadowPool')
const Treasury = artifacts.require('Treasury')
const MapContract = artifacts.require('Map')
const Fleet = artifacts.require('Fleet')
//const MasterShiba = artifacts.require('MasterShiba')
//const BasicToken = artifacts.require('BasicToken')

const _feeManager = '0x87b62B5d7c729e7C9ed28be460caDF5823228799'
const _devaddress = '0x729F3cA74A55F2aB7B584340DDefC29813fb21dF'
// const _novaPerBlock = '1000000000000000000'
// const _startBlock = '15802444'
const kj = '0x509CC3b01e4e4BD8CE810AA9C10D89d05E0FB03A'
const ll = '0xa12C28e569a7564420aa437F3d3dA29aED648707'
// SET PREVIOUS MAP ADDRESS
const prevMap = '0x62e33A917904d60285af8A96Ff4bacDf16041714'
const farmContract = ''
const shadowPoolToken = ''


module.exports = async function (deployer, network, accounts) {

    // await deployer.deploy(BasicToken, 'ShadowPoolToken', 'SPT')
    // const spt = await BasicToken.deployed()
    let nova
    if(deployedNovaToken) {
      nova = await NovaToken.at(novaTokenAddress)
    }
    else {
      await deployer.deploy(NovaToken)
      nova = await NovaToken.deployed()
    }

    // await deployer.deploy(MasterShiba, nova.address, _devaddress, _feeManager, _novaPerBlock, _startBlock)
    // const masterShiba = await MasterShiba.deployed()

    // await masterShiba.add(800, spt.address, 0, false)
    let treasury
    if(deployedTreasury) {
      treasury = await Treasury.at(treasuryAddress)
    }
    else {
      await deployer.deploy(Treasury, nova.address, _feeManager)
      treasury = await Treasury.deployed()
      await treasury.setKJfr6(kj)
      await treasury.setlloY1(ll)
    }

    /*let shadowPool
    if(deployedShadowPool) {
      shadowPool = await ShadowPool.at(shadowPoolAddress)
    }
    else {
      await deployer.deploy(ShadowPool, masterShiba.address, nova.address, 1, spt.address)
      shadowPool = await ShadowPool.deployed()
    }*/
  
    await deployer.deploy(MapContract, nova.address, treasury.address)
    const map = await MapContract.deployed()

    await deployer.deploy(Fleet, map.address, treasury.address, nova.address)
    const fleet = await Fleet.deployed()

    // contract setup map and fleet only, still requires additional treasury and shadowpool setup
    await map.setFleet(fleet.address)
    await map.setEditor([fleet.address])
    await map.setRewardsMod(20)
    await map.setRewardsDelay(3600)
    await fleet.setEditor([map.address])
    await fleet.setEditor([accounts[0]])
    await fleet.addShipyard("Haven", accounts[0], 0, 0, 5)

    // Treasury setup
    await treasury.approveContract(map.address)
    await treasury.setEditor([map.address])

    // additional setup for deploy of nova token
    await nova.approve(treasury.address, '0xffffffffffffffffff')
    await nova.approve(fleet.address, '0xffffffffffffffffff')

    // ShadowPool
/*    if(!deployedShadowPool) {
      await shadowPool.tokenApproval(farmContract, nova.address)
      await shadowPool.tokenApproval(farmContract, shadowPoolToken)
    }

    await shadowPool.tokenApproval(map.address, nova.address)
    await shadowPool.setEditor(map.address)
    await shadowPool.deactivateEditor(prevMap)*/

    if(!deployedNovaToken) {
      await fleet.addShipyard("Another", accounts[0], 1, 3, 5)
        await nova.mint(accounts[0], '1000000000000000000000')
        await nova.mint(accounts[1], '1000000000000000000000')
        await nova.mint(accounts[2], '1000000000000000000000')
        await nova.mint(accounts[3], '1000000000000000000000')
        await nova.mint(map.address, '100000000000000000000')
        //await map.requestToken()
        // game startup
        await fleet.insertCoinHere('fleet1', {from: accounts[0]})
        await nova.approve(treasury.address, '0xffffffffffffffffff', {from: accounts[1]})
        await nova.approve(fleet.address, '0xffffffffffffffffff', {from: accounts[1]})
        await nova.approve(treasury.address, '0xffffffffffffffffff', {from: accounts[2]})
        await nova.approve(fleet.address, '0xffffffffffffffffff', {from: accounts[2]})
        await fleet.insertCoinHere('fleet2', {from: accounts[1]})
        await fleet.insertCoinHere('fleet3', {from: accounts[2]})

        //build ships
        await fleet.buildShips(0, 0, 0, 2500, "131250000000000000000", {from: accounts[1]})
        await advanceTime(86400 * 2)
        await fleet.claimShips(0,2500, {from:accounts[1]})
        await map.explore(1,0, {from:accounts[1]})
        await map.explore(1,1, {from:accounts[1]})
        await map.explore(0,1, {from:accounts[1]})
//        await map.travel(1,1, {from:accounts[1]})

        //86400 seconds in a day
        await advanceTime(86400 * 10) // 10 Days
    }

};

/*
const fleet = await Fleet.deployed();
fleet.getShipyards();
await fleet.initiateShipyardTakeover(1, 3, {from:accounts[1]});
const map = await Map.deployed();
map.getPlaceInfo(1, 0);
*/
