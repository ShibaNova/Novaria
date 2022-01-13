const PlaceManager = artifacts.require('PlaceManager')
const NovaToken = artifacts.require('NovaToken')
const ShadowPool = artifacts.require('ShadowPool')
const MapContract = artifacts.require('Map')
const Treasury = artifacts.require('Treasury')
const MasterShiba = artifacts.require('MasterShiba')
const BasicToken = artifacts.require('BasicToken')

const _feeManager = '0xBF08a58d52b8bd98616760C6eEF23625329f7b0B'
const _devaddress = '0x729F3cA74A55F2aB7B584340DDefC29813fb21dF'
const _novaPerBlock = '1000000000000000000'
const _startBlock = '15802444'

module.exports = async function (deployer, network, accounts) {

    await deployer.deploy(BasicToken, 'ShadowPoolToken', 'SPT')
    const spt = await BasicToken.deployed()

    await deployer.deploy(NovaToken)
    const nova = await NovaToken.deployed()

    await deployer.deploy(MasterShiba, nova.address, _devaddress, _feeManager, _novaPerBlock, _startBlock)
    const masterShiba = await MasterShiba.deployed()

    await masterShiba.add(800, spt.address, 0, false)

    await deployer.deploy(Treasury, nova.address, _feeManager)
    const treasury = await Treasury.deployed()

    await deployer.deploy(ShadowPool, masterShiba.address, nova.address, 1, spt.address)
    const shadowPool = await ShadowPool.deployed()
  
    await deployer.deploy(MapContract, treasury.address)
    const map = await MapContract.deployed()

    await deployer.deploy(PlaceManager, map.address, nova.address, shadowPool.address)
    const placeManager = await PlaceManager.deployed()

    await map.setPlaceManager(placeManager.address)
};
