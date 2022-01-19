const { assert } = require('chai');
const { default: Web3 } = require('web3');

const Fleet = artifacts.require('Fleet')
const NovaToken = artifacts.require('NovaToken')
const MapContract = artifacts.require('Map')
const Treasury = artifacts.require('Treasury')
// const ShadowPool = artifacts.require('ShadowPool')
// const BasicToken = artifacts.require('BasicToken')
// const MasterShiba = artifacts.require('MasterShiba')
 

require('chai')
    .use(require('chai-as-promised'))
    .should()



contract('GameTest', ([owner, player1, player2, player3, feeManager]) => {
    let nova, map, fleet, treasury

    before(async () => {
    // load contracts
    nova = await NovaToken.new()
    //basicToken = await BasicToken.new('BasicToken', "BT")
    treasury = await Treasury.new(nova.address, feeManager)
    map = await MapContract.new(nova.address, treasury.address)
    fleet = await Fleet.new(map.address, treasury.address, nova.address)


    // mint nova tokens to players
    await nova.mint(player1, '10000000000000000000000')
    await nova.mint(player2, '10000000000000000000000', {from: owner})
    await nova.mint(player3, '10000000000000000000000', {from: owner})

    // set treasury address to owner
    await map.setFleet(fleet.address)

    })

    describe('Initial Nova Token Balances', async () => {

        it('sends 10,000 tokens to players 1, 2 and 3, the owner should have 0', async () => {
            let result

            result = await nova.balanceOf(owner)
            assert.equal(result.toString(), '0', 'owner starts with 0 NOVA')

            result = await nova.balanceOf(player1)
            assert.equal(result.toString(), '10000000000000000000000', 'player 1 has 10,000 NOVA')

            result = await nova.balanceOf(player2)
            assert.equal(result.toString(), '10000000000000000000000', 'player2 has 10,000 NOVA')

            result = await nova.balanceOf(player3)
            assert.equal(result.toString(), '10000000000000000000000', 'player2 has 10,000 NOVA')
        })
    })

    describe('Game Interaction', async () => {

        it('creates fleet for new player', async () => {
            let result

            await fleet.insertCoinHere('SuperJon', {from: player1})
            result = await fleet.addressToName(player1)
            assert.equal(result, 'SuperJon', 'player1 fleet is name SuperJon')

        })

    })

})